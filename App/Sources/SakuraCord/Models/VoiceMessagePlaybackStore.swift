import CryptoKit
import Foundation
import MediaPipeline
import MessageRendering
import Observation
import OSLog
import SakuraCordModels

nonisolated enum VoiceMessagePlaybackID: Hashable, Sendable {
    case attachment(String)
    case composer(MessageComposerDestination)
}

/// Owns voice-message playback for the timeline and composer previews.
///
/// Like Discord, one voice message plays at a time; starting another pauses
/// the first. Speed is device-local and shared by every player.
@MainActor
@Observable
final class VoiceMessagePlaybackStore {
    enum Source: Equatable {
        case local(URL)
        case remote(URL)
    }

    enum Phase: Equatable {
        case loading
        case playing
        case paused
    }

    /// Discord's cycle order for the speed button.
    static let speeds: [Float] = [1, 1.5, 2, 0.75]
    static let speedDefaultsKey = "VoiceMessagePlaybackSpeed"
    static let maximumCachedPlayers = 4
    static let maximumPrefetchedURLs = 512
    /// Starts quicker than this show no spinner, so resuming doesn't flicker.
    static let startSpinnerDelay: Duration = .milliseconds(150)
    /// Discord remembers where up to 25 messages were left.
    static let maximumResumePositions = 25

    private(set) var activeID: VoiceMessagePlaybackID?
    private(set) var phase: Phase = .paused
    private(set) var speed: Float {
        didSet { player?.rate = speed }
    }

    @ObservationIgnored private var player: VoiceMessagePlayer?
    @ObservationIgnored private var activeSource: Source?
    @ObservationIgnored private var activeDuration: TimeInterval?
    @ObservationIgnored private var pausedPosition: TimeInterval = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Players for recently played messages, oldest first, kept
    /// open so returning to one starts at once.
    @ObservationIgnored private var cachedPlayers: [(source: Source, player: VoiceMessagePlayer)] = []
    @ObservationIgnored private var prefetchedURLs: Set<URL> = []
    /// When play was last pressed, to tell a slow start from a quick one.
    @ObservationIgnored private var playRequestedAt: ContinuousClock.Instant?
    @ObservationIgnored private var resumesAfterScrub = false
    @ObservationIgnored private var resumePositions: [String: TimeInterval] = [:]
    @ObservationIgnored private var resumeOrder: [String] = []
    @ObservationIgnored private let defaults: UserDefaults
    /// Re-signs an expiring Discord attachment link before it is fetched.
    @ObservationIgnored var resolveRemoteURL: (@MainActor (URL) async -> URL)?
    @ObservationIgnored var onError: (@MainActor (String) -> Void)?

    private static let logger = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "VoiceMessagePlayback")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.float(forKey: Self.speedDefaultsKey)
        speed = Self.speeds.contains(stored) ? stored : 1
    }

    // MARK: Queries

    func isActive(_ id: VoiceMessagePlaybackID) -> Bool { activeID == id }

    func phase(of id: VoiceMessagePlaybackID) -> Phase? { activeID == id ? phase : nil }

    /// The live position of the active item, or a remembered position.
    func position(of id: VoiceMessagePlaybackID) -> TimeInterval {
        if activeID == id { return player?.isPlaying == true ? player?.currentTime ?? pausedPosition : pausedPosition }
        if case let .attachment(attachmentID) = id { return resumePositions[attachmentID] ?? 0 }
        return 0
    }

    func duration(of id: VoiceMessagePlaybackID) -> TimeInterval? {
        activeID == id ? player?.duration ?? activeDuration : nil
    }

    /// Whether `id` is fetching, or was pressed and hasn't sounded yet.
    func isLoading(_ id: VoiceMessagePlaybackID) -> Bool {
        guard activeID == id else { return false }
        if phase == .loading { return true }
        guard phase == .playing, player?.isRendering == false, let playRequestedAt else { return false }
        return ContinuousClock.now - playRequestedAt > Self.startSpinnerDelay
    }

    var outputLevel: Float { phase == .playing ? player?.outputLevel ?? 0 : 0 }

    var speedLabel: String { Self.label(for: speed) }

    static func label(for speed: Float) -> String {
        switch speed {
        case 1.5: "1.5×"
        case 2: "2×"
        case 0.75: "0.75×"
        default: "1×"
        }
    }

    // MARK: Observation for AppKit

    /// Posted with the store as its object whenever the active item, its
    /// phase, position, or the speed changes. Timeline canvases observe it.
    static let didChange = Notification.Name("VoiceMessagePlaybackStore.didChange")

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: Control

    func toggle(_ id: VoiceMessagePlaybackID, source: Source, duration: TimeInterval?) {
        if activeID == id {
            switch phase {
            case .playing: pause()
            case .loading: cancelActive(rememberingPosition: true)
            case .paused: play()
            }
            return
        }
        activate(id, source: source, duration: duration)
        play()
    }

    /// Moves the playhead; a paused message stays paused, as in Discord.
    func seek(_ id: VoiceMessagePlaybackID, source: Source, duration: TimeInterval?, fraction: Double) {
        if activeID != id { activate(id, source: source, duration: duration) }
        let total = self.duration(of: id) ?? duration ?? 0
        let target = min(max(0, fraction), 1) * total
        pausedPosition = target
        player?.seek(to: target)
        notify()
    }

    func beginScrub(_ id: VoiceMessagePlaybackID, source: Source, duration: TimeInterval?) {
        if activeID != id { activate(id, source: source, duration: duration) }
        resumesAfterScrub = phase == .playing
        if phase == .playing { pause() }
    }

    func endScrub(_ id: VoiceMessagePlaybackID) {
        guard activeID == id, resumesAfterScrub else { return }
        resumesAfterScrub = false
        play()
    }

    func cycleSpeed() {
        let index = Self.speeds.firstIndex(of: speed) ?? 0
        speed = Self.speeds[(index + 1) % Self.speeds.count]
        defaults.set(speed, forKey: Self.speedDefaultsKey)
        notify()
    }

    /// Fetches a visible message into the media cache, like an image, so
    /// playing it doesn't wait for the download. Expired links are left
    /// for playback to re-sign.
    func prefetch(_ url: URL) {
        guard !DiscordAttachmentLink.needsRefresh(url, now: .now), prefetchedURLs.insert(url).inserted else { return }
        if prefetchedURLs.count > Self.maximumPrefetchedURLs { prefetchedURLs.removeAll() }
        Task.detached(priority: .utility) {
            _ = try? await SharedMediaDataLoader.shared.cachedFile(for: url, priority: .prefetch)
        }
    }

    /// Stops `id` if it is active, forgetting its position.
    func stop(_ id: VoiceMessagePlaybackID) {
        guard activeID == id else { return }
        cancelActive(rememberingPosition: false)
    }

    func stopAll() {
        cancelActive(rememberingPosition: false)
        cachedPlayers.removeAll()
        resumePositions.removeAll()
        resumeOrder.removeAll()
    }

    // MARK: Internals

    private func activate(_ id: VoiceMessagePlaybackID, source: Source, duration: TimeInterval?) {
        cancelActive(rememberingPosition: true)
        activeID = id
        activeSource = source
        activeDuration = duration
        pausedPosition = position(ofInactive: id)
        phase = .paused
        notify()
    }

    private func position(ofInactive id: VoiceMessagePlaybackID) -> TimeInterval {
        guard case let .attachment(attachmentID) = id else { return 0 }
        return resumePositions[attachmentID] ?? 0
    }

    private func play() {
        guard let id = activeID else { return }
        if let player {
            start(player)
            return
        }
        guard let source = activeSource else { return }
        if let index = cachedPlayers.firstIndex(where: { $0.source == source }) {
            adopt(cachedPlayers.remove(at: index).player, for: id)
            return
        }
        phase = .loading
        notify()
        loadTask = Task { [weak self] in
            do {
                let fileURL = try await Self.playableFile(for: source, resolve: self?.resolveRemoteURL)
                try Task.checkCancellation()
                guard let self, self.activeID == id else { return }
                self.loadTask = nil
                self.adopt(try VoiceMessagePlayer(fileURL: fileURL), for: id)
            } catch is CancellationError {
            } catch {
                guard let self, self.activeID == id else { return }
                Self.logger.error("Voice message playback failed: \(error.localizedDescription, privacy: .public)")
                self.loadTask = nil
                self.phase = .paused
                self.notify()
                self.onError?("This voice message couldn't be played.")
            }
        }
    }

    private func adopt(_ player: VoiceMessagePlayer, for id: VoiceMessagePlaybackID) {
        player.rate = speed
        player.onFinish = { [weak self] in self?.finish(id) }
        player.onInterruption = { [weak self] in self?.interrupted(id) }
        self.player = player
        activeDuration = player.duration
        if pausedPosition > 0 { player.seek(to: pausedPosition) }
        start(player)
    }

    private func start(_ player: VoiceMessagePlayer) {
        if pausedPosition >= player.duration - 0.05 { pausedPosition = 0 }
        player.seek(to: pausedPosition)
        playRequestedAt = .now
        do {
            try player.play()
            phase = .playing
        } catch {
            phase = .paused
            onError?("This voice message couldn't be played.")
        }
        notify()
    }

    private func pause() {
        guard let player, phase == .playing else { return }
        player.pause()
        pausedPosition = player.currentTime
        phase = .paused
        notify()
    }

    private func interrupted(_ id: VoiceMessagePlaybackID) {
        guard activeID == id, let player, phase == .playing else { return }
        pausedPosition = player.currentTime
        phase = .paused
        notify()
    }

    private func finish(_ id: VoiceMessagePlaybackID) {
        guard activeID == id else { return }
        if case let .attachment(attachmentID) = id { forgetResumePosition(attachmentID) }
        if let player, let activeSource { cache(player, for: activeSource) }
        player = nil
        activeID = nil
        activeSource = nil
        activeDuration = nil
        pausedPosition = 0
        phase = .paused
        notify()
    }

    private func cancelActive(rememberingPosition: Bool) {
        guard let id = activeID else { return }
        loadTask?.cancel()
        loadTask = nil
        let position = player?.isPlaying == true ? player?.currentTime ?? pausedPosition : pausedPosition
        let duration = player?.duration ?? activeDuration ?? 0
        if let player, let activeSource { cache(player, for: activeSource) }
        player = nil
        if case let .attachment(attachmentID) = id {
            if rememberingPosition, position > 0.5, duration > 0, position < duration * 0.95 {
                rememberResumePosition(position, for: attachmentID)
            } else {
                forgetResumePosition(attachmentID)
            }
        }
        activeID = nil
        activeSource = nil
        activeDuration = nil
        pausedPosition = 0
        phase = .paused
        notify()
    }

    /// Pauses a player that is no longer active and keeps it for a remote
    /// message; a composer preview's file is about to go away.
    private func cache(_ player: VoiceMessagePlayer, for source: Source) {
        player.onFinish = nil
        player.onInterruption = nil
        guard case .remote = source else {
            player.stop()
            return
        }
        player.pause()
        cachedPlayers.removeAll { $0.source == source }
        cachedPlayers.append((source, player))
        if cachedPlayers.count > Self.maximumCachedPlayers {
            cachedPlayers.removeFirst().player.stop()
        }
    }

    private func rememberResumePosition(_ position: TimeInterval, for attachmentID: String) {
        resumePositions[attachmentID] = position
        resumeOrder.removeAll { $0 == attachmentID }
        resumeOrder.append(attachmentID)
        while resumeOrder.count > Self.maximumResumePositions {
            resumePositions[resumeOrder.removeFirst()] = nil
        }
    }

    private func forgetResumePosition(_ attachmentID: String) {
        resumePositions[attachmentID] = nil
        resumeOrder.removeAll { $0 == attachmentID }
    }

    /// AVAudioFile needs a file, so remote audio plays from its file in the
    /// shared media cache, under the same budget and Clear Cache as images.
    private static func playableFile(
        for source: Source,
        resolve: (@MainActor (URL) async -> URL)?
    ) async throws -> URL {
        switch source {
        case let .local(url):
            return url
        case let .remote(url):
            let resolved = await resolve?(url) ?? url
            if let file = try await SharedMediaDataLoader.shared.cachedFile(for: resolved) { return file }
            // Without a disk cache, a private copy stands in.
            let data = try await SharedMediaDataLoader.shared.data(for: resolved)
            try Task.checkCancellation()
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "SakuraCordVoicePlayback", directoryHint: .isDirectory)
            let digest = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
            let fileURL = directory.appending(path: "\(digest).ogg")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }
}
