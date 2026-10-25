import DiscordProtocol
import SakuraCordModels

extension AppModel {
    /// Discord offers Close DM on 1:1 DMs only; a group DM is left instead.
    func offersCloseDirectMessage(_ channel: Channel) -> Bool {
        channel.guildID == nil && channel.kind == .directMessage
    }

    /// Closes a 1:1 DM without confirmation, as Discord does. The provider
    /// removes it from the DM list, which moves a selection on it to the next
    /// conversation; failures use the workspace error alert and keep the DM.
    func closeDirectMessage(_ channel: Channel) {
        let store = groupDirectMessageLeave
        guard offersCloseDirectMessage(channel), !accountTransitionIsActive,
              store.leaving.insert(channel.id).inserted
        else { return }
        startAccountChildTask(account: accountSession(allowsTransition: true)) { model, session in
            defer {
                if model.isCurrentAccountSession(session) { store.leaving.remove(channel.id) }
            }
            guard !model.accountTransitionIsActive else { return }
            do {
                try await session.provider.closeDirectMessage(channel.id)
            } catch is CancellationError {
                return
            } catch {
                guard model.isCurrentAccountSession(session), !model.accountTransitionIsActive else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                model.errorMessage = "SakuraCord couldn’t close \(channel.name). \(error.localizedDescription)"
            }
        }
    }
}
