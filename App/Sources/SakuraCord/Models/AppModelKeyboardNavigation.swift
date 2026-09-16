import SakuraCordModels

extension AppModel {
    func navigateConversationHistory(direction: Int) {
        guard let destination = keyboardShortcutHistoryDestination(direction: direction) else { return }
        navigate(to: destination.channelID, historyDestination: destination)
    }

    func keyboardShortcutHistoryDestination(direction: Int) -> ConversationNavigationHistory.Destination? {
        let availableIDs = Set((snapshot?.channels ?? []).map(\.id))
            .union(visibleChannels.map(\.id))
            .subtracting(hiddenChannelIDs)
        return conversationNavigationHistory.destination(direction: direction, availableChannelIDs: availableIDs)
    }

    var orderedNavigationGuildIDs: [GuildID] {
        serverRailItems.flatMap { item -> [GuildID] in
            switch item {
            case let .guild(id): [id]
            case let .folder(folder): folder.guildIDs
            }
        }.filter { serverRailGuildsByID[$0] != nil }
    }

    func navigateShortcutServer(direction: Int) {
        if let guildID = keyboardShortcutServerDestination(direction: direction) {
            selectGuild(guildID)
        }
    }

    func keyboardShortcutServerDestination(direction: Int) -> GuildID? {
        let guildIDs = orderedNavigationGuildIDs
        guard !guildIDs.isEmpty else { return nil }
        let currentIndex = guildIDs.firstIndex { $0 == selectedGuildID }
        let start = currentIndex ?? (direction > 0 ? -1 : 0)
        let destination = guildIDs[(start + direction + guildIDs.count) % guildIDs.count]
        return destination == selectedGuildID ? nil : destination
    }

    func navigateShortcutConversation(direction: Int, unreadOnly: Bool, mentionsOnly: Bool = false) {
        if let channelID = keyboardShortcutConversationDestination(direction: direction, unreadOnly: unreadOnly, mentionsOnly: mentionsOnly) {
            navigate(to: channelID)
        }
    }

    func keyboardShortcutConversationDestination(direction: Int, unreadOnly: Bool, mentionsOnly: Bool = false) -> ChannelID? {
        let channels = shortcutConversationChannels(acrossServers: unreadOnly)
        guard !channels.isEmpty else { return nil }
        // Keep read channels in the ordered sequence so traversal starts at the
        // current conversation even after opening it clears its unread state.
        let currentIndex = channels.firstIndex { $0.id == selectedChannelID }
        let start = currentIndex ?? (direction > 0 ? -1 : 0)
        for offset in 1 ... channels.count {
            let index = (start + direction * offset + channels.count) % channels.count
            let channel = channels[index]
            guard channel.id != selectedChannelID,
                  !hiddenChannelIDs.contains(channel.id)
            else { continue }
            if unreadOnly {
                // Account read state already gates accessibility, including
                // authoritative unread evidence for servers not yet activated.
                guard readState.unread(channelID: channel.id),
                      !mentionsOnly || readState.mentions(channelID: channel.id) > 0 else { continue }
            } else if checkingChannelIDs.contains(channel.id) {
                continue
            }
            return channel.id
        }
        return nil
    }

    private func shortcutConversationChannels(acrossServers: Bool) -> [Channel] {
        guard acrossServers else {
            return visibleChannelGroups.flatMap(\.channels).filter { $0.guildID == selectedGuildID }
        }
        let channelsByGuild = Dictionary(grouping: snapshot?.channels ?? [], by: \.guildID)
        let scopes: [GuildID?] = [nil] + orderedNavigationGuildIDs.map { $0 }
        return scopes.flatMap { guildID in
            ChannelGroup.make(from: channelsByGuild[guildID] ?? []).flatMap(\.channels)
        }
    }
}
