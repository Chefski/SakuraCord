import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayThreadEvent(
        name: String,
        body: JSONValue
    ) async -> Bool {
        switch name {
        case "THREAD_CREATE":
            await handleThreadCreateDispatch(name: name, body: body)
        case "THREAD_UPDATE":
            await handleThreadUpdateDispatch(name: name, body: body)
        case "THREAD_DELETE":
            await handleThreadDeleteDispatch(name: name, body: body)
        case "THREAD_MEMBER_UPDATE":
            await handleThreadMemberUpdateDispatch(name: name, body: body)
        case "THREAD_MEMBERS_UPDATE":
            await handleThreadMembersUpdateDispatch(name: name, body: body)
        case "THREAD_LIST_SYNC":
            await handleThreadListSyncDispatch(name: name, body: body)
        default:
            return false
        }
        return true
    }

    func handleThreadCreateDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard let dto = try? JSONValueDecoder().decode(ChannelDTO.self, from: body) else { return }
        ingestForumThreads(
            [dto],
            fallbackGuildID: dto.guildID.flatMap(GuildID.init),
            advancesParentLatestThreadID: true
        )
    }

    func handleThreadUpdateDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard let dto = try? JSONValueDecoder().decode(ChannelDTO.self, from: body) else { return }
        ingestForumThreads([dto], fallbackGuildID: dto.guildID.flatMap(GuildID.init))
    }

    func handleThreadDeleteDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard let deleted = try? JSONValueDecoder().decode(GatewayThreadDeleteDTO.self, from: body),
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
        body: JSONValue
    ) async {
        guard
            let member = try? JSONValueDecoder().decode(ThreadMemberDTO.self, from: body),
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
        body: JSONValue
    ) async {
        guard
            let update = try? JSONValueDecoder().decode(
                GatewayThreadMembersUpdateDTO.self, from: body
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
        body: JSONValue
    ) async {
        guard let sync = try? JSONValueDecoder().decode(GatewayThreadListSyncDTO.self, from: body),
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
}
