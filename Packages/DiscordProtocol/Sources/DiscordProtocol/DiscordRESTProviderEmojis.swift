import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    public func emojis(in guildID: GuildID) async throws -> [DiscordEmoji] {
        let cacheGeneration = derivedCacheGeneration
        if let cached = cachedEmojis[guildID], cached.isFresh {
            return cached.emojis
        }
        if usesEmojiDiskCache, !isClearingDerivedCaches, let disk = try? loadEmojiCache(for: guildID) {
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
            #if DEBUG
                await emojiResponseReceivedForTesting?()
            #endif
            return payload.compactMap { $0.domain(guildID: guildID) }
        }
        emojiTasks[guildID] = task

        do {
            let emojis = try await task.value
            emojiTasks[guildID] = nil
            guard derivedCacheGeneration == cacheGeneration, !isClearingDerivedCaches,
                  !requestSafetyCircuitIsOpen else { return emojis }
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
}
