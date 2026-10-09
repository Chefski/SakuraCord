import CryptoKit
import Foundation
import MediaPipeline
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

    /// Stops `id` if it is active, forgetting its position.
    func stop(_ id: VoiceMessagePlaybackID) {
        guard activeID == id else { return }
        cancelActive(rememberingPosition: false)
    }

    func stopAll() {
        cancelActive(rememberingPosition: false)
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
        phase = .loading
        notify()
        loadTask = Task { [weak self] in
            do {
                let fileURL = try await Self.playableFile(for: source, resolve: self?.resolveRemoteURL)
                try Task.checkCancellation()
                guard let self, self.activeID == id else { return }
                let player = try VoiceMessagePlayer(fileURL: fileURL)
                player.rate = self.speed
                player.onFinish = { [weak self] in self?.finish(id) }
                self.player = player
                self.activeDuration = player.duration
                if self.pausedPosition > 0 { player.seek(to: self.pausedPosition) }
                self.loadTask = nil
                self.start(player)
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

    private func start(_ player: VoiceMessagePlayer) {
        if pausedPosition >= player.duration - 0.05 { pausedPosition = 0 }
        player.seek(to: pausedPosition)
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

    private func finish(_ id: VoiceMessagePlaybackID) {
        guard activeID == id else { return }
        if case let .attachment(attachmentID) = id { forgetResumePosition(attachmentID) }
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
        player?.stop()
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

    /// AVAudioFile needs a file, so remote audio is materialized once per URL
    /// path in a disposable directory; the bytes come from the shared cache.
    private static func playableFile(
        for source: Source,
        resolve: (@MainActor (URL) async -> URL)?
    ) async throws -> URL {
        switch source {
        case let .local(url):
            return url
        case let .remote(url):
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "SakuraCordVoicePlayback", directoryHint: .isDirectory)
            let digest = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
            let fileURL = directory.appending(path: "\(digest).ogg")
            if FileManager.default.fileExists(atPath: fileURL.path) { return fileURL }
            let resolved = await resolve?(url) ?? url
            let data = try await SharedMediaDataLoader.shared.data(for: resolved)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }
}
