import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayChannelAndInteractionEvent(
        name: String,
        body: JSONValue,
        data: Data
    ) async -> Bool {
        switch name {
        case "GUILD_APPLICATION_COMMAND_INDEX_UPDATE":
            await handleGuildApplicationCommandIndexUpdateDispatch(name: name, body: body, data: data)
        case "RATE_LIMITED":
            await handleRateLimitedDispatch(name: name, body: body, data: data)
        case "GUILD_DELETE":
            await handleGuildDeleteDispatch(name: name, body: body, data: data)
        case "CHANNEL_CREATE", "CHANNEL_UPDATE":
            await handleChannelCreateDispatch(name: name, body: body, data: data)
        case "CHANNEL_RECIPIENT_ADD", "CHANNEL_RECIPIENT_REMOVE":
            await handleChannelRecipientAddDispatch(name: name, body: body, data: data)
        case "CHANNEL_DELETE":
            await handleChannelDeleteDispatch(name: name, body: body, data: data)
        case "USER_APPLICATION_UPDATE", "USER_APPLICATION_REMOVE":
            await handleUserApplicationUpdateDispatch(name: name, body: body, data: data)
        case "APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE":
            await handleApplicationCommandAutocompleteResponseDispatch(name: name, body: body, data: data)
        case "INTERACTION_CREATE":
            await handleInteractionCreateDispatch(name: name, body: body, data: data)
        case "INTERACTION_SUCCESS":
            await handleInteractionSuccessDispatch(name: name, body: body, data: data)
        case "INTERACTION_FAILURE":
            await handleInteractionFailureDispatch(name: name, body: body, data: data)
        case "INTERACTION_MODAL_CREATE":
            await handleInteractionModalCreateDispatch(name: name, body: body, data: data)
        case "TYPING_START":
            await handleTypingStartDispatch(name: name, body: body, data: data)
        case "MESSAGE_REACTION_ADD":
            await handleMessageReactionAddDispatch(name: name, body: body, data: data)
        default:
            return false
        }
        return true
    }

    func handleGuildApplicationCommandIndexUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayApplicationCommandIndexUpdateDTO.self, from: data
            ), let guildID = GuildID(update.guildID)
        else { return }
        let target = ApplicationCommandIndexTarget.guild(guildID)
        if cachedApplicationCommandCatalogs[target]?.version != update.version?.value {
            invalidateApplicationCommandCatalog(target)
        }
    }

    func handleRateLimitedDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let rateLimit = try? JSONDecoder().decode(
            GatewayRateLimitedDTO.self, from: data
        ) else { return }
        gatewayOpcodeRateLimitDates[rateLimit.opcode] = Date().addingTimeInterval(
            max(0, rateLimit.retryAfter)
        )
        failGatewayRequests(rateLimited: rateLimit)
    }

    func handleGuildDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let deleted = try? JSONDecoder().decode(
                GatewayDeletedEntityDTO.self, from: data
            ), let guildID = GuildID(deleted.id)
        else { return }
        invalidateApplicationCommandCatalog(.guild(guildID))
        if deleted.unavailable == true {
            if var guild = cachedGuilds[guildID] {
                guild.isUnavailable = true
                cachedGuilds[guildID] = guild
                continuation?.yield(.guildChanged(guild))
            }
        } else {
            removeGuild(guildID)
        }
    }

    func handleChannelCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let dto = try? JSONDecoder().decode(ChannelDTO.self, from: data) else {
            return
        }
        if dto.isThread {
            ingestForumThreads(
                [dto],
                fallbackGuildID: dto.guildID.flatMap(GuildID.init),
                advancesParentLatestThreadID: name == "CHANNEL_CREATE"
            )
            return
        }
        if let guildID = dto.guildID.flatMap(GuildID.init) {
            if name == "CHANNEL_CREATE", let channelID = ChannelID(dto.id) {
                appendQuickSwitcherChannelStoreOrder([channelID])
                persistQuickSwitcherChannelStoreCache()
            }
            cachedGuildChannelDTOs[guildID, default: [:]][dto.id] = dto
            publishGuildChannels(guildID)
            return
        }
        if let recipients = dto.recipients {
            cacheLiveSearchUsers(recipients)
        }
        if let channelID = ChannelID(dto.id) {
            lazyPrivateChannelIDs.remove(channelID)
        }
        cachePrivateRecipientReferences([dto])
        guard dto.type == 1 || dto.type == 3,
              var channel = try? dto.domain(
                  guildID: nil,
                  knownUsersByID: cachedGatewayUsersByID
              )
        else { return }
        if name == "CHANNEL_UPDATE", let existing = privateChannel(id: channel.id) {
            if dto.recipients == nil, dto.recipientIDs == nil {
                channel.recipients = existing.recipients
            }
            if dto.name == nil, dto.recipients == nil, dto.recipientIDs == nil {
                channel.name = existing.name
            }
            if dto.ownerID == nil {
                channel.ownerID = existing.ownerID
            }
            if dto.icon == nil {
                channel.iconURL = existing.iconURL
            }
            if dto.lastMessageID == nil {
                channel.lastMessageID = existing.lastMessageID
            }
        }
        upsertPrivateChannel(channel)
    }

    func handleChannelRecipientAddDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(
            GatewayChannelRecipientDTO.self,
            from: data
        ),
            let channelID = ChannelID(update.channelID),
            var channel = privateChannel(id: channelID),
            let user = try? update.user.domain()
        else { return }
        if name == "CHANNEL_RECIPIENT_ADD" {
            cacheLiveSearchUsers([update.user])
            if !channel.recipients.contains(where: { $0.id == user.id }) {
                channel.recipients.append(user)
            }
            channel.kind = .groupDirectMessage
        } else {
            channel.recipients.removeAll { $0.id == user.id }
        }
        channel.recipients = DiscordPrivateRecipientOrdering.sortedDomainUsers(
            channel.recipients,
            channelID: update.channelID,
            channelType: channel.kind == .groupDirectMessage ? 3 : 1
        )
        cachedPrivateRecipientIDsByChannelID[channelID] =
            channel.recipients.map { $0.id.description }
        upsertPrivateChannel(channel)
    }

    func handleChannelDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let deleted = try? JSONDecoder().decode(
                GatewayDeletedEntityDTO.self, from: data
            ), let channelID = ChannelID(deleted.id)
        else { return }
        invalidateApplicationCommandCatalog(.channel(channelID))
        let guildID = deleted.guildID.flatMap(GuildID.init)
            ?? cachedGuildChannelDTOs.first(where: { $0.value[deleted.id] != nil })?.key
        if let guildID {
            cachedGuildChannelDTOs[guildID]?[deleted.id] = nil
            cachedForumPosts[channelID] = nil
            for parentID in cachedForumPosts.keys {
                cachedForumPosts[parentID]?[channelID] = nil
            }
            publishGuildChannels(guildID)
            return
        }
        if cachedChannels[nil]?.contains(where: { $0.id == channelID }) == true {
            cachedChannels[nil]?.removeAll { $0.id == channelID }
            lazyPrivateChannelIDs.remove(channelID)
            continuation?.yield(
                .channelsChanged(guildID: nil, channels: cachedChannels[nil] ?? [])
            )
            continuation?.yield(.privateMembersChanged(privateMembersInChannelOrder()))
        }
    }

    func handleUserApplicationUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        invalidateApplicationCommandCatalog(.user)
    }

    func handleApplicationCommandAutocompleteResponseDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let response = try? JSONDecoder().decode(
                GatewayApplicationCommandAutocompleteDTO.self, from: data
            )
        else { return }
        let nonce = response.nonce.value
        guard let optionType = pendingAutocompleteTypes.removeValue(forKey: nonce) else {
            return
        }
        autocompleteTimeoutTasks.removeValue(forKey: nonce)?.cancel()
        let choices = response.choices.compactMap { $0.domain(optionType: optionType) }
        continuation?.yield(
            .applicationCommandAutocomplete(
                ApplicationCommandAutocompleteResult(nonce: nonce, choices: choices)
            )
        )
    }

    func handleInteractionCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let event = try? JSONDecoder().decode(
                GatewayInteractionLifecycleDTO.self, from: data),
            let nonce = event.nonce?.value, let interactionID = event.id
        else { return }
        continuation?.yield(
            .interaction(.created(nonce: nonce, interactionID: interactionID))
        )
    }

    func handleInteractionSuccessDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let event = try? JSONDecoder().decode(
                GatewayInteractionLifecycleDTO.self, from: data),
            let nonce = event.nonce?.value
        else { return }
        if pendingAutocompleteTypes[nonce] == nil {
            continuation?.yield(.interaction(.succeeded(nonce: nonce)))
        }
    }

    func handleInteractionFailureDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let event = try? JSONDecoder().decode(
                GatewayInteractionLifecycleDTO.self, from: data),
            let nonce = event.nonce?.value
        else { return }
        pendingAutocompleteTypes[nonce] = nil
        autocompleteTimeoutTasks.removeValue(forKey: nonce)?.cancel()
        continuation?.yield(
            .interaction(
                .failed(
                    nonce: nonce,
                    message: event.errorMessage
                        ?? event.errorCode.map {
                            "Discord rejected the interaction (code \($0))."
                        }
                        ?? "Discord rejected the interaction."
                )
            )
        )
    }

    func handleInteractionModalCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let event = try? JSONDecoder().decode(
                GatewayInteractionModalDTO.self, from: data
            )
        else { return }
        pendingModalContexts[event.nonce.value] = event
        continuation?.yield(
            .interaction(.presentModal(nonce: event.nonce.value, modal: event.modal))
        )
    }

    func handleTypingStartDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let typing = try? JSONDecoder().decode(TypingStartDTO.self, from: data),
              let channelID = ChannelID(typing.channelID),
              let userID = UserID(typing.userID),
              let user = DiscordTypingEventResolver.resolve(.init(
                  typing: typing,
                  userID: userID,
                  currentUser: currentUser,
                  currentStatus: presenceStatus,
                  cachedMembers: cachedMembers,
                  cachedChannels: cachedChannels.values.flatMap(\.self),
                  cachedMessages: Array(cachedMessages.values),
                  cachedGuildRoles: cachedGuildRoles
              ))
        else {
            gatewayLogger.debug("Ignored an unresolved or malformed typing event")
            return
        }
        continuation?.yield(.typing(channelID: channelID, user: user))
    }

    func handleMessageReactionAddDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let value = try? JSONDecoder().decode(
                GatewayMessageReactionUserDTO.self,
                from: data
            ),
            let update = value.domainUpdate(isAddition: true)
        else { return }
        applyGatewayReactionUpdate(update)
    }
}
