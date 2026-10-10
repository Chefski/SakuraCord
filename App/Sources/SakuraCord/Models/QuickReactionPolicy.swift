import Foundation
import SakuraCordModels

/// One emoji in the message hover toolbar's quick-reaction section.
nonisolated struct QuickReaction: Identifiable, Equatable, Sendable {
    /// Tone-folded Unicode key or custom emoji ID.
    let id: String
    /// The reaction token for the shared toggle. An applied reaction keeps the
    /// message's own token so the toggle removes that exact reaction.
    let token: String
    /// Discord's tooltip name: the Unicode unique name or custom emoji name.
    let name: String
    let isApplied: Bool
}

/// Discord's message hover bar quick reactions: the reaction frecency list,
/// resolved and tone-folded, minus emoji that are filtered or locked for a
/// reaction in this channel. Fewer than three usable entries are topped up
/// with a fixed fallback set before taking the first three.
enum QuickReactionPolicy {
    static let limit = 3
    static let candidateLimit = 42
    static let fallbackKeys = ["100", "laughing", "sparkling_heart"]

    struct Context {
        /// The message channel's guild; nil in DMs and group DMs.
        var guildID: GuildID?
        var hasNitro: Bool
        var canUseExternalEmojis: Bool
        var roleIDsByGuild: [GuildID: Set<RoleID>] = [:]
        var skinTone: NativeEmojiSkinTone = .standard
    }

    private enum Candidate {
        case native(key: String, value: String)
        case custom(DiscordEmoji)

        var foldedKey: String {
            switch self {
            case let .native(key, _): key
            case let .custom(emoji): emoji.id
            }
        }
    }

    /// - Parameters:
    ///   - rankedKeys: Reaction frecency keys, highest first.
    ///   - customEmojisByID: Custom emoji the account can resolve.
    static func reactions(
        rankedKeys: [String],
        customEmojisByID: [String: DiscordEmoji],
        existingReactions: [Reaction],
        context: Context
    ) -> [QuickReaction] {
        let resolved = rankedKeys.lazy
            .compactMap { resolve($0, customEmojisByID: customEmojisByID) }
            .prefix(candidateLimit)
        let usable = folded(Array(resolved)).filter { isUsable($0, context: context) }
        let fallback = fallbackKeys.compactMap { resolve($0, customEmojisByID: [:]) }
        let selected = usable.count >= limit ? usable : folded(usable + fallback)
        return selected.prefix(limit).map {
            quickReaction(for: $0, existingReactions: existingReactions, skinTone: context.skinTone)
        }
    }

    /// Discord's `getEmojiUnavailableReason` for the reaction intention,
    /// keeping only the filtered and premium-locked outcomes.
    static func canReact(with emoji: DiscordEmoji, context: Context) -> Bool {
        let isInternal = emoji.guildID == context.guildID
        if context.guildID != nil, !isInternal, !context.canUseExternalEmojis { return false }
        guard emoji.isAvailable else { return false }
        if !context.hasNitro, !isInternal, !emoji.isManaged { return false }
        if !emoji.roleIDs.isEmpty,
           context.roleIDsByGuild[emoji.guildID]?.isDisjoint(with: emoji.roleIDs) != false
        {
            return false
        }
        return !emoji.isAnimated || context.hasNitro
    }

    private static func resolve(_ key: String, customEmojisByID: [String: DiscordEmoji]) -> Candidate? {
        if let emoji = customEmojisByID[key] { return .custom(emoji) }
        let base = EmojiFrecencyKeys.baseKey(key)
        guard let value = EmojiFrecencyKeys.value(for: base) else { return nil }
        return .native(key: base, value: value)
    }

    /// Keeps each base emoji or custom ID at its first position.
    private static func folded(_ candidates: [Candidate]) -> [Candidate] {
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.foldedKey).inserted }
    }

    private static func isUsable(_ candidate: Candidate, context: Context) -> Bool {
        guard case let .custom(emoji) = candidate else { return true }
        return canReact(with: emoji, context: context)
    }

    private static func quickReaction(
        for candidate: Candidate,
        existingReactions: [Reaction],
        skinTone: NativeEmojiSkinTone
    ) -> QuickReaction {
        let token: String
        let name: String
        let applied: Reaction?
        switch candidate {
        case let .native(key, value):
            token = NativeEmojiPickerIndex.emoji(forValue: value)?.value(for: skinTone) ?? value
            name = key
            applied = existingReactions.first {
                $0.didCurrentUserReact && $0.emojiReference.id == nil
                    && normalized($0.emoji) == normalized(token)
            }
        case let .custom(emoji):
            token = emoji.messageToken
            name = emoji.name
            applied = existingReactions.first {
                $0.didCurrentUserReact && $0.emojiReference.id == emoji.id
            }
        }
        return QuickReaction(
            id: candidate.foldedKey,
            token: applied?.emoji ?? token,
            name: name,
            isApplied: applied != nil
        )
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FE0F}", with: "")
    }
}
