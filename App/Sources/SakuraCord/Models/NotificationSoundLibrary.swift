import AVFAudio
import Foundation
import OSLog

/// Which notification sound a stored choice controls.
nonisolated enum NotificationSoundKind: CaseIterable, Sendable {
    case message
    case call

    var defaultEffect: AppSoundEffect {
        switch self {
        case .message: .message
        case .call: .callRinging
        }
    }

    var label: String {
        switch self {
        case .message: "Message"
        case .call: "Call"
        }
    }
}

nonisolated enum NotificationSoundKeys {
    static let messageSoundID = "notifications.messageSound"
    static let messageSoundBookmark = "notifications.messageSoundBookmark"
    static let messageSoundName = "notifications.messageSoundName"
    static let callRingtoneID = "notifications.callRingtone"
    static let callRingtoneBookmark = "notifications.callRingtoneBookmark"
    static let callRingtoneName = "notifications.callRingtoneName"
}

nonisolated enum NotificationSoundLibrary {
    static let bundledID = "bundled"
    static let customID = "custom"
    static let chooseFileID = "choose-file"
    private static let systemPrefix = "system:"
    private static let systemSoundsDirectory = "/System/Library/Sounds"

    static func systemID(for name: String) -> String { "\(systemPrefix)\(name)" }

    /// The stored choice for one sound, read from NotificationPreferences.
    struct Choice: Equatable, Sendable {
        var soundID: String
        var bookmark: Data?
    }

    /// A resolved sound file. `isSecurityScoped` means the caller must start
    /// and later stop access to `url`; `isStaleBookmark` means the bookmark
    /// should be re-created and saved.
    struct Resolution: Sendable {
        var url: URL
        var isSecurityScoped: Bool
        var isStaleBookmark: Bool
    }

    /// Listed once: /System/Library/Sounds does not change while the app runs.
    static let systemAlertSounds: [String] =
        ((try? FileManager.default.contentsOfDirectory(atPath: systemSoundsDirectory)) ?? [])
            .filter { $0.hasSuffix(".aiff") || $0.hasSuffix(".aif") || $0.hasSuffix(".wav") }
            .sorted()

    static let systemAlertSoundNames: [String] =
        systemAlertSounds.map { ($0 as NSString).deletingPathExtension }

    static func displayName(soundID: String, customName: String) -> String {
        if soundID == bundledID {
            return "Default"
        }
        if soundID.hasPrefix(systemPrefix) {
            return String(soundID.dropFirst(systemPrefix.count))
        }
        if soundID == customID {
            return customName.isEmpty ? "Custom file" : customName
        }
        return "Default"
    }

    static func defaultURL(kind: NotificationSoundKind) -> URL {
        kind.defaultEffect.resourceURL
            ?? URL(fileURLWithPath: systemSoundsDirectory).appendingPathComponent("Glass.aiff")
    }

    /// Resolves the chosen file without touching it. A custom file's
    /// existence can only be checked after security-scoped access starts,
    /// so the caller falls back to `defaultURL` when opening it fails.
    static func resolve(_ choice: Choice, kind: NotificationSoundKind) -> Resolution {
        if choice.soundID.hasPrefix(systemPrefix) {
            let name = String(choice.soundID.dropFirst(systemPrefix.count))
            if let match = systemAlertSounds.first(where: { ($0 as NSString).deletingPathExtension == name }) {
                return Resolution(
                    url: URL(fileURLWithPath: systemSoundsDirectory).appendingPathComponent(match),
                    isSecurityScoped: false,
                    isStaleBookmark: false
                )
            }
        } else if choice.soundID == customID, let bookmark = choice.bookmark, !bookmark.isEmpty {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return Resolution(url: url, isSecurityScoped: true, isStaleBookmark: isStale)
            }
        }
        return Resolution(url: defaultURL(kind: kind), isSecurityScoped: false, isStaleBookmark: false)
    }
}

/// Notification Center plays `UNNotificationSound(named:)` files from the
/// app's `Library/Sounds`, so a custom choice is exported there as a CAF.
nonisolated extension NotificationSoundLibrary {
    private static let logger = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "Notifications")
    /// Notification Center ignores sounds of 30 seconds or longer.
    private static let bannerMaximumSeconds = 29.0
    private static let bannerChunkFrames: AVAudioFrameCount = 32_768

    static func bannerSoundName(kind: NotificationSoundKind) -> String {
        switch kind {
        case .message: "SakuraCord-message.caf"
        case .call: "SakuraCord-call.caf"
        }
    }

    static func bannerSoundURL(kind: NotificationSoundKind) -> URL {
        URL.libraryDirectory
            .appending(path: "Sounds", directoryHint: .isDirectory)
            .appending(path: bannerSoundName(kind: kind), directoryHint: .notDirectory)
    }

    /// Replaces the exported copy with the current choice, or removes it for
    /// the default sound. A source longer than the limit is trimmed, so the
    /// banner plays its start while in-app playback keeps the full file.
    static func exportBannerSound(_ choice: Choice, kind: NotificationSoundKind) {
        guard !Task.isCancelled else { return }
        let destination = bannerSoundURL(kind: kind)
        guard choice.soundID != bundledID else {
            try? FileManager.default.removeItem(at: destination)
            return
        }
        let resolution = resolve(choice, kind: kind)
        let isScoped = resolution.isSecurityScoped && resolution.url.startAccessingSecurityScopedResource()
        defer { if isScoped { resolution.url.stopAccessingSecurityScopedResource() } }
        let temporary = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try convertToLinearPCM(from: resolution.url, to: temporary)
            // A newer choice's export owns the destination.
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            // A cancelled export has been superseded, so the newer copy is not its to remove.
            guard !Task.isCancelled else { return }
            // Without a copy the banner keeps the bundled sound.
            try? FileManager.default.removeItem(at: destination)
            let nsError = error as NSError
            logger.error("\(kind.label) banner sound export failed; domain=\(nsError.domain, privacy: .public), code=\(nsError.code)")
        }
    }

    private static func convertToLinearPCM(from source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let output = try AVAudioFile(
            forWriting: destination,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ]
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bannerChunkFrames) else { return }
        let limit = min(input.length, AVAudioFramePosition(format.sampleRate * bannerMaximumSeconds))
        while input.framePosition < limit {
            let remaining = AVAudioFrameCount(limit - input.framePosition)
            try input.read(into: buffer, frameCount: min(bannerChunkFrames, remaining))
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }
}
