import SakuraCordModels

extension AppModel {
    func navigateConversationHistory(direction: Int) {
        guard let destination = keyboardShortcutHistoryDestination(direction: direction) else { return }
        navigate(to: destination.channelID, historyDestination: destination)
    }

    func keyboardShortcutHistoryDestination(direction: Int) -> ConversationNavigationHistory.Destination? {
        // Resolve only actual history candidates; an empty Back/Forward stack
        // must not build an account-wide channel set on every menu update.
        conversationNavigationHistory.destination(direction: direction) { id in
            !hiddenChannelIDs.contains(id)
                && messagePresentationChannel(id) != nil
        }
    }

    var orderedNavigationGuildIDs: [GuildID] {
        serverRailPresentation.orderedNavigationGuildIDs
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

    /// Menu validation needs existence, not navigation order. Sorting every
    /// server's channels here repeats on observed workspace updates, including
    /// history pagination, and can block the main thread between scroll frames.
    func hasKeyboardShortcutConversationDestination(unreadOnly: Bool, mentionsOnly: Bool = false) -> Bool {
        if !unreadOnly {
            return visibleChannelGroups.contains { group in
                group.channels.contains { channel in
                    channel.guildID == selectedGuildID && channel.id != selectedChannelID
                        && !hiddenChannelIDs.contains(channel.id)
                        && !checkingChannelIDs.contains(channel.id)
                }
            }
        }
        let guildIDs = serverRailPresentation.navigationGuildIDs
        let selectedID = selectedChannelID
        let hiddenIDs = hiddenChannelIDs
        let entries = readState.entries
        let channels = snapshot?.channels ?? []
        let isCandidate: (AccountReadStateModel.Entry) -> Bool = { entry in
            entry.channelID != selectedID && entry.isAccessible && entry.isUnread
                && !hiddenIDs.contains(entry.channelID)
                && (!mentionsOnly || entry.mentionCount > 0)
                && (entry.guildID.map { guildIDs.contains($0) } ?? true)
        }
        let isDestination: (Channel) -> Bool = { channel in
            guard let entry = entries[channel.id], isCandidate(entry),
                  channel.guildID.map({ guildIDs.contains($0) }) ?? true
            else { return false }
            return self.readState.unread(channelID: channel.id)
        }
        // A previously successful position is only a hint. Validate the
        // channel currently at that position against every live input, so
        // snapshot replacement, reordering, mute and access changes remain
        // correct without rebuilding an account-wide index on each update.
        let previousIndex = mentionsOnly
            ? shortcutMentionNavigationCandidateIndex
            : shortcutUnreadNavigationCandidateIndex
        if let previousIndex, channels.indices.contains(previousIndex),
           isDestination(channels[previousIndex])
        {
            return true
        }
        let candidateIndex = entries.values.contains(where: isCandidate)
            ? channels.firstIndex(where: isDestination)
            : nil
        if mentionsOnly {
            shortcutMentionNavigationCandidateIndex = candidateIndex
        } else {
            shortcutUnreadNavigationCandidateIndex = candidateIndex
        }
        return candidateIndex != nil
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
