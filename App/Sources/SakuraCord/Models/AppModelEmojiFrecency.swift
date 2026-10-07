import DiscordProtocol
import Foundation
import MessageRendering
import SakuraCordModels

extension AppModel {
    func configureEmojiFrecency(scope: String) {
        emojiFrecency.configure(scope: scope, persists: persistsEmojiPreferences)
        reactionEmojiFrecency.configure(scope: scope, persists: persistsEmojiPreferences)
        emojiSettingsDataVersion = nil
        deferredEmojiSettings = nil
        refreshEmojiFrecencyPresentation()
        let session = accountSession(allowsTransition: true)
        Task { [weak self] in
            await session.provider.configureEmojiFrecencyPersistence { [weak self] in
                await self?.prepareEmojiFrecencyContribution(session: session)
            }
        }
    }

    func updateEmojiFrecency(_ settings: EmojiUserSettings) {
        if let version = settings.dataVersion, let current = emojiSettingsDataVersion, version < current { return }
        emojiSettingsDataVersion = settings.dataVersion
        emojiFrecency.overwrite(with: settings.messageHistory)
        reactionEmojiFrecency.overwrite(with: settings.reactionHistory)
        hasLoadedDiscordEmojiSettings = true
        refreshEmojiFrecencyPresentation()
    }

    func refreshEmojiFrecencyPresentation() {
        discordFrequentlyUsedEmojiKeys = emojiFrecency.frequently
        discordFrequentlyUsedReactionKeys = reactionEmojiFrecency.frequently
        discordEmojiUsageScores = Dictionary(uniqueKeysWithValues: emojiFrecency.historyForSave().entries.map { ($0.key, Int($0.score)) })
        discordReactionUsageScores = Dictionary(uniqueKeysWithValues: reactionEmojiFrecency.historyForSave().entries.map { ($0.key, Int($0.score)) })
    }

    func recordMessageEmojiUsage(_ content: String, session: AppModelAccountSession) {
        guard !Task.isCancelled, isCurrentAccountSession(session) else { return }
        recordMessageEmojiUsage(content)
    }

    func recordMessageEmojiUsage(_ content: String) {
        for key in EmojiFrecencyKeys.messageKeys(in: content, customEmojis: orderedCustomEmojis) { emojiFrecency.recordUse(key) }
        refreshEmojiFrecencyPresentation()
    }

    func recordReactionEmojiUsage(_ token: String) {
        guard let key = EmojiFrecencyKeys.reactionKey(token) else { return }
        reactionEmojiFrecency.recordUse(key)
        emojiFrecency.recordUse(key)
        refreshEmojiFrecencyPresentation()
    }

    /// Contribute a captured prefix when GIFs, stickers, sounds or commands
    /// cause a type-2 settings write. Incoming echoes use the same save slot.
    func prepareEmojiFrecencyContribution(session: AppModelAccountSession) async -> EmojiFrecencySaveContribution? {
        guard isCurrentAccountSession(session), emojiFrecencySaveTask == nil,
              emojiFrecency.hasPendingUsage || reactionEmojiFrecency.hasPendingUsage else { return nil }
        if !emojiFrecency.hasLoadedRemoteHistory { await loadDiscordEmojiSettings() }
        guard isCurrentAccountSession(session), !Task.isCancelled, emojiFrecencySaveTask == nil,
              emojiFrecency.hasLoadedRemoteHistory else { return nil }
        let messages = emojiFrecency.pendingUsages
        let reactions = reactionEmojiFrecency.pendingUsages
        let (stream, continuation) = AsyncStream<EmojiUserSettings?>.makeStream()
        let saving = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            defer { releaseEmojiFrecencySave(session: session) }
            for await settings in stream {
                guard !Task.isCancelled, isCurrentAccountSession(session), let settings else { return false }
                acknowledgeEmojiFrecencySave(settings, messages: messages, reactions: reactions)
                return true
            }
            return false
        }
        emojiFrecencySaveTask = saving
        return EmojiFrecencySaveContribution(
            messages: emojiFrecency.historyForSave(), reactions: reactionEmojiFrecency.historyForSave()
        ) { settings in
            continuation.yield(settings)
            continuation.finish()
            _ = await saving.value
        }
    }

    private func acknowledgeEmojiFrecencySave(
        _ settings: EmojiUserSettings,
        messages: [DiscordFrecencyStore.PendingUsage], reactions: [DiscordFrecencyStore.PendingUsage]
    ) {
        emojiFrecency.acknowledge(messages)
        reactionEmojiFrecency.acknowledge(reactions)
        discordFavoriteEmojiKeys = settings.favoriteKeys
        updateEmojiFrecency(settings)
    }

    private func releaseEmojiFrecencySave(session: AppModelAccountSession) {
        guard isCurrentAccountSession(session) else { return }
        emojiFrecencySaveTask = nil
        if let deferred = deferredEmojiSettings {
            deferredEmojiSettings = nil
            applyDiscordEmojiSettings(deferred)
        }
    }

    /// Uses remain local until Discord's connection/timer flush or an explicit
    /// favorite save. Both message and reaction maps travel in the same PATCH.
    @discardableResult
    func flushEmojiFrecencyIfNeeded(favoriteKey: String? = nil, isFavorite: Bool = false) async -> Bool {
        if let saving = emojiFrecencySaveTask {
            let success = await saving.value
            guard favoriteKey != nil else { return success }
            guard !Task.isCancelled else { return false }
            return await flushEmojiFrecencyIfNeeded(favoriteKey: favoriteKey, isFavorite: isFavorite)
        }
        guard emojiFrecency.hasPendingUsage || reactionEmojiFrecency.hasPendingUsage || favoriteKey != nil else { return true }
        let session = accountSession()
        let saving = Task { [weak self] () -> Bool in
            guard let self else { return false }
            defer { releaseEmojiFrecencySave(session: session) }
            // Load before capturing the prefix. A read or Gateway update while
            // loading is deferred by the save slot, then replayed exactly once.
            if !emojiFrecency.hasLoadedRemoteHistory { await loadDiscordEmojiSettings() }
            guard !Task.isCancelled, isCurrentAccountSession(session) else { return false }
            if let deferred = deferredEmojiSettings {
                deferredEmojiSettings = nil
                updateEmojiFrecency(deferred)
            }
            guard emojiFrecency.hasLoadedRemoteHistory else { return false }
            let messages = emojiFrecency.pendingUsages
            let reactions = reactionEmojiFrecency.pendingUsages
            do {
                let settings = try await session.provider.saveEmojiFrecency(
                    emojiFrecency.historyForSave(), reactions: reactionEmojiFrecency.historyForSave(),
                    favoriteKey: favoriteKey, isFavorite: isFavorite
                )
                guard !Task.isCancelled, isCurrentAccountSession(session) else { return false }
                acknowledgeEmojiFrecencySave(settings, messages: messages, reactions: reactions)
                return true
            } catch {
                guard isCurrentAccountSession(session) else { return false }
                if !(error is CancellationError) { DiscordAPIDiagnosticStore.shared.recordClientFailure(error) }
                return false
            }
        }
        emojiFrecencySaveTask = saving
        return await saving.value
    }
}
