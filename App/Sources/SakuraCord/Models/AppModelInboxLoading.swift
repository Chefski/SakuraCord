import DiscordProtocol
import SakuraCordModels

extension AppModel {
    func loadInboxMentionPage(query: InboxMentionQuery, before: MessageID?, session: AppModelAccountSession, generation: UInt64) async throws {
        let page = try await session.provider.inboxMentions(query, before: before)
        guard !Task.isCancelled, isCurrentAccountSession(session), inbox.generation == generation else { return }
        for thread in page.threads { inbox.threads[thread.id] = thread }
        var combined = Dictionary(uniqueKeysWithValues: inbox.mentions.map { ($0.id, $0) })
        for message in page.messages where !inbox.removedIDs.contains(message.id) {
            combined[message.id] = inbox.replacements[message.id] ?? message
        }
        inbox.mentions = combined.values.sorted { $0.id > $1.id }
        inbox.nextBefore = page.nextBefore
        inbox.hasMore = page.hasMore && page.nextBefore != nil && page.nextBefore != before
    }

    func loadInboxGroup(_ group: InboxUnreadGroup, session: AppModelAccountSession, generation: UInt64) async throws {
        if group.isEvents {
            try await loadInboxEvents(group, session: session, generation: generation)
        } else if group.isForum {
            try await loadInboxForum(group, session: session, generation: generation)
        } else {
            try await loadInboxMessages(group, session: session, generation: generation)
        }
    }

    func loadInboxMessages(_ group: InboxUnreadGroup, session: AppModelAccountSession, generation: UInt64) async throws {
        var anchor = group.oldestReadMessageID.map(MessageHistoryAnchor.around) ?? .newest
        var collected: [MessageID: Message] = [:]
        var previousCursor: MessageID?
        while true {
            let page = try await session.provider.messagesForImmediatePresentation(
                in: group.channelID, anchoredAt: anchor, limit: 30
            )
            guard !Task.isCancelled, isCurrentAccountSession(session), inbox.generation == generation else { return }
            for message in page.messages where message.id > (group.oldestReadMessageID ?? MessageID(rawValue: 0))
                && message.id <= group.newestUnreadMessageID {
                collected[message.id] = message
            }
            guard collected.count < 25, page.hasMoreAfter,
                  let cursor = page.messages.map(\.id).max(), cursor < group.newestUnreadMessageID,
                  cursor != previousCursor else { break }
            previousCursor = cursor
            anchor = .after(cursor)
        }
        guard let index = inbox.groups.firstIndex(where: { $0.id == group.id }) else { return }
        inbox.groups[index].messages = Array(collected.values.filter {
            !inbox.deletedIDs.contains($0.id)
        }.sorted { $0.id < $1.id }.prefix(25)).map { inbox.replacements[$0.id] ?? $0 }
        inbox.groups[index].isLoaded = true
        inbox.groups[index].errorMessage = nil
        inbox.hasMore = inbox.groups.contains { !$0.isLoaded && !$0.isCollapsed }
    }
}
