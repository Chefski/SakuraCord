import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    /// Discord offers Edit Group to every member of a group DM.
    func canEditGroupDirectMessage(_ channel: Channel) -> Bool {
        channel.guildID == nil && channel.kind == .groupDirectMessage
    }

    func presentGroupDirectMessageEditor(for channelID: ChannelID) {
        guard let channel = snapshot?.channels.first(where: { $0.id == channelID }),
              canEditGroupDirectMessage(channel)
        else { return }
        groupDirectMessageEditor.presentation = GroupDirectMessageEditorStore.Presentation(
            channel: channel,
            placeholder: groupDirectMessagePlaceholder(for: channel)
        )
    }

    /// Discord's untitled group name: members by friend nickname, then name,
    /// or your own group once nobody else remains.
    private func groupDirectMessagePlaceholder(for channel: Channel) -> String {
        guard channel.recipients.isEmpty else {
            return channel.recipients.map { friendNickname(for: $0.id) ?? $0.displayName }.joined(separator: ", ")
        }
        return currentUser.map { "\($0.displayName)'s Group" } ?? "Group Direct Message"
    }

    /// Saves the open dialog once. An unchanged dialog closes without a
    /// request; the provider publishes the saved group, and failures keep the
    /// draft for another try.
    func saveGroupDirectMessage(_ presentation: GroupDirectMessageEditorStore.Presentation) {
        let store = groupDirectMessageEditor
        guard store.presentation == presentation, !store.isSaving else { return }
        let changes = store.changes
        guard changes.hasChanges else {
            store.presentation = nil
            return
        }
        let revision = store.revision
        store.isSaving = true
        store.error = nil
        startAccountChildTask(account: accountSession()) { model, session in
            do {
                _ = try await session.provider.editGroupDirectMessage(presentation.channel.id, changes: changes)
                guard model.isCurrentAccountSession(session), store.revision == revision else { return }
                store.isSaving = false
                store.presentation = nil
            } catch {
                guard model.isCurrentAccountSession(session), store.revision == revision else { return }
                if !(error is CancellationError) {
                    DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                }
                store.isSaving = false
                store.error = error is CancellationError
                    ? "The group change was interrupted. Check the group before trying again."
                    : error.localizedDescription
            }
        }
    }
}
