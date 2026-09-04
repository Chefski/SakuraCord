import MessageRendering
import SakuraCordModels
import SwiftUI
import UniformTypeIdentifiers

enum ColonAutocompleteSuggestionFactory {
    private struct RankedSuggestion {
        let suggestion: ColonAutocompleteSuggestion
        let isFavorite: Bool
        let score: Double
    }

    static func suggestions(
        query: String,
        customEmojis: [DiscordEmoji],
        customValue: (DiscordEmoji) -> String,
        customSource: (DiscordEmoji) -> String? = { _ in nil },
        discordFavoriteKeys: Set<String> = [],
        usageCounts: [String: Int] = [:],
        discordUsageScores: [String: Int] = [:],
        discordSettingsAreLoaded: Bool? = nil
    ) -> [ColonAutocompleteSuggestion] {
        let normalizedQuery = DiscordEmojiAutocompleteRanking.searchNormalized(query)
        var values = NativeEmojiAutocompleteCatalog.search(query).map { result in
            ColonAutocompleteSuggestion(
                id: result.id,
                title: result.name,
                detail: ":\(result.shortcode):",
                // Discord searches aliases but scores and alphabetizes the
                // entry's primary name. This keeps alias-only matches such as
                // :100: after the primary `sc…` prefix block.
                rankingName: result.rankingName,
                value: result.value,
                imageURL: nil,
                source: nil,
                usageKey: "unicode:\(result.value)",
                discordUsageKeys: [result.rankingName],
                completionNames: result.completionNames,
                customEmoji: nil,
                stableOrder: result.catalogIndex
            )
        }
        let availableCustomEmojis = customEmojis.filter(\.isAvailable)
        let normalizedCustomEmojis = availableCustomEmojis.map { emoji in
            (emoji, DiscordEmojiAutocompleteRanking.searchNormalized(emoji.name))
        }
        var duplicateCounts: [String: Int] = [:]
        duplicateCounts.reserveCapacity(normalizedCustomEmojis.count)
        for (_, normalizedName) in normalizedCustomEmojis {
            duplicateCounts[normalizedName, default: 0] += 1
        }
        var duplicateOrdinals: [String: Int] = [:]
        values.append(contentsOf: normalizedCustomEmojis.enumerated().compactMap { index, element in
            let (emoji, normalizedName) = element
            let ordinal = duplicateOrdinals[normalizedName, default: 0]
            duplicateOrdinals[normalizedName] = ordinal + 1
            let displayName = duplicateCounts[normalizedName, default: 0] > 1 && ordinal > 0
                ? "\(emoji.name)~\(ordinal)"
                : emoji.name
            guard normalizedName.contains(normalizedQuery) else { return nil }
            return ColonAutocompleteSuggestion(
                id: "custom:\(emoji.id)",
                title: displayName,
                detail: ":\(displayName):",
                rankingName: displayName,
                value: customValue(emoji),
                imageURL: emoji.imageURL,
                source: customSource(emoji),
                usageKey: "custom:\(emoji.name):\(emoji.id)",
                discordUsageKeys: [emoji.id],
                completionNames: ordinal > 0 ? [displayName, emoji.name] : [emoji.name],
                customEmoji: emoji,
                stableOrder: 100_000 + index
            )
        })

        let usesDiscordSettings = discordSettingsAreLoaded
            ?? !discordUsageScores.isEmpty
        let boundaryExpression = DiscordEmojiAutocompleteRanking.boundaryExpression(query: query)
        let ranked = values.map { suggestion in
            let isFavorite = suggestion.discordUsageKeys.contains(
                where: discordFavoriteKeys.contains
            )
            let frecency = usesDiscordSettings
                ? suggestion.discordUsageKeys.compactMap { discordUsageScores[$0] }.max()
                : nil
            var score = DiscordEmojiAutocompleteRanking.relevance(
                name: suggestion.rankingName,
                query: query,
                boundaryExpression: boundaryExpression
            )
            if let frecency { score *= Double(frecency) / 100 }
            return RankedSuggestion(
                suggestion: suggestion,
                isFavorite: isFavorite,
                score: score
            )
        }
        return ranked.sorted { lhs, rhs in
            // The visible composer hoists matching favorites before the base
            // EmojiStore result. Preserve the account's stored favorite order
            // implicitly through the stable result catalogue when both match.
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.suggestion.rankingName != rhs.suggestion.rankingName {
                return lhs.suggestion.rankingName < rhs.suggestion.rankingName
            }
            if lhs.suggestion.stableOrder != rhs.suggestion.stableOrder {
                return lhs.suggestion.stableOrder < rhs.suggestion.stableOrder
            }
            return lhs.suggestion.id < rhs.suggestion.id
        }.map(\.suggestion)
    }
}
