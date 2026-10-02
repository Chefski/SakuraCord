import SakuraCordModels

extension AppModel {
    func applyingMessageUpdate(_ update: MessageUpdate) -> Message? {
        guard var message = retainedMessage(channelID: update.channelID, messageID: update.messageID) else { return nil }
        update.apply(to: &message)
        return message
    }

    /// The workspace copy, or one retained by pins, search, or the Inbox.
    func retainedMessage(channelID: ChannelID, messageID: MessageID) -> Message? {
        if let message = messageInWorkspace(channelID: channelID, messageID: messageID) { return message }
        if let pinned = pinnedMessages.items.first(where: { $0.id == messageID })?.message { return pinned }
        if let search = messageSearch.page?.results.lazy.flatMap(\.messages).first(where: { $0.id == messageID && $0.channelID == channelID }) {
            return search
        }
        return inbox.mentions.first { $0.id == messageID } ?? inbox.groups.lazy.flatMap(\.messages).first { $0.id == messageID }
    }

    func reconcileRetainedMessageIdentities(_ user: User) {
        // Pages still being prepared have no retained message IDs yet. Keep
        // identity changes at conversation scope until their refresh commits.
        for channelID in conversationRefreshJournals.keys {
            conversationRefreshJournals[channelID]?.recordIdentityUpdate(user)
        }
        let retained = messages + threadMessages + messageCache.values.flatMap { $0 }
            + pinnedMessages.items.map(\.message)
            + inbox.mentions + inbox.groups.flatMap(\.messages)
            + forumCataloguePosts.flatMap { [$0.firstMessage, $0.mostRecentMessage].compactMap { $0 } }
        var seen = Set<MessageID>()
        for message in retained where seen.insert(message.id).inserted {
            guard message.author.id == user.id || message.mentionedUsers.contains(where: { $0.id == user.id }) else { continue }
            var update = MessageUpdate(messageID: message.id, channelID: message.channelID)
            update.updatedUsers[user.id] = user
            consumeImmediately(.messagePatched(update))
        }
    }

    func messageInWorkspace(channelID: ChannelID, messageID: MessageID) -> Message? {
        if channelID == selectedChannelID,
           let index = selectedMessageIndex(for: messageID),
           messages.indices.contains(index)
        {
            return messages[index]
        }
        if channelID == openThread?.id,
           let message = threadMessages.first(where: { $0.id == messageID })
        {
            return message
        }
        if let message = messageCache[channelID]?.first(where: { $0.id == messageID }) {
            return message
        }
        if let forumIndex = forumCatalogueIndexByID[channelID] {
            let post = forumCataloguePosts[forumIndex]
            if post.firstMessage?.id == messageID {
                return post.firstMessage
            }
            if post.mostRecentMessage?.id == messageID {
                return post.mostRecentMessage
            }
        }
        return nil
    }
}
