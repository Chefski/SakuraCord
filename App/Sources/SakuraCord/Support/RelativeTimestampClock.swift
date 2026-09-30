import AppKit
import MessageRendering
import Observation

/// A single clock services attached timestamp surfaces. Listeners own no timers,
/// and weak ownership prevents a retained timer from keeping a view alive.
@MainActor
final class RelativeTimestampClock {
    static let shared = RelativeTimestampClock()

    private struct Listener {
        weak var owner: AnyObject?
        let update: (Date) -> Void
    }

    private var listeners: [ObjectIdentifier: Listener] = [:]
    private var timer: Timer?
    private var observations: [NSObjectProtocol] = []

    func observe(_ owner: AnyObject, update: @escaping (Date) -> Void) {
        listeners[ObjectIdentifier(owner)] = Listener(owner: owner, update: update)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pulse(at: .now) }
        }
        timer.tolerance = 0.1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSLocale.currentLocaleDidChangeNotification,
            NSNotification.Name.NSSystemTimeZoneDidChange,
        ] {
            observations.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.pulse(at: .now) }
            })
        }
    }

    func remove(_ owner: AnyObject) {
        listeners[ObjectIdentifier(owner)] = nil
        stopIfUnused()
    }

    func pulse(at date: Date) {
        listeners = listeners.filter { $0.value.owner != nil }
        // Callbacks may remove a detached view while processing the tick.
        for listener in Array(listeners.values) where listener.owner != nil {
            listener.update(date)
        }
        stopIfUnused()
    }

    private func stopIfUnused() {
        guard listeners.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
    }
}

nonisolated enum TimestampMentionPresentation {
    static func tokens(in source: String) -> [DiscordTimestampToken] {
        RichMessageAttributedText.prepare(source: source).tokens.compactMap { token in
            guard case let .mention(mention) = token, mention.kind == .timestamp else { return nil }
            return DiscordTimestampToken(rawToken: mention.rawToken)
        }
    }

    static func labels(in source: String, at date: Date) -> [String: String] {
        tokens(in: source).reduce(into: [:]) { result, token in
            result[token.rawToken] = token.formatted(relativeTo: date)
        }
    }

    static func refreshed(
        _ presentations: [String: MentionPresentation],
        source: String,
        at date: Date
    ) -> [String: MentionPresentation] {
        var result = presentations
        for token in tokens(in: source) {
            result[token.rawToken] = MentionPresentation(
                rawToken: token.rawToken,
                label: token.formatted(relativeTo: date),
                target: .unresolved,
                isTimestamp: true
            )
        }
        return result
    }
}

@Observable
@MainActor
final class RelativeTimestampDisplayClock {
    var date: Date = .now

    func start() {
        date = .now
        RelativeTimestampClock.shared.observe(self) { [weak self] date in
            self?.date = date
        }
    }

    func stop() { RelativeTimestampClock.shared.remove(self) }
}
