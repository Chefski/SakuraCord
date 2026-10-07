import Foundation
import DiscordProtocol
import SakuraCordModels

extension AppModel {
    func loadThreadMembers(_ thread: MessageThreadSummary) async throws {
        guard openThread?.id == thread.id, openThreadAccess.isReadable, !thread.isArchived else { return }
        let account = accountSession()
        do {
            var request = thread
            request.guildID = thread.guildID ?? openThreadParentChannel?.guildID
            let members = try await account.provider.threadMembers(in: request)
            guard !Task.isCancelled, isCurrentAccountSession(account),
                  openThread?.id == thread.id, openThreadAccess.isReadable else { return }
            if let members { threadMembersByID[thread.id] = members }
        } catch {
            guard isCurrentAccountSession(account) else { throw CancellationError() }
            throw error
        }
    }

    func sidebarThreadPermissions(_ thread: MessageThreadSummary) -> SidebarThreadPermissions {
        let thread = sidebarThread(thread.id) ?? thread
        guard let parent = snapshot?.channels.first(where: { $0.id == thread.parentID }),
              conversationAccess(for: parent).isReadable,
              let permissions = effectiveMessagePermissions(in: parent),
              let currentUserID = currentUser?.id else { return .init() }
        return SidebarThreadPermissions(
            thread: thread, currentUserID: currentUserID,
            permissions: permissions, isForum: parent.kind == .forum
        )
    }

    func canManageSidebarThread(_ thread: MessageThreadSummary) -> Bool {
        sidebarThreadPermissions(thread).canManage
    }

    func canArchiveSidebarThread(_ thread: MessageThreadSummary) -> Bool {
        let permissions = sidebarThreadPermissions(thread)
        return thread.isArchived ? permissions.canReopen : permissions.canClose
    }

    func setSidebarThreadMute(_ thread: MessageThreadSummary, isMuted: Bool, until: Date?) {
        guard sidebarThreadPermissions(thread).canChangeNotifications else { return }
        setForumPostMute(isMuted, until: until, for: ForumPost(thread: thread), reportErrorInAlert: true)
    }

    func setSidebarThreadNotificationLevel(_ thread: MessageThreadSummary, level: MessageNotificationLevel) {
        guard sidebarThreadPermissions(thread).canChangeNotifications else { return }
        setForumPostNotificationLevel(level, for: ForumPost(thread: thread), reportErrorInAlert: true)
    }

    func setSidebarThreadMembership(_ thread: MessageThreadSummary, isJoined: Bool) {
        guard sidebarThreadPermissions(thread).canChangeMembership else { return }
        startAccountChildTask(account: accountSession()) { model, account in
            guard model.sidebarThreadPermissions(thread).canChangeMembership else { return }
            do {
                try await account.provider.setThreadMembership(threadID: thread.id, isJoined: isJoined)
            } catch {
                guard model.isCurrentAccountSession(account) else { return }
                model.errorMessage = error.localizedDescription
            }
        }
    }

    func updateSidebarThread(_ thread: MessageThreadSummary, mutation: ForumPostMutation) {
        switch mutation {
        case .archived(let archived):
            let permissions = sidebarThreadPermissions(thread)
            guard archived ? permissions.canClose : permissions.canReopen else { return }
        case .locked: guard canManageSidebarThread(thread) else { return }
        case .pinned:
            guard canManageSidebarThread(thread),
                  snapshot?.channels.first(where: { $0.id == thread.parentID })?.kind == .forum else { return }
        case .tags: return
        }
        startAccountChildTask(account: accountSession()) { model, account in
            do {
                let updated = try await account.provider.updateForumPost(ForumPost(thread: thread), mutation: mutation)
                guard model.isCurrentAccountSession(account) else { return }
                if model.openThread?.id == thread.id { model.openThread = updated.thread }
            } catch {
                guard model.isCurrentAccountSession(account) else { return }
                model.errorMessage = error.localizedDescription
            }
        }
    }

    func deleteSidebarThread(_ thread: MessageThreadSummary) {
        guard sidebarThreadPermissions(thread).canDelete else { return }
        startAccountChildTask(account: accountSession()) { model, account in
            guard model.sidebarThreadPermissions(thread).canDelete else { return }
            do {
                try await account.provider.deleteForumPost(ForumPost(thread: thread))
                guard model.isCurrentAccountSession(account) else { return }
                model.consumeThreadDeleted(channelID: thread.id)
            } catch {
                guard model.isCurrentAccountSession(account) else { return }
                model.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Eligibility shared by menu construction and action execution. Thread permissions
/// inherit from the actual parent, independently of the selected conversation.
nonisolated struct SidebarThreadPermissions {
    var canRead = false
    var canManage = false
    var canClose = false
    var canReopen = false
    var canDelete = false
    var canChangeMembership = false
    var canChangeNotifications = false

    init() {}

    init(thread: MessageThreadSummary, currentUserID: UserID, permissions: UInt64, isForum: Bool) {
        guard permissions & DiscordPermissionBits.viewChannel != 0 else { return }
        let managesThreads = permissions & DiscordPermissionBits.manageThreads != 0
        guard !thread.isPrivate || thread.notificationSettings != nil || managesThreads else { return }
        canRead = true
        canManage = managesThreads
        let ownsThread = thread.ownerID == currentUserID
        canClose = canManage || (!thread.isLocked && ownsThread)
        let canSend = permissions & DiscordPermissionBits.sendMessagesInThreads != 0
            && permissions & DiscordPermissionBits.sendMessages != 0
        canReopen = thread.isLocked ? canManage : canSend
        // A regular thread's creator cannot delete it. Forum authors may delete
        // an empty post; deleting only its starter once replies exist is distinct.
        canDelete = canManage || (isForum && ownsThread && thread.messageCount == 0)
        canChangeMembership = thread.notificationSettings != nil || !thread.isArchived
        canChangeNotifications = thread.notificationSettings != nil
    }
}
