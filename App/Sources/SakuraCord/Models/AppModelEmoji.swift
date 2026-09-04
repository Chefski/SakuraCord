import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func loadEmojis(for guildID: GuildID) async {
        guard emojisByGuild[guildID] == nil, !loadingEmojiGuildIDs.contains(guildID) else { return }
        let session = accountSession()
        loadingEmojiGuildIDs.insert(guildID)
        defer {
            if isCurrentAccountSession(session) {
                loadingEmojiGuildIDs.remove(guildID)
            }
        }
        do {
            let emojis = try await session.provider.emojis(in: guildID)
            guard isCurrentAccountSession(session) else { return }
            applyEmojis(emojis, to: guildID)
        } catch {
            guard isCurrentAccountSession(session) else { return }
            emojiLoadErrorsByGuild[guildID] = error.localizedDescription
        }
    }

    func applyEmojis(_ emojis: [DiscordEmoji], to guildID: GuildID) {
        emojisByGuild[guildID] = emojis
        for emoji in emojis {
            ComposerEmojiImageStore.shared.register(emoji)
        }
        emojiLoadErrorsByGuild[guildID] = nil
    }

    func applyEmojiUpdate(
        upserted: [DiscordEmoji],
        deletedIDs: [String],
        to guildID: GuildID
    ) {
        guard let existing = emojisByGuild[guildID] else {
            // Discord can send a delta when its official client has a cached base.
            // SakuraCord deliberately leaves this guild unresolved so the existing
            // coalesced REST fallback can obtain a complete catalog.
            return
        }
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for id in deletedIDs {
            byID[id] = nil
        }
        for emoji in upserted {
            byID[emoji.id] = emoji
        }
        applyEmojis(
            byID.values.sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            },
            to: guildID
        )
    }

    func retryEmojis(for guildID: GuildID) async {
        emojisByGuild[guildID] = nil
        emojiLoadErrorsByGuild[guildID] = nil
        await loadEmojis(for: guildID)
    }

    func loadDiscordEmojiSettings() async {
        guard !didAttemptDiscordEmojiSettings else { return }
        let session = accountSession()
        didAttemptDiscordEmojiSettings = true
        let settings = try? await session.provider.emojiUserSettings()
        guard isCurrentAccountSession(session) else { return }
        if let settings {
            applyDiscordEmojiSettings(settings)
        }
        // Destination discovery is local once bootstrap state is available.
        // A failed or timed-out settings enrichment must not leave Forward on
        // an infinite loading state; persisted local deltas still provide the
        // best available frecency signal until the next authenticated session.
        hasLoadedDiscordEmojiSettings = true
        applyPersistedDiscordFrecencyUsageDeltas()
        forwardSearchSourceRevision &+= 1
    }

    func applyDiscordEmojiSettings(_ settings: EmojiUserSettings) {
        discordFavoriteEmojiKeys = settings.favoriteKeys
        discordFrequentlyUsedEmojiKeys = settings.frequentlyUsedKeys
        discordEmojiUsageScores = settings.usageScores
        discordGuildAndChannelUsageScores = settings.guildAndChannelUsageScores
        discordSyncedGuildAndChannelUsageScores = settings.guildAndChannelUsageScores
        discordGuildAndChannelUsage = settings.guildAndChannelUsage
        discordGuildAndChannelUsageOrder = settings.guildAndChannelUsageOrder
    }

    func recordEmojiUse(_ key: String) {
        emojiUsageCounts[key, default: 0] += 1
        emojiRecentKeys.removeAll { $0 == key }
        emojiRecentKeys.insert(key, at: 0)
        if emojiRecentKeys.count > 50 {
            emojiRecentKeys.removeLast(emojiRecentKeys.count - 50)
        }
        if persistsEmojiPreferences {
            UserDefaults.standard.set(emojiUsageCounts, forKey: "dev.sakuracord.emoji-usage")
            UserDefaults.standard.set(emojiRecentKeys, forKey: "dev.sakuracord.emoji-recents")
        }
    }

    func clearLocalEmojiRecents() {
        emojiRecentKeys.removeAll()
        if persistsEmojiPreferences {
            UserDefaults.standard.removeObject(forKey: "dev.sakuracord.emoji-recents")
            UserDefaults.standard.set([String](), forKey: "dev.sakuracord.emoji-recents")
        }
    }

    func resetLocalEmojiRanking() {
        emojiUsageCounts.removeAll()
        if persistsEmojiPreferences {
            UserDefaults.standard.removeObject(forKey: "dev.sakuracord.emoji-usage")
        }
    }

    @discardableResult
    func setEmojiFavorite(
        discordKey: String,
        isFavorite: Bool
    ) async -> Bool {
        let session = accountSession()
        do {
            let settings = try await session.provider.setEmojiFavorite(
                discordKey,
                isFavorite: isFavorite
            )
            guard isCurrentAccountSession(session) else { return false }
            applyDiscordEmojiSettings(settings)
            didAttemptDiscordEmojiSettings = true
            hasLoadedDiscordEmojiSettings = true
            forwardSearchSourceRevision &+= 1
            return true
        } catch {
            return false
        }
    }

    func composerText(for emoji: DiscordEmoji) -> String {
        DiscordEmojiPermissionPolicy.composerText(
            for: emoji,
            currentGuildID: selectedGuildID,
            premiumType: snapshot?.currentUser.premiumType ?? 0
        )
    }

    /// Invalidates asynchronous work and presentation state owned by the
    /// current account. IDs are not sufficient guards here because Discord
    /// guild, channel, and thread IDs remain identical when the same account
    /// reconnects through a replacement provider.
}
