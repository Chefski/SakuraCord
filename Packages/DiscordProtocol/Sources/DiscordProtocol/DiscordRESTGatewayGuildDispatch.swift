import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayGuildEvent(
        name: String,
        body: JSONValue,
        data: Data
    ) async -> Bool {
        switch name {
        case "GUILD_CREATE":
            await handleGuildCreateDispatch(name: name, body: body, data: data)
        case "GUILD_UPDATE":
            await handleGuildUpdateDispatch(name: name, body: body, data: data)
        case "GUILD_EMOJIS_UPDATE":
            await handleGuildEmojisUpdateDispatch(name: name, body: body, data: data)
        case "GUILD_ROLE_CREATE", "GUILD_ROLE_UPDATE":
            await handleGuildRoleCreateDispatch(name: name, body: body, data: data)
        case "GUILD_ROLE_DELETE":
            await handleGuildRoleDeleteDispatch(name: name, body: body, data: data)
        case "GUILD_MEMBER_ADD", "GUILD_MEMBER_UPDATE":
            await handleGuildMemberAddDispatch(name: name, body: body, data: data)
        case "GUILD_MEMBER_REMOVE":
            await handleGuildMemberRemoveDispatch(name: name, body: body, data: data)
        case "USER_UPDATE":
            await handleUserUpdateDispatch(name: name, body: body, data: data)
        default:
            return false
        }
        return true
    }

    func handleGuildCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        if let patch = try? JSONDecoder().decode(GatewayGuildPatchDTO.self, from: data),
           let guildID = GuildID(patch.id),
           var guild = patch.applying(
               to: cachedGuilds[guildID], currentUserID: currentUser?.id
           )
        {
            guild.isUnavailable = false
            cachedGuilds[guildID] = guild
            if !gatewayGuildIDs.contains(guildID) { gatewayGuildIDs.append(guildID) }
            insertGuildIntoRailIfNeeded(guildID)
            publishGuildLayout()
        }
        if let catalog = try? JSONDecoder().decode(GatewayGuildCatalogDTO.self, from: data),
           let guildID = GuildID(catalog.id)
        {
            if let channels = catalog.channels {
                appendQuickSwitcherChannelStoreOrder(
                    channels.compactMap { ChannelID($0.id) }
                )
                persistQuickSwitcherChannelStoreCache()
                cachedGuildChannelDTOs[guildID] = Dictionary(
                    channels.map { ($0.id, $0) },
                    uniquingKeysWith: { _, newer in newer }
                )
                publishGuildChannels(guildID)
            }
            if let roles = catalog.roles {
                cachedGuildRoles[guildID] = roles
                publishGuildRoles(guildID)
            }
            if let threads = catalog.threads, !threads.isEmpty {
                ingestForumThreads(
                    threads,
                    fallbackGuildID: guildID,
                    advancesParentLatestThreadID: true
                )
            }
            if let catalogMembers = catalog.members, !catalogMembers.isEmpty {
                quickSwitcherGuildMemberUserIDsByGuildID[guildID, default: []]
                    .formUnion(catalogMembers.compactMap { UserID($0.user.id) })
                cacheLiveSearchUsers(catalogMembers.map(\.user))
                let guildRoles = cachedGuildRoles[guildID] ?? []
                let guildRoleCatalog = GuildMemberRoleCatalog(guildRoles)
                let members = catalogMembers.compactMap {
                    try? $0.domain(
                        currentUserID: currentUser?.id,
                        currentStatus: presenceStatus,
                        guildRoles: guildRoles,
                        guildRoleCatalog: guildRoleCatalog,
                        guildID: guildID
                    )
                }
                cachedMembers[guildID] = DiscordMemberStoreOrdering.merging(
                    existing: cachedMembers[guildID] ?? [], updates: members
                )
                quickSwitcherJoinedMemberIDsByGuildID[guildID, default: []]
                    .formUnion(zip(catalogMembers, members).compactMap { dto, member in
                        dto.joinedAt != nil && dto.pending != true ? member.id : nil
                    })
                continuation?.yield(
                    .membersChanged(
                        guildID: guildID,
                        members: cachedMembers[guildID] ?? [],
                        groups: selectedMemberListGroups(guildID: guildID)
                    )
                )
                // Discord's UserSearchContextManager handles GUILD_CREATE
                // by indexing the accompanying members with their guild
                // nicknames. `cacheLiveSearchUsers` publishes newly
                // observed account records, but the nickname index is a
                // separate snapshot and must advance even when every user
                // was already known from READY.
                publishUserSearchAliases()
                scheduleForwardSearchPeopleCachePersistence()
                if let currentUserID = currentUser?.id,
                   let ownMember = members.first(where: { $0.id == currentUserID })
                {
                    continuation?.yield(
                        .currentUserRolesChanged(
                            guildID: guildID, roleIDs: ownMember.roleIDs
                        )
                    )
                }
            }
        }
        if let emojiSnapshot = try? JSONDecoder().decode(
            GatewayGuildEmojiSnapshotDTO.self,
            from: data
        ),
            let guildID = GuildID(emojiSnapshot.id),
            let emojis = emojiSnapshot.emojis
        {
            publishEmojiCollection(emojis, guildID: guildID)
        }
        if let snapshot = try? JSONDecoder().decode(
            GuildVoiceStateSnapshotDTO.self, from: data
        ) {
            let states = snapshot.domainVoiceStates
            gatewayLogger.info(
                "Initial voice-state snapshot received; guild=\(snapshot.id, privacy: .public), count=\(states.count)"
            )
            for state in states {
                continuation?.yield(.voiceStateChanged(state))
            }
        }
    }

    func handleGuildUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let patch = try? JSONDecoder().decode(GatewayGuildPatchDTO.self, from: data),
            let guildID = GuildID(patch.id),
            let guild = patch.applying(
                to: cachedGuilds[guildID], currentUserID: currentUser?.id
            )
        else { return }
        cachedGuilds[guildID] = guild
        continuation?.yield(.guildChanged(guild))
    }

    func handleGuildEmojisUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayGuildEmojiSnapshotDTO.self,
                from: data
            ),
            let guildID = GuildID(update.id),
            let emojis = update.emojis
        else { return }
        publishEmojiCollection(emojis, guildID: guildID)
    }

    func handleGuildRoleCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayGuildRoleEventDTO.self, from: data
            ), let guildID = GuildID(update.guildID)
        else { return }
        var roles = cachedGuildRoles[guildID] ?? []
        roles.removeAll { $0.id == update.role.id }
        roles.append(update.role)
        cachedGuildRoles[guildID] = roles
        clearCurrentUserPermissionSnapshot(guildID)
        publishGuildRoles(guildID)
    }

    func handleGuildRoleDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let deletion = try? JSONDecoder().decode(
                GatewayGuildRoleDeleteDTO.self, from: data
            ), let guildID = GuildID(deletion.guildID)
        else { return }
        cachedGuildRoles[guildID]?.removeAll { $0.id == deletion.roleID }
        if let roleID = RoleID(deletion.roleID),
           var members = cachedMembers[guildID]
        {
            for index in members.indices {
                members[index].roleIDs.removeAll { $0 == roleID }
            }
            cachedMembers[guildID] = members
        }
        clearCurrentUserPermissionSnapshot(guildID)
        publishGuildRoles(guildID)
    }

    func handleGuildMemberAddDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayGuildMemberEventDTO.self, from: data
            ), let guildID = GuildID(update.guildID),
            let member = try? update.member.domain(
                currentUserID: currentUser?.id,
                currentStatus: presenceStatus,
                guildRoles: cachedGuildRoles[guildID] ?? [],
                guildID: guildID
            )
        else { return }
        quickSwitcherGuildMemberUserIDsByGuildID[guildID, default: []].insert(member.id)
        if update.member.joinedAt != nil, member.isPending != true {
            quickSwitcherJoinedMemberIDsByGuildID[guildID, default: []]
                .insert(member.id)
        } else {
            quickSwitcherJoinedMemberIDsByGuildID[guildID]?.remove(member.id)
        }
        cacheLiveSearchUsers([update.member.user])
        publishMemberChange(member, guildID: guildID)
        publishUserSearchAliases()
        scheduleForwardSearchPeopleCachePersistence()
    }

    func handleGuildMemberRemoveDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let deletion = try? JSONDecoder().decode(
                GatewayGuildMemberRemoveDTO.self, from: data
            ), let guildID = GuildID(deletion.guildID),
            let userID = UserID(deletion.user.id)
        else { return }
        quickSwitcherGuildMemberUserIDsByGuildID[guildID]?.remove(userID)
        quickSwitcherJoinedMemberIDsByGuildID[guildID]?.remove(userID)
        removeMember(userID: userID, guildID: guildID)
        publishUserSearchAliases()
        scheduleForwardSearchPeopleCachePersistence()
    }

    func handleUserUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let dto = try? JSONDecoder().decode(UserDTO.self, from: data),
              let user = try? dto.domain()
        else { return }
        applyUserUpdate(dto: dto, user: user)
    }
}
