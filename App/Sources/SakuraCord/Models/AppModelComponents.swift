import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func submitComponent(
        on message: Message, customID: String, kind: ComponentInteractionKind, values: [String] = []
    ) async {
        let key = ComponentControlKey(messageID: message.id, customID: customID)
        guard !componentInteractionPresentation.pendingControls.contains(key)
        else { return }
        guard supportedCapabilities.contains(.components) else {
            componentInteractionPresentation.errors[key] =
                ChatProviderError.capabilityDisabled(.components).localizedDescription
            return
        }
        let submission = ComponentInteractionSubmission(
            messageID: message.id, channelID: message.channelID, guildID: message.guildID,
            applicationID: message.applicationID, customID: customID, kind: kind, values: values
        )
        componentInteractionPresentation.pendingControls.insert(key)
        componentKeyByNonce[submission.nonce] = key
        componentInteractionPresentation.errors[key] = nil
        let session = accountSession()
        do {
            try await session.provider.submitComponentInteraction(submission)
        } catch {
            guard isCurrentAccountSession(session) else { return }
            componentInteractionPresentation.pendingControls.remove(key)
            componentKeyByNonce[submission.nonce] = nil
            componentInteractionPresentation.errors[key] =
                error.localizedDescription
        }
    }

    func supportsCapability(_ capability: ChatCapability) -> Bool {
        supportedCapabilities.contains(capability)
    }

    func componentChoices(
        kind: ComponentSelectKind,
        query: String,
        guildID: GuildID?,
        channelID: ChannelID
    ) async throws -> [ComponentSelectOption] {
        guard supportedCapabilities.contains(.remoteComponentChoices) else {
            throw ChatProviderError.capabilityDisabled(
                .remoteComponentChoices
            )
        }
        let session = accountSession()
        let choices = try await session.provider.componentChoices(
                kind: kind,
                query: query,
                guildID: guildID,
                channelID: channelID
            )
        guard isCurrentAccountSession(session) else {
            throw CancellationError()
        }
        return Array(
            resolvedComponentChoices(
                choices,
                kind: kind,
                guildID: guildID
            ).prefix(25)
        )
    }

    func cachedComponentChoices(
        kind: ComponentSelectKind,
        guildID: GuildID?,
        channelTypes: [Int]
    ) -> [ComponentSelectOption] {
        let roles = componentChoiceRoles(in: guildID)
        let choices: [ComponentSelectOption]
        switch kind {
        case .string:
            choices = []
        case .user:
            choices = componentChoiceMembers(in: guildID).map {
                componentChoice(for: $0, roles: roles)
            }
        case .role:
            choices = roles
                .sorted(by: componentChoiceRolePrecedes)
                .map(componentChoice(for:))
        case .mentionable:
            choices = componentChoiceMembers(in: guildID).map {
                componentChoice(for: $0, roles: roles)
            } + roles
                .sorted(by: componentChoiceRolePrecedes)
                .map(componentChoice(for:))
        case .channel:
            choices = componentChoiceChannels(
                in: guildID,
                channelTypes: channelTypes
            ).map(componentChoice(for:))
        }
        return Array(choices.prefix(25))
    }

    private func resolvedComponentChoices(
        _ choices: [ComponentSelectOption],
        kind: ComponentSelectKind,
        guildID: GuildID?
    ) -> [ComponentSelectOption] {
        let membersByValue = Dictionary(
            componentChoiceMembers(in: guildID).map {
                (String($0.id.rawValue), $0)
            },
            uniquingKeysWith: { _, newer in newer }
        )
        let rolesByValue = Dictionary(
            componentChoiceRoles(in: guildID).map {
                (String($0.id.rawValue), $0)
            },
            uniquingKeysWith: { _, newer in newer }
        )
        let channelsByValue = Dictionary(
            componentChoiceChannels(in: guildID, channelTypes: []).map {
                (String($0.id.rawValue), $0)
            },
            uniquingKeysWith: { _, newer in newer }
        )
        let roles = Array(rolesByValue.values)
        return choices.map { choice in
            switch kind {
            case .string:
                choice
            case .user:
                membersByValue[choice.value].map {
                    componentChoice(for: $0, roles: roles)
                } ?? componentChoiceFallback(choice, entityKind: .user)
            case .role:
                rolesByValue[choice.value].map(componentChoice(for:))
                    ?? componentChoiceFallback(choice, entityKind: .role)
            case .mentionable:
                if let member = membersByValue[choice.value] {
                    componentChoice(for: member, roles: roles)
                } else if let role = rolesByValue[choice.value] {
                    componentChoice(for: role)
                } else {
                    choice
                }
            case .channel:
                channelsByValue[choice.value].map(componentChoice(for:))
                    ?? componentChoiceFallback(choice, entityKind: .channel)
            }
        }
    }

    private func componentChoiceMembers(
        in guildID: GuildID?
    ) -> [Member] {
        let values: [Member]
        if let guildID,
           let stored = membersByGuildID[guildID],
           !stored.isEmpty
        {
            values = Array(stored.values)
        } else {
            values = members
        }
        return values.sorted {
            let comparison = $0.user.displayName.localizedCaseInsensitiveCompare(
                $1.user.displayName
            )
            return comparison == .orderedSame
                ? $0.id < $1.id
                : comparison == .orderedAscending
        }
    }

    private func componentChoiceRoles(
        in guildID: GuildID?
    ) -> [GuildRole] {
        if let guildID,
           let stored = guildRolesByGuildID[guildID],
           !stored.isEmpty
        {
            return stored
        }
        return guildRoles
    }

    private func componentChoiceChannels(
        in guildID: GuildID?,
        channelTypes: [Int]
    ) -> [Channel] {
        let source = snapshot?.channels ?? visibleChannels
        return source.filter { channel in
            (guildID == nil || channel.guildID == guildID)
                && (channelTypes.isEmpty
                    || channelTypes.contains(channel.discordCommandType))
        }.sorted {
            if $0.categoryPosition != $1.categoryPosition {
                return $0.categoryPosition < $1.categoryPosition
            }
            if $0.position != $1.position {
                return $0.position < $1.position
            }
            return $0.id < $1.id
        }
    }

    private func componentChoice(
        for member: Member,
        roles: [GuildRole]
    ) -> ComponentSelectOption {
        let roleIDs = Set(member.roleIDs)
        let colorHex = MessageAuthorPresentation.topRoleColor(
            in: member.roles
        ) ?? MessageAuthorPresentation.topRoleColor(
            in: roles.filter { roleIDs.contains($0.id) }
        )
        return ComponentSelectOption(
            label: member.user.displayName,
            value: String(member.id.rawValue),
            description: "@\(member.user.username)",
            imageURL: member.guildAvatarURL ?? member.user.avatarURL,
            imageShape: .circle,
            entityKind: .user,
            colorHex: colorHex
        )
    }

    private func componentChoice(
        for role: GuildRole
    ) -> ComponentSelectOption {
        ComponentSelectOption(
            label: role.name,
            value: String(role.id.rawValue),
            imageURL: role.iconURL,
            imageShape: .roundedRectangle,
            entityKind: .role,
            colorHex: role.colorHex,
            unicodeEmoji: role.unicodeEmoji
        )
    }

    private func componentChoice(
        for channel: Channel
    ) -> ComponentSelectOption {
        ComponentSelectOption(
            label: channel.name,
            value: String(channel.id.rawValue),
            description: channel.category,
            entityKind: .channel,
            channelKind: channel.kind
        )
    }

    private func componentChoiceFallback(
        _ choice: ComponentSelectOption,
        entityKind: ComponentSelectOptionEntityKind
    ) -> ComponentSelectOption {
        var resolved = choice
        resolved.entityKind = entityKind
        if entityKind == .role, resolved.label.hasPrefix("@")
            || entityKind == .channel && resolved.label.hasPrefix("#")
        {
            resolved.label.removeFirst()
        }
        return resolved
    }

    private func componentChoiceRolePrecedes(
        _ lhs: GuildRole,
        _ rhs: GuildRole
    ) -> Bool {
        if lhs.position != rhs.position {
            return lhs.position > rhs.position
        }
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return comparison == .orderedSame
            ? lhs.id < rhs.id
            : comparison == .orderedAscending
    }

    func isComponentPending(messageID: MessageID, customID: String) -> Bool {
        componentInteractionPresentation.pendingControls.contains(
            ComponentControlKey(messageID: messageID, customID: customID))
    }

    func componentSelection(
        messageID: MessageID,
        customID: String
    ) -> [ComponentSelectOption]? {
        componentInteractionPresentation.selections[
            ComponentControlKey(messageID: messageID, customID: customID)
        ]
    }

    func setComponentSelection(
        _ options: [ComponentSelectOption],
        messageID: MessageID,
        customID: String
    ) {
        componentInteractionPresentation.selections[
            ComponentControlKey(messageID: messageID, customID: customID)
        ] = options
    }

    func publishComponentSelectionPresentation() {
        timelinePresentationRevision &+= 1
    }

    func componentError(for messageID: MessageID) -> String? {
        componentInteractionPresentation.errors
            .filter { $0.key.messageID == messageID }
            .sorted { $0.key.customID < $1.key.customID }
            .first?.value
    }

    func dismissInteractionModal() {
        presentedInteractionModal = nil
        interactionModalNonce = nil
    }

    func submitModal(values: [String: [String]], fileURLs: [String: [URL]]) async -> Bool {
        guard let modal = presentedInteractionModal, let nonce = interactionModalNonce else {
            return false
        }
        let session = accountSession()
        do {
            try await session.provider.submitModal(
                ModalSubmission(customID: modal.customID, values: values, fileURLs: fileURLs),
                nonce: nonce
            )
            guard isCurrentAccountSession(session) else { return false }
            dismissInteractionModal()
            return true
        } catch {
            guard isCurrentAccountSession(session) else { return false }
            interactionErrorMessage = error.localizedDescription
            return false
        }
    }

}
