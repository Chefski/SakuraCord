import Foundation
import SakuraCordModels

nonisolated enum TimelineTextAccessibility {
    static func hiddenSpoilerRanges(
        in value: NSAttributedString,
        revealedLocations: Set<Int>
    ) -> [NSRange] {
        guard value.length > 0 else { return [] }
        var result: [NSRange] = []
        value.enumerateAttribute(
            .discordMarkdownSpoiler,
            in: NSRange(location: 0, length: value.length)
        ) { rawValue, range, _ in
            guard (rawValue as? NSNumber)?.boolValue == true,
                  !revealedLocations.contains(range.location)
            else { return }
            result.append(range)
        }
        return result
    }

    static func text(
        _ value: NSAttributedString,
        revealedLocations: Set<Int>
    ) -> String {
        guard value.length > 0 else { return "" }
        let hiddenRanges = hiddenSpoilerRanges(
            in: value,
            revealedLocations: revealedLocations
        )
        let source = value.string as NSString
        var result = ""
        var cursor = 0
        var hiddenIndex = 0
        while cursor < value.length {
            if hiddenIndex < hiddenRanges.count,
               hiddenRanges[hiddenIndex].location == cursor
            {
                result += "Spoiler"
                cursor = NSMaxRange(hiddenRanges[hiddenIndex])
                hiddenIndex += 1
                continue
            }

            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = value.attributes(
                at: cursor,
                effectiveRange: &effectiveRange
            )
            let nextHiddenLocation = hiddenIndex < hiddenRanges.count
                ? hiddenRanges[hiddenIndex].location
                : value.length
            let runEnd = min(
                NSMaxRange(effectiveRange),
                nextHiddenLocation
            )
            let runRange = NSRange(
                location: cursor,
                length: max(1, runEnd - cursor)
            )
            if let mention = (
                attributes[.nativeTimelineMention]
                    as? NativeTimelineMentionBox
            )?.presentation {
                result += mention.label
            } else if let rawToken =
                attributes[.discordEmojiToken] as? String
            {
                result += ":\(EmojiReference(rawToken: rawToken).name):"
            } else {
                result += source.substring(with: runRange)
                    .replacingOccurrences(of: "\u{fffc}", with: "")
            }
            cursor = NSMaxRange(runRange)
        }
        return result
    }
}
