import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func currentUserSearchAliasesByUserID() -> [UserID: [String]] {
        var result: [UserID: [String]] = [:]
        var seenGuildIDs = Set<GuildID>()
        // CONNECTION_OPEN establishes GuildMemberStore's key insertion order.
        // Cached aliases only fill gaps after that live authoritative order;
        // putting the disk cache first changed equal-score nickname ties.
        let orderedGuildIDs = gatewayGuildIDs.filter {
            seenGuildIDs.insert($0).inserted
        } + loadedForwardSearchAliasGuildOrder.filter { seenGuildIDs.insert($0).inserted }
            + cachedMembers.keys.sorted().filter { seenGuildIDs.insert($0).inserted }
            + cachedForwardSearchAliasGuildOrder.filter { seenGuildIDs.insert($0).inserted }
        for guildID in orderedGuildIDs {
            var aliases = cachedForwardSearchAliasesByGuildID[guildID] ?? [:]
            for member in cachedMembers[guildID] ?? [] {
                aliases[member.id] = forwardSearchNickname(from: member)
            }
            for userID in aliases.keys.sorted() {
                guard let alias = aliases[userID],
                      result[userID, default: []].contains(where: {
                          $0.localizedCaseInsensitiveCompare(alias) == .orderedSame
                      }) == false
                else { continue }
                result[userID, default: []].append(alias)
            }
        }
        return result
    }

    func currentQuickSwitcherGuildMemberUserIDs() -> [GuildID: [UserID]] {
        var guildIDs = Set(gatewayGuildIDs)
        guildIDs.formUnion(quickSwitcherGuildMemberUserIDsByGuildID.keys)
        guildIDs.formUnion(cachedMembers.keys)
        let result = Dictionary(uniqueKeysWithValues: guildIDs.map { guildID in
            var remaining = quickSwitcherGuildMemberUserIDsByGuildID[guildID] ?? []
            remaining.formUnion((cachedMembers[guildID] ?? []).map(\.id))
            var ordered: [UserID] = []
            for member in cachedMembers[guildID] ?? [] where remaining.remove(member.id) != nil {
                ordered.append(member.id)
            }
            ordered.append(contentsOf: remaining.sorted())
            return (guildID, ordered)
        })
        return result
    }

    func currentQuickSwitcherGuildMemberAliases() -> [GuildID: [UserID: String]] {
        var guildIDs = Set(gatewayGuildIDs)
        guildIDs.formUnion(cachedMembers.keys)
        return Dictionary(uniqueKeysWithValues: guildIDs.map { guildID in
            var aliases: [UserID: String] = [:]
            for member in cachedMembers[guildID] ?? [] {
                aliases[member.id] = forwardSearchNickname(from: member)
            }
            return (guildID, aliases.filter { !$0.value.isEmpty })
        })
    }

    func currentQuickSwitcherJoinedGuildMemberUserIDs() -> [GuildID: [UserID]] {
        Dictionary(uniqueKeysWithValues: quickSwitcherJoinedMemberIDsByGuildID.map { entry in
            (entry.key, entry.value.sorted())
        })
    }

    func publishUserSearchAliases() {
        continuation?.yield(.userSearchAliasesChanged(currentUserSearchAliasesByUserID()))
        continuation?.yield(.quickSwitcherGuildMemberUserIDsChanged(
            currentQuickSwitcherGuildMemberUserIDs()
        ))
        continuation?.yield(.quickSwitcherJoinedMemberIDsChanged(
            currentQuickSwitcherJoinedGuildMemberUserIDs()
        ))
        continuation?.yield(.quickSwitcherGuildMemberAliasesChanged(
            currentQuickSwitcherGuildMemberAliases()
        ))
    }

    func currentKnownUsers() -> [User] {
        cachedGatewayUserOrder.compactMap { rawUserID -> User? in
            let userID = UserID(rawUserID)
            guard let user = cachedGatewayUsersByID[rawUserID]
                .flatMap({ try? $0.domain() }) ?? userID.flatMap({
                    cachedForwardSearchUsersByID[$0]
                }),
                  !cachedBlockedOrIgnoredUserIDs.contains(user.id)
            else { return nil }
            return user
        }
    }

    func currentQuickSwitcherUsers() -> [User] {
        var seen = Set<UserID>()
        let orderedUserIDs = forwardSearchEligibleUserOrder.filter {
            seen.insert($0).inserted
        }
        // Discord's quick-switcher worker mirrors the live UserStore. It does
        // not index every user record carried by READY_SUPPLEMENTAL, nor does
        // it restore message authors from an app-specific disk cache. READY
        // users and members hydrated into UserStore are marked eligible at
        // their ingestion sites and retain the same insertion order here.
        // UserStore retains blocked/ignored relationships as searchable
        // identities; forwarding continues to exclude them separately.
        // Keeping this distinct from currentKnownUsers() prevents a relaunch
        // with ForwardSearchPeople data from changing quick-switcher results.
        return orderedUserIDs.compactMap { userID in
            cachedGatewayUsersByID[userID.description]
                .flatMap { try? $0.domain() } ?? cachedForwardSearchUsersByID[userID]
        }
    }

    func currentMessageSearchUsers() -> [User] {
        messageSearchUserOrder.compactMap { userID in
            cachedGatewayUsersByID[userID.description].flatMap { try? $0.domain() }
        }
    }

    @discardableResult
    func cacheGatewayUser(
        _ user: UserDTO,
        forwardSearchEligible: Bool = true,
        includeInKnownUserStore: Bool = true,
        messageSearchEligible: Bool? = nil
    ) -> Bool {
        let userID = UserID(user.id)
        let previous = cachedGatewayUsersByID[user.id].flatMap { try? $0.domain() }
            ?? userID.flatMap { cachedForwardSearchUsersByID[$0] }
        let insertedIntoKnownUserStore = includeInKnownUserStore
            && cachedGatewayUserIDs.insert(user.id).inserted
        if insertedIntoKnownUserStore {
            cachedGatewayUserOrder.append(user.id)
        }
        cachedGatewayUsersByID[user.id] = user
        let becameForwardSearchEligible = userID.map {
            forwardSearchEligible && forwardSearchEligibleUserIDs.insert($0).inserted
        } ?? false
        if let userID, becameForwardSearchEligible {
            forwardSearchEligibleUserOrder.append(userID)
        }
        let admitsToMessageSearch = messageSearchEligible ?? includeInKnownUserStore
        let becameMessageSearchEligible = userID.map {
            admitsToMessageSearch && messageSearchUserIDs.insert($0).inserted
        } ?? false
        if let userID, becameMessageSearchEligible {
            messageSearchUserOrder.append(userID)
        }
        return becameMessageSearchEligible || becameForwardSearchEligible || insertedIntoKnownUserStore
            || previous != (try? user.domain())
    }

    @discardableResult
    func includeCachedGatewayUserInKnownUserStore(_ rawUserID: String) -> Bool {
        guard cachedGatewayUsersByID[rawUserID] != nil,
              let userID = UserID(rawUserID)
        else { return false }
        let insertedIntoKnownUserStore = cachedGatewayUserIDs.insert(rawUserID).inserted
        if insertedIntoKnownUserStore {
            cachedGatewayUserOrder.append(rawUserID)
        }
        let insertedIntoMessageSearch = messageSearchUserIDs.insert(userID).inserted
        if insertedIntoMessageSearch {
            messageSearchUserOrder.append(userID)
        }
        return insertedIntoKnownUserStore || insertedIntoMessageSearch
    }

    func cacheLiveSearchUsers(_ users: [UserDTO]) {
        cacheSearchUsers(users, persistToMessageCache: false)
    }

    func cacheMessageSearchUsers(_ users: [UserDTO]) {
        cacheSearchUsers(users, persistToMessageCache: true)
    }

    private func cacheSearchUsers(
        _ users: [UserDTO],
        persistToMessageCache: Bool
    ) {
        var changed = false
        for user in users {
            changed = cacheGatewayUser(user) || changed
        }
        let persistentChanged = persistToMessageCache
            ? cacheForwardSearchMessageUsers(users) : false
        if persistentChanged {
            scheduleForwardSearchPeopleCachePersistence()
        }
        if changed || persistentChanged {
            continuation?.yield(.knownUsersChanged(currentKnownUsers()))
            continuation?.yield(
                .quickSwitcherUserIDsChanged(currentQuickSwitcherUsers().map(\.id))
            )
            continuation?.yield(.messageSearchUsersChanged(currentMessageSearchUsers()))
        }
    }

    func currentActiveJoinedThreads() -> [MessageThreadSummary] {
        var seen = Set<ChannelID>()
        return cachedJoinedThreadOrder.compactMap { threadID in
            guard seen.insert(threadID).inserted,
                  let thread = cachedJoinedThreads[threadID], !thread.isArchived
            else { return nil }
            return thread
        } + cachedJoinedThreads.values
            .filter { !seen.contains($0.id) && !$0.isArchived }
            .sorted { $0.id < $1.id }
    }

    func waitForInitialGatewaySnapshot() async throws -> InitialGatewaySnapshot {
        if let initialGatewaySnapshotResult {
            return try initialGatewaySnapshotResult.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            initialGatewaySnapshotContinuation = continuation
        }
    }

    func finishInitialGatewaySnapshot(_ snapshot: InitialGatewaySnapshot) {
        guard initialGatewaySnapshotResult == nil else { return }
        // GatewaySession emits READY dispatch before its `.ready` state event.
        // Bootstrap resumes here, so immediate channel loads must already be
        // allowed to resolve missing message authors through the Gateway.
        gatewayReady = true
        initialGatewaySnapshotResult = .success(snapshot)
        initialGatewaySnapshotContinuation?.resume(returning: snapshot)
        initialGatewaySnapshotContinuation = nil
    }

    func failInitialGatewaySnapshot(_ error: any Error) {
        guard initialGatewaySnapshotResult == nil else { return }
        initialGatewaySnapshotResult = .failure(error)
        initialGatewaySnapshotContinuation?.resume(throwing: error)
        initialGatewaySnapshotContinuation = nil
    }

    func failInitialGatewaySnapshotOnTerminalDisconnect(_ state: ConnectionState) {
        guard state == .disconnected else { return }
        failInitialGatewaySnapshot(
            ChatProviderError.invalidRequest(
                "Discord's Gateway disconnected before initial state was ready."
            )
        )
    }

    static func applyingGuildLayout(
        _ layout: DiscordGuildLayout,
        to guilds: [Guild]
    ) -> (guilds: [Guild], railItems: [GuildRailItem]) {
        let byID = Dictionary(uniqueKeysWithValues: guilds.map { ($0.id, $0) })
        let folderGuildIDs = layout.folders.flatMap(\.guildIDs)
        let orderedIDs = folderGuildIDs.isEmpty ? layout.guildPositions : folderGuildIDs
        guard !orderedIDs.isEmpty else {
            return (guilds, guilds.map { .guild($0.id) })
        }

        let referenced = Set(orderedIDs)
        let omitted =
            guilds
                .filter { !referenced.contains($0.id) }
                .sorted { $0.id.rawValue > $1.id.rawValue }
        var railItems = omitted.map { GuildRailItem.guild($0.id) }
        var emittedGuildIDs = Set(omitted.map(\.id))
        var emittedFolderIDs: Set<Int64> = []

        if layout.folders.isEmpty {
            for id in layout.guildPositions
                where byID[id] != nil && emittedGuildIDs.insert(id).inserted {
                railItems.append(.guild(id))
            }
        } else {
            for decodedFolder in layout.folders {
                let validIDs = decodedFolder.guildIDs.filter {
                    byID[$0] != nil && !emittedGuildIDs.contains($0)
                }
                emittedGuildIDs.formUnion(validIDs)
                guard !validIDs.isEmpty else { continue }
                if let id = decodedFolder.id, emittedFolderIDs.insert(id).inserted {
                    railItems.append(
                        .folder(
                            GuildFolder(
                                id: id,
                                name: decodedFolder.name,
                                colorHex: decodedFolder.colorHex,
                                guildIDs: validIDs
                            )))
                } else {
                    railItems.append(contentsOf: validIDs.map(GuildRailItem.guild))
                }
            }
        }

        let flattenedIDs = railItems.flatMap { item -> [GuildID] in
            switch item {
            case .guild(let id): [id]
            case .folder(let folder): folder.guildIDs
            }
        }
        let orderedGuilds = flattenedIDs.compactMap { byID[$0] }
        gatewayLogger.info(
            "Applied guild folder settings; folders=\(emittedFolderIDs.count), guilds=\(orderedGuilds.count), omitted=\(omitted.count)"
        )
        return (orderedGuilds, railItems)
    }

    static func applyingGuildOrder(_ orderedIDs: [GuildID], to guilds: [Guild]) -> [Guild] {
        let byID = Dictionary(uniqueKeysWithValues: guilds.map { ($0.id, $0) })
        let ordered = orderedIDs.compactMap { byID[$0] }
        let orderedSet = Set(orderedIDs)
        let omitted =
            guilds
                .filter { !orderedSet.contains($0.id) }
                .sorted { $0.id.rawValue > $1.id.rawValue }
        gatewayLogger.info(
            "Applied guild settings order; ordered=\(ordered.count), omitted=\(omitted.count)"
        )
        // Match Discord/Paicord's unlisted-guild fallback: guilds absent from the
        // folder payload appear first, newest joined/created first. Guild IDs are
        // time-sortable snowflakes and are the bootstrap-safe proxy for join date.
        return omitted + ordered
    }

    public func channels(in guildID: GuildID?) async throws -> [Channel] {
        if let cached = cachedChannels[guildID] {
            return cached
        }
        guard let guildID else { return cachedChannels[nil] ?? [] }
        if let task = guildChannelTasks[guildID] {
            return try await task.value
        }
        let task = Task { [self] in
            let values: [ChannelDTO] = try await request("/guilds/\(guildID)/channels")
            cachedGuildChannelDTOs[guildID] = Dictionary(
                values.map { ($0.id, $0) },
                uniquingKeysWith: { _, newer in newer }
            )
            return try Self.domainChannels(values, guildID: guildID)
        }
        guildChannelTasks[guildID] = task
        do {
            let channels = try await task.value
            guildChannelTasks[guildID] = nil
            cachedChannels[guildID] = channels
            return channels
        } catch {
            guildChannelTasks[guildID] = nil
            throw error
        }
    }

    func privateChannel(id: ChannelID) -> Channel? {
        cachedChannels[nil]?.first { $0.id == id }
    }

    func upsertPrivateChannel(_ channel: Channel) {
        var channels = cachedChannels[nil] ?? []
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            var channel = channel
            // `cachedChannels[nil]` is reordered by last activity for the DM
            // sidebar. Preserve the independent READY/store insertion rank used
            // by Discord's equal-score forwarding search.
            channel.position = channels[index].position
            channels[index] = channel
        } else {
            var channel = channel
            channel.position = (channels.lazy.map(\.position).max() ?? -1) + 1
            channels.append(channel)
        }
        cachedChannels[nil] = channels
        continuation?.yield(.channelsChanged(guildID: nil, channels: channels))
        continuation?.yield(.privateMembersChanged(privateMembersInChannelOrder()))
    }

    func cachePrivateRecipientReferences(_ values: [ChannelDTO]) {
        for value in values {
            guard let channelID = ChannelID(value.id), value.type == 1 || value.type == 3,
                  let recipientIDs = value.recipientIDs ?? value.recipients?.map(\.id)
            else { continue }
            cachedPrivateRecipientIDsByChannelID[channelID] =
                DiscordPrivateRecipientOrdering.sortedIDs(
                    recipientIDs,
                    channelID: value.id,
                    channelType: value.type
                )
        }
    }

    func admitCachedPrivateRecipientUsersToMessageSearch() {
        for channel in cachedChannels[nil] ?? [] {
            for recipientID in cachedPrivateRecipientIDsByChannelID[channel.id] ?? [] {
                includeCachedGatewayUserInKnownUserStore(recipientID)
            }
        }
    }

    /// READY_SUPPLEMENTAL may carry a broad user hydration table, but Discord's
    /// UserStore only admits the raw recipients referenced by lazy private
    /// channels. Preserve their payload order independently of the deterministic
    /// recipient ordering used to render a group DM.
    func cacheLazyPrivateRecipientUsers(_ values: [ChannelDTO]) {
        for value in values where value.type == 1 || value.type == 3 {
            if let recipients = value.recipients {
                for recipient in recipients {
                    cacheGatewayUser(recipient)
                }
            } else {
                for recipientID in value.recipientIDs ?? [] {
                    includeCachedGatewayUserInKnownUserStore(recipientID)
                }
            }
        }
    }

    /// READY can describe private channels with only `recipient_ids`, while
    /// the corresponding UserStore records arrive in READY_SUPPLEMENTAL. The
    /// official client retains those references and resolves the recipients
    /// once its UserStore advances; do the same without issuing a REST read.
    func rehydratePrivateChannelRecipients() {
        guard var channels = cachedChannels[nil] else { return }
        var changed = false
        for index in channels.indices {
            let channel = channels[index]
            guard let recipientIDs = cachedPrivateRecipientIDsByChannelID[channel.id]
            else { continue }
            let recipients = recipientIDs.compactMap {
                cachedGatewayUsersByID[$0].flatMap { try? $0.domain() }
            }
            guard recipients != channel.recipients else { continue }
            channels[index].recipients = recipients
            if !channel.hasExplicitName {
                let recipientName = recipients.map(\.displayName).joined(separator: ", ")
                if !recipientName.isEmpty {
                    channels[index].name = recipientName
                } else if channel.kind == .groupDirectMessage,
                          let ownerID = channel.ownerID,
                          let owner = cachedGatewayUsersByID[ownerID.description]
                            .flatMap({ try? $0.domain() })
                {
                    channels[index].name = "\(owner.displayName)'s Group"
                } else {
                    channels[index].name = channel.kind == .groupDirectMessage
                        ? "Group Direct Message" : "Direct Message"
                }
            }
            changed = true
        }
        guard changed else { return }
        cachedChannels[nil] = channels
        continuation?.yield(.channelsChanged(guildID: nil, channels: channels))
        continuation?.yield(.privateMembersChanged(privateMembersInChannelOrder()))
    }

    func promotePrivateChannel(
        channelID: ChannelID,
        lastMessageID: MessageID
    ) {
        var channels = cachedChannels[nil] ?? []
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }
        var channel = channels.remove(at: index)
        channel.lastMessageID = lastMessageID
        channels.insert(channel, at: 0)
        cachedChannels[nil] = channels
        continuation?.yield(.channelsChanged(guildID: nil, channels: channels))
    }

    func privateMembersInChannelOrder() -> [Member] {
        var seen: Set<UserID> = []
        return (cachedChannels[nil] ?? []).flatMap(\.recipients).compactMap { user in
            guard seen.insert(user.id).inserted else { return nil }
            if var member = cachedPrivateMembersByID[user.id] {
                // READY presence records only contain a partial user. Keep DM
                // identity sourced from the hydrated private-channel recipient.
                member.user = user
                return member
            }
            return Member(user: user, roleName: "Direct Message", status: .offline)
        }
    }

    func cachePrivatePresence(_ update: PresenceUpdateDTO) {
        guard update.guildID == nil,
              let userID = UserID(update.user.id),
              let status = PresenceStatus(rawValue: update.status)
        else { return }
        let user =
            cachedChannels[nil]?.lazy.flatMap(\.recipients)
                .first(where: { $0.id == userID })
                ?? cachedGatewayUsersByID[update.user.id].flatMap { try? $0.domain() }
        guard let user else { return }
        var member =
            cachedPrivateMembersByID[userID]
                ?? Member(user: user, roleName: "Direct Message", status: status)
        member.user = user
        member.status = status
        if let activities = update.activities {
            member.customStatus = activities.first(where: { $0.type == 4 })?.displayText
            member.activityText =
                activities.first(where: { $0.type != 4 })?.displayText
                    ?? member.customStatus
        }
        cachedPrivateMembersByID[userID] = member
    }

    static func orderedPrivateChannels(_ channels: [Channel]) -> [Channel] {
        channels.sorted { lhs, rhs in
            let lhsActivity = lhs.lastMessageID?.rawValue ?? lhs.id.rawValue
            let rhsActivity = rhs.lastMessageID?.rawValue ?? rhs.id.rawValue
            return lhsActivity > rhsActivity
        }
    }

    static func domainChannels(_ values: [ChannelDTO], guildID: GuildID) throws -> [Channel] {
        let categories = Dictionary(
            uniqueKeysWithValues: values.filter { $0.type == 4 }.map { ($0.id, $0) }
        )
        return try values.filter { $0.type != 4 && !$0.isThread }.map { dto in
            let category = dto.parentID.flatMap { categories[$0] }
            return try dto.domain(
                guildID: guildID,
                categoryName: category?.name,
                categoryPosition: category?.position ?? -1
            )
        }.sorted { lhs, rhs in
            if lhs.categoryPosition != rhs.categoryPosition {
                return lhs.categoryPosition < rhs.categoryPosition
            }
            return lhs.position < rhs.position
        }
    }

    public func members(in guildID: GuildID?) async throws -> [Member] {
        guard let guildID else {
            return privateMembersInChannelOrder()
        }
        if cachedGuildRoles[guildID] == nil {
            do {
                _ = try await guildRoleDTOs(in: guildID)
            } catch {
                gatewayLogger.warning(
                    "Guild roles unavailable; member categories will use the default group: \(error.localizedDescription, privacy: .public)"
                )
                cachedGuildRoles[guildID] = []
            }
        }
        pendingMemberGuildID = guildID
        gatewayLogger.info("Member list requested; gatewayReady=\(self.gatewayReady)")
        if gatewayReady {
            await attemptMemberSubscription(guildID: guildID)
        }
        return orderedMemberListMembers(guildID: guildID) ?? cachedMembers[guildID] ?? []
    }

    public func roles(in guildID: GuildID) async throws -> [GuildRole] {
        try await guildRoleDTOs(in: guildID)
            .compactMap(\.domain)
            .sorted { $0.position > $1.position }
    }

    func guildRoleDTOs(in guildID: GuildID) async throws -> [GuildRoleDTO] {
        if let cached = cachedGuildRoles[guildID] {
            return cached
        }
        if let task = guildRoleTasks[guildID] {
            return try await task.value
        }
        let task = Task { [self] in
            let roles: [GuildRoleDTO] = try await request("/guilds/\(guildID)/roles")
            return roles
        }
        guildRoleTasks[guildID] = task
        do {
            let roles = try await task.value
            guildRoleTasks[guildID] = nil
            cachedGuildRoles[guildID] = roles
            return roles
        } catch {
            guildRoleTasks[guildID] = nil
            throw error
        }
    }

    public func searchMembers(
        in guildID: GuildID, query: String, limit: Int
    ) async throws -> [Member] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        _ = try await roles(in: guildID)
        guard gatewayReady else {
            throw ChatProviderError.invalidRequest(
                "Discord Gateway is not ready to search guild members.")
        }
        let requestID = UUID().uuidString
        let maximumResults = min(max(1, limit), 100)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Member], any Error>) in
                if let supersededRequestID = pendingMemberSearchRequestByGuild[guildID] {
                    failMemberSearchRequest(
                        requestID: supersededRequestID,
                        error: CancellationError()
                    )
                }
                let timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    await self?.timeoutMemberSearchRequest(requestID: requestID)
                }
                pendingMemberSearchRequests[requestID] = PendingMemberSearchRequest(
                    guildID: guildID,
                    maximumResults: maximumResults,
                    members: [],
                    receivedChunks: [],
                    continuation: continuation,
                    timeoutTask: timeout
                )
                pendingMemberSearchRequestByGuild[guildID] = requestID
                Task { [weak self] in
                    do {
                        try await self?.sendGateway(
                            DiscordGatewayPayloadFactory.searchMembers(
                                guildIDs: [guildID],
                                query: normalized,
                                limit: maximumResults
                            )
                        )
                        gatewayLogger.info(
                            "Sent member autocomplete Gateway request; limit=\(maximumResults)"
                        )
                    } catch {
                        await self?.failMemberSearchRequest(requestID: requestID, error: error)
                    }
                }
            }
        } onCancel: {
            Task {
                await self.failMemberSearchRequest(
                    requestID: requestID,
                    error: CancellationError()
                )
            }
        }
    }

    public func requestQuickSwitcherMembers(
        in guildID: GuildID, query: String, limit: Int
    ) async throws {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard gatewayReady else {
            throw ChatProviderError.invalidRequest(
                "Discord Gateway is not ready to search guild members.")
        }
        let maximumResults = min(max(1, limit), 100)
        try await sendGateway(
            DiscordGatewayPayloadFactory.searchMembers(
                guildIDs: [guildID],
                query: normalized.lowercased(),
                limit: maximumResults
            )
        )
        gatewayLogger.info(
            "Sent quick-switcher member Gateway request; limit=\(maximumResults)"
        )
    }

    public func members(withRole roleID: RoleID, in guildID: GuildID) async throws
        -> RoleMemberResult
    {
        let ids: [String] = try await request("/guilds/\(guildID)/roles/\(roleID)/member-ids")
        let validIDs = ids.compactMap(UserID.init)
        let maximumDisplayedMembers = 1_000
        let requestedIDs = Array(validIDs.prefix(maximumDisplayedMembers))
        let cachedByID = Dictionary(
            uniqueKeysWithValues: (cachedMembers[guildID] ?? []).map { ($0.id, $0) })
        let missing = requestedIDs.filter { cachedByID[$0] == nil }
        if !missing.isEmpty {
            try await requestMembersByID(missing, guildID: guildID)
        }
        let resolvedByID = Dictionary(
            uniqueKeysWithValues: (cachedMembers[guildID] ?? []).map { ($0.id, $0) })
        return RoleMemberResult(
            members: requestedIDs.compactMap { resolvedByID[$0] },
            totalCount: validIDs.count,
            isTruncated: validIDs.count > maximumDisplayedMembers
        )
    }

    public func resolveMembers(in guildID: GuildID, userIDs: [UserID]) async throws -> [Member] {
        var seen: Set<UserID> = []
        let requested = Array(userIDs.filter { seen.insert($0).inserted }.prefix(100))
        guard !requested.isEmpty else { return [] }

        var cachedByID = cachedMemberIndex(guildID: guildID)
        let missing = requested.filter { cachedByID[$0] == nil }
        if !missing.isEmpty {
            try await requestMembersByID(missing, guildID: guildID)
            cachedByID = cachedMemberIndex(guildID: guildID)
        }
        return requested.compactMap { cachedByID[$0] }
    }

    public func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        let key = ProfileCacheKey(userID: userID, guildID: guildID)
        if let cached = cachedProfiles[key] {
            return cached
        }
        if let task = profileTasks[key] {
            return try await task.value
        }
        let task = Task { [self] in
            try await loadProfile(for: userID, in: guildID)
        }
        profileTasks[key] = task
        do {
            let profile = try await task.value
            profileTasks[key] = nil
            cachedProfiles[key] = profile
            return profile
        } catch {
            profileTasks[key] = nil
            throw error
        }
    }

    func loadProfile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        var query = [
            URLQueryItem(name: "with_mutual_guilds", value: "true"),
            URLQueryItem(name: "with_mutual_friends", value: "true"),
            URLQueryItem(name: "with_mutual_friends_count", value: "true"),
        ]
        if let guildID {
            query.append(URLQueryItem(name: "guild_id", value: guildID.description))
        }
        let dto: UserProfileDTO
        do {
            dto = try await request("/users/\(userID)/profile", query: query)
        } catch ChatProviderError.transport(status: 404, requestID: _) {
            throw ChatProviderError.invalidRequest(
                "This profile is unavailable. You may no longer share a server or friendship with this user."
            )
        }

        let effectID =
            dto.guildMemberProfile?.profileEffect?.resolvedID
                ?? dto.userProfile?.profileEffect?.resolvedID
        if effectID != nil, profileEffects == nil { profileEffects = [:] }
        if let effectID, profileEffects?[effectID] == nil {
            let product = await collectibleProduct(for: effectID)
            for effect in product?.items?.elements.filter({ $0.type == 1 }) ?? [] {
                if let id = effect.id {
                    profileEffects?[id] = effect
                }
                if let skuID = effect.skuID {
                    profileEffects?[skuID] = effect
                }
            }
        }

        let profile = try dto.domain(
            guildID: guildID,
            guilds: cachedGuilds,
            guildRoles: guildID.flatMap { cachedGuildRoles[$0] } ?? [],
            effectConfig: effectID.flatMap { profileEffects?[$0] }
        )
        gatewayLogger.debug(
            "Profile assets resolved; bio=\(profile.bio?.isEmpty == false), badges=\(profile.badges.count), effect=\(profile.effect != nil), animations=\(profile.effect?.animations.count ?? 0)"
        )
        return profile
    }

    func collectibleProduct(for effectID: String) async -> CollectibleProductDTO? {
        if let task = collectibleProductTasks[effectID] {
            return await task.value
        }
        let task = Task<CollectibleProductDTO?, Never> { [self] in
            try? await request(
                "/collectibles-products/\(effectID)",
                query: [URLQueryItem(name: "locale", value: clientMetadata.locale)]
            )
        }
        collectibleProductTasks[effectID] = task
        let product = await task.value
        collectibleProductTasks[effectID] = nil
        return product
    }

    public func emojis(in guildID: GuildID) async throws -> [DiscordEmoji] {
        if let cached = cachedEmojis[guildID], cached.isFresh {
            return cached.emojis
        }
        if usesEmojiDiskCache, let disk = try? loadEmojiCache(for: guildID) {
            cachedEmojis[guildID] = disk
            if disk.isFresh {
                return disk.emojis
            }
        }
        if let task = emojiTasks[guildID] {
            do {
                return try await task.value
            } catch {
                if let stale = cachedEmojis[guildID] {
                    return stale.emojis
                }
                throw error
            }
        }
        let task = Task { [self] in
            let payload: [GuildEmojiDTO] = try await request("/guilds/\(guildID)/emojis")
            return payload.compactMap { $0.domain(guildID: guildID) }
        }
        emojiTasks[guildID] = task

        do {
            let emojis = try await task.value
            emojiTasks[guildID] = nil
            let entry = EmojiCacheEntry(fetchedAt: .now, emojis: emojis)
            cachedEmojis[guildID] = entry
            if usesEmojiDiskCache {
                try? persistEmojiCache(entry, for: guildID)
            }
            return emojis
        } catch {
            emojiTasks[guildID] = nil
            if let stale = cachedEmojis[guildID] {
                return stale.emojis
            }
            throw error
        }
    }

    public func emojiUserSettings() async throws -> EmojiUserSettings {
        if let cachedEmojiUserSettings {
            return cachedEmojiUserSettings
        }
        if let task = emojiUserSettingsTask {
            return try await task.value
        }
        let task = Task { [self] in
            let data = try await frecencySettingsProto()
            return DiscordSettingsProto.emojiSettings(from: data)
        }
        emojiUserSettingsTask = task
        do {
            let settings = try await task.value
            emojiUserSettingsTask = nil
            gatewayLogger.info(
                "Decoded emoji settings; favorites=\(settings.favoriteKeys.count), frequent=\(settings.frequentlyUsedKeys.count)"
            )
            cachedEmojiUserSettings = settings
            return settings
        } catch {
            emojiUserSettingsTask = nil
            throw error
        }
    }

    func loadEmojiCache(for guildID: GuildID) throws -> EmojiCacheEntry {
        let data = try Data(contentsOf: try emojiCacheURL(for: guildID))
        return try JSONDecoder().decode(EmojiCacheEntry.self, from: data)
    }

    func persistEmojiCache(_ entry: EmojiCacheEntry, for guildID: GuildID) throws {
        let url = try emojiCacheURL(for: guildID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(entry).write(to: url, options: .atomic)
    }

    func emojiCacheURL(for guildID: GuildID) throws -> URL {
        guard let accountID else { throw ChatProviderError.unauthenticated }
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        return
            base
                .appending(
                    path: "dev.sakuracord.SakuraCord/EmojiCache/\(accountID)",
                    directoryHint: .isDirectory
                )
                .appending(path: "\(guildID).json")
    }

    public func currentStatus() async -> PresenceStatus {
        presenceStatus
    }

    public func updateStatus(_ status: PresenceStatus) async throws {
        try await sendGateway([
            "op": 3,
            "d": ["since": 0, "activities": [], "status": status.rawValue, "afk": false]
                as [String: Any],
        ])
        presenceStatus = status
        if let statusDefaultsKey {
            UserDefaults.standard.set(status.rawValue, forKey: statusDefaultsKey)
        }
    }

    var statusDefaultsKey: String? {
        accountID.map { "dev.sakuracord.presence.\($0)" }
    }

    public func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws
        -> MessagePage
    {
        try await messages(
            in: channelID,
            anchoredAt: before.map(MessageHistoryAnchor.before) ?? .newest,
            limit: limit
        )
    }

    public func messages(
        in channelID: ChannelID,
        anchoredAt anchor: MessageHistoryAnchor,
        limit: Int
    ) async throws -> MessagePage {
        try await messages(
            in: channelID,
            anchoredAt: anchor,
            limit: limit,
            resolvesMissingHistoryMembers: true
        )
    }

    public func messagesForImmediatePresentation(
        in channelID: ChannelID,
        anchoredAt anchor: MessageHistoryAnchor,
        limit: Int
    ) async throws -> MessagePage {
        try await messages(
            in: channelID,
            anchoredAt: anchor,
            limit: limit,
            resolvesMissingHistoryMembers: false
        )
    }

    private func messages(
        in channelID: ChannelID,
        anchoredAt anchor: MessageHistoryAnchor,
        limit: Int,
        resolvesMissingHistoryMembers: Bool
    ) async throws -> MessagePage {
        var query: [URLQueryItem] = []
        switch anchor {
        case .newest:
            break
        case .before(let messageID):
            query.append(URLQueryItem(name: "before", value: messageID.description))
        case .after(let messageID):
            query.append(URLQueryItem(name: "after", value: messageID.description))
        case .around(let messageID):
            query.append(URLQueryItem(name: "around", value: messageID.description))
        }
        let boundedLimit = min(max(limit, 1), 100)
        query.append(
            URLQueryItem(
                name: "limit",
                value: String(boundedLimit)
            )
        )
        let payload: LossyList<MessageDTO> = try await request(
            "/channels/\(channelID)/messages", query: query
        )
        let postprocess = discordPerformanceSignposter.beginInterval(
            "MessageHistoryPostprocess",
            id: discordPerformanceSignposter.makeSignpostID()
        )
        defer {
            discordPerformanceSignposter.endInterval(
                "MessageHistoryPostprocess",
                postprocess
            )
        }
        cacheMessageSearchUsers(payload.elements.flatMap(\.searchIndexUsers))
        if payload.skippedCount > 0 {
            gatewayLogger.warning(
                "Skipped \(payload.skippedCount) unsupported message payloads in channel \(channelID)"
            )
        }
        var values = payload.elements.compactMap { try? $0.domain() }.sorted {
            $0.timestamp < $1.timestamp
        }
        let hydration = discordPerformanceSignposter.beginInterval(
            "MessageHistoryMemberHydration",
            id: discordPerformanceSignposter.makeSignpostID()
        )
        let memberHydration = await hydrateHistoryMembers(
            &values,
            channelID: channelID,
            resolvesMissingMembers: resolvesMissingHistoryMembers
        )
        discordPerformanceSignposter.endInterval(
            "MessageHistoryMemberHydration",
            hydration
        )
        cacheForwardSearchMessageAliases(values)
        for index in values.indices {
            if let existing = cachedMessages[values[index].id] {
                values[index].guildMember = MessageGuildMember.merging(
                    incoming: values[index].guildMember,
                    existing: existing.guildMember
                )
            }
            cachedMessages[values[index].id] = values[index]
        }
        let firstID = values.first?.id
        let lastID = values.last?.id
        let hasMoreBefore: Bool
        let hasMoreAfter: Bool
        switch anchor {
        case .newest:
            hasMoreBefore = values.count == boundedLimit
            hasMoreAfter = false
        case .before:
            hasMoreBefore = values.count == boundedLimit
            hasMoreAfter = true
        case .after:
            hasMoreBefore = false
            hasMoreAfter = values.count == boundedLimit
        case .around(let messageID):
            hasMoreBefore = firstID.map { $0 < messageID } ?? false
            hasMoreAfter = lastID.map { $0 > messageID } ?? false
        }
        return MessagePage(
            messages: values,
            hasMoreBefore: hasMoreBefore,
            hasMoreAfter: hasMoreAfter,
            resolvedMembers: memberHydration.members,
            hasCompleteMemberResolution: memberHydration.isComplete
        )
    }

    func hydrateHistoryMembers(
        _ values: inout [Message],
        channelID: ChannelID,
        resolvesMissingMembers: Bool = true
    ) async -> (members: [Member], isComplete: Bool) {
        if let guildID = cachedChannels.values.lazy.flatMap(\.self).first(where: {
            $0.id == channelID
        })?.guildID {
            for index in values.indices where values[index].guildID == nil {
                values[index].guildID = guildID
            }

            let requested = requestedHistoryMemberIDs[guildID] ?? []
            let resolving = resolvingHistoryMemberIDs[guildID] ?? []
            var membersByID = cachedMemberIndex(guildID: guildID)
            let requiredUserIDs = Set(
                DiscordMessageMemberHydration.userIDs(in: values)
            )
            let missing = DiscordMessageMemberHydration.missingUserIDs(
                in: values,
                cached: Set(membersByID.keys),
                requested: requested
            )
            let hasPendingResolution = !requiredUserIDs.isDisjoint(with: resolving)
            var isComplete = missing.isEmpty && !hasPendingResolution
            if resolvesMissingMembers, !missing.isEmpty {
                requestedHistoryMemberIDs[guildID, default: []].formUnion(missing)
                resolvingHistoryMemberIDs[guildID, default: []].formUnion(missing)
                do {
                    try await requestMembersByID(missing, guildID: guildID)
                    isComplete = !hasPendingResolution
                    resolvingHistoryMemberIDs[guildID]?.subtract(missing)
                    if resolvingHistoryMemberIDs[guildID]?.isEmpty == true {
                        resolvingHistoryMemberIDs[guildID] = nil
                    }
                } catch {
                    isComplete = false
                    requestedHistoryMemberIDs[guildID]?.subtract(missing)
                    if requestedHistoryMemberIDs[guildID]?.isEmpty == true {
                        requestedHistoryMemberIDs[guildID] = nil
                    }
                    resolvingHistoryMemberIDs[guildID]?.subtract(missing)
                    if resolvingHistoryMemberIDs[guildID]?.isEmpty == true {
                        resolvingHistoryMemberIDs[guildID] = nil
                    }
                    gatewayLogger.warning(
                        "History member lookup failed; count=\(missing.count), error=\(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            if !missing.isEmpty {
                membersByID = cachedMemberIndex(guildID: guildID)
            }
            for index in values.indices {
                DiscordMessageMemberHydration.hydrate(
                    message: &values[index],
                    membersByID: membersByID
                )
            }
            return (
                DiscordMessageMemberHydration.userIDs(in: values).compactMap {
                    membersByID[$0]
                },
                isComplete
            )
        }
        return ([], true)
    }

    func cachedMemberIndex(guildID: GuildID) -> [UserID: Member] {
        if let cached = cachedMembersByID[guildID] {
            return cached
        }
        let indexed = Dictionary(
            (cachedMembers[guildID] ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { _, newer in newer }
        )
        cachedMembersByID[guildID] = indexed
        return indexed
    }

}

nonisolated struct DiscordInstallationExperimentsDTO: Decodable {
    let installation: String?
}
