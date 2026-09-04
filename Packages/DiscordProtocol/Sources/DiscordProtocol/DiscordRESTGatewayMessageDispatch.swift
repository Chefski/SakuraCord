import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayMessageEvent(
        name: String,
        body: JSONValue,
        data: Data
    ) async -> Bool {
        switch name {
        case "MESSAGE_REACTION_REMOVE":
            await handleMessageReactionRemoveDispatch(name: name, body: body, data: data)
        case "MESSAGE_REACTION_REMOVE_ALL":
            await handleMessageReactionRemoveAllDispatch(name: name, body: body, data: data)
        case "MESSAGE_REACTION_REMOVE_EMOJI":
            await handleMessageReactionRemoveEmojiDispatch(name: name, body: body, data: data)
        case "MESSAGE_UPDATE":
            await handleMessageUpdateDispatch(name: name, body: body, data: data)
        case "MESSAGE_DELETE":
            await handleMessageDeleteDispatch(name: name, body: body, data: data)
        case "MESSAGE_DELETE_BULK":
            await handleMessageDeleteBulkDispatch(name: name, body: body, data: data)
        case "CHANNEL_PINS_UPDATE":
            await handleChannelPinsUpdateDispatch(name: name, body: body, data: data)
        case "GUILD_MEMBER_LIST_UPDATE":
            await handleGuildMemberListUpdateDispatch(name: name, body: body, data: data)
        case "GUILD_MEMBERS_CHUNK":
            await handleGuildMembersChunkDispatch(name: name, body: body, data: data)
        default:
            return false
        }
        return true
    }

    func handleMessageReactionRemoveDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let value = try? JSONDecoder().decode(
                GatewayMessageReactionUserDTO.self,
                from: data
            ),
            let update = value.domainUpdate(isAddition: false)
        else { return }
        applyGatewayReactionUpdate(update)
    }

    func handleMessageReactionRemoveAllDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let value = try? JSONDecoder().decode(
                GatewayMessageReactionRemoveAllDTO.self,
                from: data
            ),
            let update = value.domainUpdate
        else { return }
        applyGatewayReactionUpdate(update)
    }

    func handleMessageReactionRemoveEmojiDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let value = try? JSONDecoder().decode(
                GatewayMessageReactionRemoveEmojiDTO.self,
                from: data
            ),
            let update = value.domainUpdate
        else { return }
        applyGatewayReactionUpdate(update)
    }

    func handleMessageUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        if let update = try? JSONDecoder().decode(MessageUpdateDTO.self, from: data),
           let messageID = MessageID(update.id), ChannelID(update.channelID) != nil,
           var message = cachedMessages[messageID]
        {
            if let mentions = update.mentions?.elements {
                cacheMessageSearchUsers(mentions.map(\.searchIndexUser))
            }
            update.apply(to: &message)
            cachedMessages[messageID] = message
            continuation?.yield(.messageUpdated(message))
            updateForumPostForMessage(message)
        }
    }

    func handleMessageDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        if let value = try? JSONDecoder().decode(MessageDeleteDTO.self, from: data),
           let channelID = ChannelID(value.channelID), let messageID = MessageID(value.id)
        {
            cachedMessages[messageID] = nil
            continuation?.yield(.messageDeleted(channelID: channelID, messageID: messageID))
        }
    }

    func handleMessageDeleteBulkDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let deletion = try? JSONDecoder().decode(
                GatewayMessageDeleteBulkDTO.self, from: data
            ), let channelID = ChannelID(deletion.channelID)
        else { return }
        for messageID in deletion.ids.compactMap(MessageID.init) {
            cachedMessages[messageID] = nil
            continuation?.yield(
                .messageDeleted(channelID: channelID, messageID: messageID)
            )
        }
    }

    func handleChannelPinsUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayChannelPinsUpdateDTO.self, from: data
            ), let channelID = ChannelID(update.channelID)
        else { return }
        let timestamp = update.lastPinTimestamp.flatMap(DiscordDate.parse)
        if let guildID = update.guildID.flatMap(GuildID.init) {
            cachedGuildChannelDTOs[guildID]?[update.channelID]?.lastPinTimestamp =
                update.lastPinTimestamp
            publishGuildChannels(guildID)
        } else if var channels = cachedChannels[nil],
                  let index = channels.firstIndex(where: { $0.id == channelID })
        {
            channels[index].lastPinTimestamp = timestamp
            cachedChannels[nil] = channels
            continuation?.yield(.channelsChanged(guildID: nil, channels: channels))
        }
        continuation?.yield(.channelPinsInvalidated(channelID: channelID))
    }

    func handleGuildMemberListUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(GuildMemberListUpdateDTO.self, from: data),
              let guildID = GuildID(update.guildID)
        else {
            gatewayLogger.error("Member-list update could not be decoded; bytes=\(data.count)")
            return
        }
        let syncItemCount = update.ops.reduce(0) { $0 + ($1.items?.count ?? 0) }
        if syncItemCount > 0 {
            gatewayLogger.info("Member-list range synchronized; items=\(syncItemCount)")
        }
        // Discord's UserSearchManager deliberately does not subscribe to
        // GUILD_MEMBER_LIST_UPDATE. These members remain available to the
        // visible member list and nickname store, but must not leak into
        // the account-wide Forward user-search index.
        applyMemberListOperations(
            update.ops, guildID: guildID, memberListID: update.id
        )
        if let groups = update.groups {
            cachedMemberListGroups[guildID, default: [:]][update.id] = groups.map {
                GuildMemberListGroup(id: $0.id, count: $0.count)
            }
        }
        let changedUserIDs = Self.memberListChangedUserIDs(in: update.ops)
        let members = decodedMemberListMembers(
            guildID: guildID,
            memberListID: update.id,
            restrictingTo: changedUserIDs
        )
        cachedMembers[guildID] = DiscordMemberStoreOrdering.merging(
            existing: cachedMembers[guildID] ?? [], updates: members
        )
        publishUserSearchAliases()
        if guildID == pendingMemberGuildID,
           update.id == selectedMemberListID[guildID]
        {
            continuation?.yield(
                .membersChanged(
                    guildID: guildID,
                    members: orderedMemberListMembers(guildID: guildID) ?? members,
                    groups: cachedMemberListGroups[guildID]?[update.id] ?? []
                )
            )
        }
    }

    func handleGuildMembersChunkDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let chunk = try? JSONDecoder().decode(GatewayGuildMembersChunkDTO.self, from: data),
            let guildID = GuildID(chunk.guildID)
        else { return }
        let guildRoles = cachedGuildRoles[guildID] ?? []
        let guildRoleCatalog = GuildMemberRoleCatalog(guildRoles)
        let decodedMembers = chunk.members.compactMap {
            try? $0.domain(
                currentUserID: currentUser?.id,
                currentStatus: presenceStatus,
                guildRoles: guildRoles,
                guildRoleCatalog: guildRoleCatalog,
                guildID: guildID
            )
        }
        let responseUserIDs = Set(decodedMembers.map(\.id)).union(
            (chunk.notFound ?? []).compactMap(UserID.init)
        )
        let roleMemberRequestID = pendingRoleMemberRequestID(
            guildID: guildID,
            responseUserIDs: responseUserIDs
        )
        if roleMemberRequestID == nil {
            // Discord's SearchContextManager handles unsolicited and
            // search-driven GUILD_MEMBERS_CHUNK_BATCH users. SakuraCord
            // also issues private member-resolution requests solely to
            // hydrate timeline presentation; those extra requests must
            // not expand message-search UserStore beyond Discord's live
            // source set.
            cacheLiveSearchUsers(chunk.members.map(\.user))
        } else {
            for member in chunk.members {
                cacheGatewayUser(member.user, messageSearchEligible: false)
            }
        }
        let joinedUserIDs = Set<UserID>(chunk.members.compactMap { member -> UserID? in
            guard member.joinedAt != nil, member.pending != true else { return nil }
            return UserID(member.user.id)
        })
        mergeResolvedMembers(
            decodedMembers, guildID: guildID, joinedUserIDs: joinedUserIDs
        )
        // The first-party SearchContext worker records membership from
        // every GUILD_MEMBERS_CHUNK_BATCH result. Keep this index separate
        // from the bounded visible-member cache so @ searches can filter
        // a newly resolved user immediately within this live connection.
        quickSwitcherGuildMemberUserIDsByGuildID[guildID, default: []]
            .formUnion(decodedMembers.map(\.id))
        publishUserSearchAliases()
        if let requestID = roleMemberRequestID,
           var request = pendingRoleMemberRequests[requestID]
        {
            request.members.append(contentsOf: decodedMembers)
            request.receivedChunks.insert(chunk.chunkIndex)
            if request.receivedChunks.count >= max(1, chunk.chunkCount) {
                pendingRoleMemberRequests[requestID] = nil
                request.timeoutTask.cancel()
                request.continuation.resume(returning: request.members)
            } else {
                pendingRoleMemberRequests[requestID] = request
            }
            return
        }

        guard let requestID = pendingMemberSearchRequestByGuild[guildID],
              var search = pendingMemberSearchRequests[requestID]
        else {
            return
        }
        search.members.append(contentsOf: decodedMembers)
        search.receivedChunks.insert(chunk.chunkIndex)
        if search.receivedChunks.count >= max(1, chunk.chunkCount) {
            _ = removeMemberSearchRequest(requestID: requestID)
            search.timeoutTask.cancel()
            let responseMembers = Array(search.members.prefix(search.maximumResults))
            mergeResolvedMembers(responseMembers, guildID: guildID)
            let members = DiscordMemberStoreOrdering.searchResults(
                in: cachedMembers[guildID] ?? [],
                matching: responseMembers,
                limit: search.maximumResults
            )
            search.continuation.resume(returning: members)
        } else {
            pendingMemberSearchRequests[requestID] = search
        }
    }
}
