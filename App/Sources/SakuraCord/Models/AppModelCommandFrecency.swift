import DiscordProtocol
import Foundation
import SakuraCordModels

/// Slash-command usage synced through Discord's frecency settings. Uses stay
/// pending locally and are saved on Discord's own schedule: shortly after the
/// Gateway becomes ready, every two hours, and when the app stops being
/// active or the connection closes.
extension AppModel {
    static let commandFrecencyFlushInterval: Duration = .seconds(2 * 60 * 60)

    /// Discord loads synced usage when the picker first needs it.
    func loadCommandFrecencyIfNeeded() {
        guard !commandComposer.frecencyStore.hasLoadedRemoteHistory, commandFrecencyLoadTask == nil else { return }
        let session = accountSession()
        commandFrecencyLoadTask = Task { [weak self] in
            defer { self?.commandFrecencyLoadTask = nil }
            guard let history = try? await session.provider.applicationCommandFrecency(),
                  let self, isCurrentAccountSession(session)
            else { return }
            commandComposer.applyRemoteFrecency(history)
        }
    }

    func applyRemoteCommandFrecency(_ history: ApplicationCommandFrecencyHistory) {
        commandComposer.applyRemoteFrecency(history)
    }

    /// Discord waits up to ten seconds after (re)connecting, then repeats about
    /// every two hours.
    func scheduleCommandFrecencyFlushAfterConnecting() {
        scheduleCommandFrecencyFlush(after: .milliseconds(10 + Int.random(in: 0 ..< 10_000)))
    }

    func flushCommandFrecencyNow() {
        scheduleCommandFrecencyFlush(after: .zero)
    }

    private func scheduleCommandFrecencyFlush(after delay: Duration) {
        commandFrecencyFlushTask?.cancel()
        commandFrecencyFlushTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            await flushCommandFrecencyIfNeeded()
            guard !Task.isCancelled else { return }
            scheduleCommandFrecencyFlush(
                after: Self.commandFrecencyFlushInterval + .milliseconds(Int.random(in: 0 ..< 600_000))
            )
        }
    }

    /// Saves pending uses on top of the latest synced history, then adopts
    /// what Discord stored.
    func flushCommandFrecencyIfNeeded() async {
        let store = commandComposer.frecencyStore
        guard store.hasPendingUsage, supportedCapabilities.contains(.slashCommands) else { return }
        let session = accountSession()
        if !store.hasLoadedRemoteHistory {
            guard let history = try? await session.provider.applicationCommandFrecency(),
                  isCurrentAccountSession(session)
            else { return }
            commandComposer.applyRemoteFrecency(history)
        }
        let saving = store.pendingUsages
        do {
            let stored = try await session.provider.saveApplicationCommandFrecency(store.historyForSave())
            guard isCurrentAccountSession(session) else { return }
            if store.pendingUsages == saving { store.clearPendingUsages() }
            commandComposer.applyRemoteFrecency(stored)
        } catch {
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
        }
    }
}
