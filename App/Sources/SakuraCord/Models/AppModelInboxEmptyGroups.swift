import Foundation
import SakuraCordModels

extension AppModel {
    @discardableResult
    func dismissEmptyInboxGroups() -> Bool {
        guard inbox.isPresented, inbox.tab == .unread else { return false }
        let empty = inbox.groups.filter {
            $0.isLoaded && !$0.isCollapsed && !$0.isAgeRestricted && $0.errorMessage == nil
                && $0.messages.isEmpty && $0.forumPosts.isEmpty && $0.events.isEmpty
        }
        var removed = false
        for group in empty {
            #if DEBUG
                // Live verification can exercise empty groups without acknowledging
                // unrelated conversations on the configured account.
                if let scope = ProcessInfo.processInfo.environment["SAKURACORD_INBOX_VERIFICATION_GUILD_ID"],
                   group.guildID?.description != scope { continue }
            #endif
            let boundary = group.isForum ? Self.forumAcknowledgementBoundary(at: .now)
                : readState.entries[group.id]?.latestKnownMessageID
            markInboxGroupRead(group.id, allowsUndo: false, acknowledgementBoundary: boundary)
            removed = true
        }
        return removed
    }
}
