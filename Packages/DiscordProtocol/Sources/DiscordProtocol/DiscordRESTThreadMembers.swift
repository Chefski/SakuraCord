import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    /// The desktop client uses a bounded thread-member subscription, not the
    /// parent channel's lazy member ranges or a message-author approximation.
    public func threadMembers(in thread: MessageThreadSummary) async throws -> [Member]? {
        guard let guildID = thread.guildID,
              let parent = cachedChannels[guildID]?.first(where: { $0.id == thread.parentID }) else { return [] }
        guard !thread.isArchived, parent.kind != .announcement else { return [] }
        var ids = threadMemberSubscriptions[guildID] ?? []
        let alreadySubscribed = ids.contains(thread.id)
        ids.removeAll { $0 == thread.id }
        ids.append(thread.id)
        let evicted = ids.prefix(max(0, ids.count - 3))
        for id in evicted {
            cachedThreadMemberIDs[id] = nil
            continuation?.yield(.threadMembersChanged(guildID: guildID, threadID: id, members: nil))
        }
        threadMemberSubscriptions[guildID] = Array(ids.suffix(3))
        if !alreadySubscribed, gatewayReady {
            do {
                try await sendThreadMemberSubscription(guildID: guildID)
            } catch {
                threadMemberSubscriptions[guildID]?.removeAll { $0 == thread.id }
                throw error
            }
        }
        return resolvedThreadMembers(threadID: thread.id, guildID: guildID)
    }

    func sendThreadMemberSubscription(guildID: GuildID) async throws {
        // Subscription updates are partial. Do not replace channel ranges while
        // adding a thread to the same guild subscription.
        try await sendGateway(DiscordGatewayPayloadFactory.threadMemberSubscriptions(
            guildID: guildID, threadIDs: threadMemberSubscriptions[guildID] ?? []
        ))
        gatewayLogger.info("Thread member subscription sent; retained=\(self.threadMemberSubscriptions[guildID]?.count ?? 0)")
    }

    func removeThreadMemberSubscription(_ threadID: ChannelID) async {
        cachedThreadMemberIDs[threadID] = nil
        for (guildID, ids) in threadMemberSubscriptions where ids.contains(threadID) {
            threadMemberSubscriptions[guildID]?.removeAll { $0 == threadID }
            continuation?.yield(.threadMembersChanged(guildID: guildID, threadID: threadID, members: nil))
            guard gatewayReady else { continue }
            do { try await sendThreadMemberSubscription(guildID: guildID) } catch { gatewayLogger.error("Thread member unsubscribe failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func handleThreadMemberListUpdate(body: JSONValue) {
        guard let update = try? JSONValueDecoder().decode(ThreadMemberListDTO.self, from: body),
              let guildID = GuildID(update.guildID), let threadID = ChannelID(update.threadID),
              threadMemberSubscriptions[guildID]?.contains(threadID) == true else { return }
        gatewayLogger.info("Thread member snapshot received; members=\(update.members.count)")
        ingestThreadMembers(update.members, guildID: guildID)
        cachedThreadMemberIDs[threadID] = update.members.compactMap { $0.userID.flatMap(UserID.init) }
        publishThreadMembers(guildID: guildID)
    }

    func ingestThreadMembers(_ entries: [ThreadMemberDTO], guildID: GuildID) {
        let roles = cachedGuildRoles[guildID] ?? []
        let catalog = GuildMemberRoleCatalog(roles)
        let members = entries.compactMap { entry -> Member? in
            guard let member = entry.member else { return nil }
            cacheGatewayUser(member.user, messageSearchEligible: false)
            return try? member.domain(
                currentUserID: currentUser?.id, currentStatus: presenceStatus,
                presence: entry.presence, guildRoles: roles,
                guildRoleCatalog: catalog, guildID: guildID
            )
        }
        cachedMembers[guildID] = DiscordMemberStoreOrdering.merging(
            existing: cachedMembers[guildID] ?? [], updates: members
        )
    }

    func resolvedThreadMembers(threadID: ChannelID, guildID: GuildID) -> [Member]? {
        guard let ids = cachedThreadMemberIDs[threadID] else { return nil }
        let byID = Dictionary((cachedMembers[guildID] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return membersWithCurrentStatus(ids.compactMap { byID[$0] }).map { member in
            var member = member
            member.memberListIndex = nil
            return member
        }
    }

    func publishThreadMembers(guildID: GuildID) {
        for threadID in threadMemberSubscriptions[guildID] ?? [] {
            guard let members = resolvedThreadMembers(threadID: threadID, guildID: guildID) else { continue }
            continuation?.yield(.threadMembersChanged(guildID: guildID, threadID: threadID, members: members))
        }
    }
}

private struct ThreadMemberListDTO: Decodable {
    var guildID: String
    var threadID: String
    var members: [ThreadMemberDTO]

    enum CodingKeys: String, CodingKey {
        case guildID = "guild_id"
        case threadID = "thread_id"
        case members
    }
}
