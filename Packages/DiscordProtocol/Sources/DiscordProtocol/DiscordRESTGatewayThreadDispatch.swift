import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayThreadEvent(
        name: String,
        body: JSONValue,
        data: Data
    ) async -> Bool {
        switch name {
        case "MESSAGE_CREATE":
            await handleMessageCreateDispatch(name: name, body: body, data: data)
        case "THREAD_CREATE":
            await handleThreadCreateDispatch(name: name, body: body, data: data)
        case "THREAD_UPDATE":
            await handleThreadUpdateDispatch(name: name, body: body, data: data)
        case "THREAD_DELETE":
            await handleThreadDeleteDispatch(name: name, body: body, data: data)
        case "THREAD_MEMBER_UPDATE":
            await handleThreadMemberUpdateDispatch(name: name, body: body, data: data)
        case "THREAD_MEMBERS_UPDATE":
            await handleThreadMembersUpdateDispatch(name: name, body: body, data: data)
        case "THREAD_LIST_SYNC":
            await handleThreadListSyncDispatch(name: name, body: body, data: data)
        case "MESSAGE_ACK":
            await handleMessageAckDispatch(name: name, body: body, data: data)
        default:
            return false
        }
        return true
    }

    func handleMessageCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        if let dto = try? JSONDecoder().decode(MessageDTO.self, from: data),
           let message = try? dto.domain()
        {
            cacheMessageSearchUsers(dto.searchIndexUsers)
            cacheForwardSearchMessageAliases([message])
            cachedMessages[message.id] = message
            continuation?.yield(.messageCreated(message))
            promotePrivateChannel(
                channelID: message.channelID,
                lastMessageID: message.id
            )
            updateForumPostForMessage(message, marksUnread: true)
        }
    }

    func handleThreadCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let dto = try? JSONDecoder().decode(ChannelDTO.self, from: data) else { return }
        ingestForumThreads(
            [dto],
            fallbackGuildID: dto.guildID.flatMap(GuildID.init),
            advancesParentLatestThreadID: true
        )
    }

    func handleThreadUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let dto = try? JSONDecoder().decode(ChannelDTO.self, from: data) else { return }
        ingestForumThreads([dto], fallbackGuildID: dto.guildID.flatMap(GuildID.init))
    }

    func handleThreadDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let deleted = try? JSONDecoder().decode(GatewayThreadDeleteDTO.self, from: data),
              let threadID = ChannelID(deleted.id),
              let parentID = deleted.parentID.flatMap(ChannelID.init)
        else { return }
        cachedForumPosts[parentID]?[threadID] = nil
        cachedForumThreadOrder.removeAll { $0 == threadID }
        cachedJoinedThreads[threadID] = nil
        cachedJoinedThreadOrder.removeAll { $0 == threadID }
        publishForumPosts(parentID: parentID)
        publishActiveJoinedThreads()
    }

    func handleThreadMemberUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let member = try? JSONDecoder().decode(ThreadMemberDTO.self, from: data),
            member.userID == nil || member.userID.flatMap(UserID.init) == currentUser?.id,
            let rawThreadID = member.id,
            let threadID = ChannelID(rawThreadID)
        else { return }
        for (parentID, posts) in cachedForumPosts where posts[threadID] != nil {
            cachedForumPosts[parentID]?[threadID]?.thread.notificationSettings =
                member.domain
            if let thread = cachedForumPosts[parentID]?[threadID]?.thread {
                reconcileJoinedThread(thread)
            }
            publishForumPosts(parentID: parentID)
            publishActiveJoinedThreads()
            break
        }
    }

    func handleThreadMembersUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayThreadMembersUpdateDTO.self, from: data
            ), let threadID = ChannelID(update.id)
        else { return }
        for parentID in cachedForumPosts.keys.sorted(by: {
            $0.rawValue < $1.rawValue
        }) where cachedForumPosts[parentID]?[threadID] != nil {
            cachedForumPosts[parentID]?[threadID]?.thread.memberCount =
                update.memberCount
            if let ownMember = update.addedMembers?.first(where: {
                $0.userID.flatMap(UserID.init) == currentUser?.id
            }) {
                cachedForumPosts[parentID]?[threadID]?.thread.notificationSettings =
                    ownMember.domain
                if let thread = cachedForumPosts[parentID]?[threadID]?.thread {
                    reconcileJoinedThread(thread)
                }
            } else if update.removedMemberIDs?.contains(
                currentUser?.id.description ?? ""
            ) == true {
                cachedForumPosts[parentID]?[threadID]?.thread.notificationSettings = nil
                cachedJoinedThreads[threadID] = nil
                cachedJoinedThreadOrder.removeAll { $0 == threadID }
            }
            publishForumPosts(parentID: parentID)
            publishActiveJoinedThreads()
            break
        }
    }

    func handleThreadListSyncDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let sync = try? JSONDecoder().decode(GatewayThreadListSyncDTO.self, from: data),
              let guildID = GuildID(sync.guildID)
        else { return }
        let parents = Set(sync.channelIDs.compactMap(ChannelID.init))
        let membersByThreadID = Dictionary(
            sync.members.compactMap { member in
                member.id.map { ($0, member) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let hydratedThreads = sync.threads.map { thread in
            var thread = thread
            if thread.member == nil {
                thread.member = membersByThreadID[thread.id]
            }
            return thread
        }
        ingestForumThreads(
            hydratedThreads, fallbackGuildID: guildID,
            replacingParents: parents.isEmpty ? nil : parents,
            advancesParentLatestThreadID: true
        )
    }

    func handleMessageAckDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let ack = try? JSONDecoder().decode(GatewayMessageAckDTO.self, from: data),
              let channelID = ChannelID(ack.channelID)
        else { return }
        forumReadStates[channelID] = ForumReadState(
            lastReadMessageID: ack.messageID.flatMap(MessageID.init),
            mentionCount: ack.mentionCount ?? 0
        )
        continuation?.yield(
            .readStateChanged(
                ChannelReadState(
                    channelID: channelID,
                    lastAcknowledgedMessageID: ack.messageID.flatMap(MessageID.init),
                    mentionCount: ack.mentionCount ?? 0,
                    isManual: ack.manual ?? false,
                    flags: ack.flags,
                    lastViewed: ack.lastViewed,
                    version: ack.version
                )
            )
        )
        for (parentID, posts) in cachedForumPosts where posts[channelID] != nil {
            if let lastMessageID = posts[channelID]?.thread.lastMessageID {
                cachedForumPosts[parentID]?[channelID]?.isUnread =
                    (ack.mentionCount ?? 0) > 0
                    || (ack.messageID.flatMap(MessageID.init).map {
                        lastMessageID > $0
                    } ?? true)
            } else {
                cachedForumPosts[parentID]?[channelID]?.isUnread =
                    (ack.mentionCount ?? 0) > 0
            }
            publishForumPosts(parentID: parentID)
            break
        }
    }
}
