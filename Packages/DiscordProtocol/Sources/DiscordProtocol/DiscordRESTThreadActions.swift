import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    /// The first-party thread browser's REST reads, through the same
    /// `threads/search` builders and caches as the forum catalogue. Archived
    /// pages hold 25 records; a name search returns active and archived matches.
    public func threadBrowserPage(in parentID: ChannelID, query: ThreadBrowserQuery) async throws
        -> ForumPostPage
    {
        guard
            let channel = cachedChannels.values.lazy.flatMap(\.self).first(where: {
                $0.id == parentID && [.text, .announcement, .forum].contains($0.kind)
            })
        else { throw ChatProviderError.channelNotFound }
        var catalogueQuery = ForumPostQuery(
            sortOrder: .latestActivity,
            selectedTagIDs: query.selectedTagIDs,
            tagMatch: query.tagMatch,
            limit: ThreadBrowserQuery.pageSize,
            requiresFreshPage: true
        )
        switch query.scope {
        case .archived(let offset):
            catalogueQuery.offset = max(0, offset)
            return try await olderForumPosts(channel: channel, query: catalogueQuery)
        case .search(let text):
            catalogueQuery.scope = .search(text)
            return try await searchedForumPosts(channel: channel, query: catalogueQuery, searchText: text)
        }
    }

    /// Active threads from READY, THREAD_LIST_SYNC, THREAD_CREATE and earlier
    /// reads. Joined threads carry their member's notification settings.
    public func activeThreads(in parentID: ChannelID) async -> [ForumPost] {
        cachedForumPosts[parentID, default: [:]].values
            .filter { !$0.thread.isArchived }
            .sorted {
                $0.lastActivityAt != $1.lastActivityAt
                    ? $0.lastActivityAt > $1.lastActivityAt
                    : $0.id > $1.id
            }
    }

    /// A confirmed join or leave updates known threads at once. A member the
    /// Gateway already delivered is kept; it carries Discord's join timestamp.
    func reconcileConfirmedThreadMembership(threadID: ChannelID, isJoined: Bool) {
        for (parentID, posts) in cachedForumPosts {
            guard var post = posts[threadID] else { continue }
            guard isJoined != (post.thread.notificationSettings != nil) else { return }
            if isJoined {
                post.thread.notificationSettings = ThreadNotificationSettings(joinedAt: .now)
                cachedForumPosts[parentID]?[threadID] = post
                reconcileJoinedThread(post.thread)
            } else {
                post.thread.notificationSettings = nil
                cachedForumPosts[parentID]?[threadID] = post
                cachedJoinedThreads[threadID] = nil
                cachedJoinedThreadOrder.removeAll { $0 == threadID }
            }
            publishForumPosts(parentID: parentID)
            publishActiveJoinedThreads()
            return
        }
    }

    /// A thread started from a message shares that message's ID. Discord's
    /// starter `MESSAGE_UPDATE` carries only the has-thread flag, so attach the
    /// known thread to a cached starter that lacks it.
    func attachStartedThreadToCachedStarter(_ threadID: ChannelID) {
        let messageID = MessageID(rawValue: threadID.rawValue)
        guard var message = cachedMessages[messageID], message.thread == nil,
              let thread = cachedForumPosts[message.channelID]?[threadID]?.thread
        else { return }
        message.thread = thread
        message.flags.insert(.hasThread)
        cachedMessages[messageID] = message
        continuation?.yield(.messageUpdated(message))
    }

    /// The same reconciliation for a starter update that arrives after the
    /// thread is known, including for an uncached starter.
    func attachKnownStartedThread(to update: inout MessageUpdate) {
        guard update.thread == nil, update.flags?.contains(.hasThread) == true,
              let thread = cachedForumPosts[update.channelID]?[
                  ChannelID(rawValue: update.messageID.rawValue)
              ]?.thread
        else { return }
        update.thread = .some(thread)
    }
}
