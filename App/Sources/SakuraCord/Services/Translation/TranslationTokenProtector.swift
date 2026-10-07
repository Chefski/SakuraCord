import Foundation

/// A structure-aware translation plan. Protected syntax never enters the model:
/// only prose slots are translated, then inserted at their original positions.
/// No user text can collide with a placeholder because none are sent or restored.
nonisolated struct TranslationTokenProtector: Equatable, Sendable {
    nonisolated struct Slot: Equatable, Sendable {
        let index: Int
        let text: String
    }

    let original: String
    let parts: [String]
    let slots: [Slot]

    init(_ text: String) {
        original = text
        var parts: [String] = []
        var slots: [Slot] = []
        var cursor = text.startIndex
        func appendProse(_ prose: Substring) {
            let raw = String(prose)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains),
                  let range = raw.range(of: trimmed)
            else {
                parts.append(raw)
                return
            }
            parts.append(String(raw[..<range.lowerBound]))
            slots.append(Slot(index: parts.count, text: trimmed))
            parts.append(trimmed)
            parts.append(String(raw[range.upperBound...]))
        }
        for match in Self.syntax.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            appendProse(text[cursor ..< range.lowerBound])
            parts.append(String(text[range]))
            cursor = range.upperBound
        }
        appendProse(text[cursor...])
        self.parts = parts
        self.slots = slots
    }

    var hasTranslatableText: Bool { !slots.isEmpty }

    /// Require exactly one response for every slot; never accept model-generated
    /// Discord syntax, new spoilers, links, code, or private-use placeholder text.
    func restore(_ responses: [Slot]) throws -> String {
        guard responses.count == slots.count,
              Set(responses.map(\.index)) == Set(slots.map(\.index)),
              Set(responses.map(\.index)).count == responses.count
        else { throw LocalTranslationError.protectedTokenChanged }
        var output = parts
        let replacements = Dictionary(uniqueKeysWithValues: responses.map { ($0.index, $0.text) })
        var isBlockStart = true
        for index in output.indices {
            if let response = replacements[index] {
                let value = response.trimmingCharacters(in: .whitespacesAndNewlines)
                // A fragment after bold text or a mention is not a new line.
                // Preserve that context when checking anchored Markdown syntax.
                let contextualValue = isBlockStart ? value : "x" + value
                guard !value.isEmpty,
                      Self.syntax.firstMatch(in: contextualValue, range: NSRange(contextualValue.startIndex..., in: contextualValue)) == nil
                else { throw LocalTranslationError.protectedTokenChanged }
                output[index] = value
            }
            // Existing quote/list/heading prefixes still leave us at the start
            // of block content; they must not enable an injected nested list.
            if isBlockStart, output[index].range(of: Self.blockPrefixPattern + "$", options: .regularExpression) != nil {
                continue
            }
            for character in output[index] {
                if character.isNewline {
                    isBlockStart = true
                } else if character != " ", character != "\t", character != ">" {
                    isBlockStart = false
                }
            }
        }
        return output.joined()
    }

    // Preserve Markdown delimiters and line structure, including unmatched code
    // fences. Link destinations (including non-HTTP schemes) stay byte-for-byte.
    // Splitting prose at syntax boundaries trades some context for token safety.
    // Fences close on delimiter lines; inline code needs matching backtick runs.
    private static let blockPrefixPattern = #"^[ \t]*(?:#{1,3} |[-+] |\d+\. )"#

    private static let syntax: NSRegularExpression = {
        let pattern = [
        #"(?m:^[ \t]*(?:>[ \t]*)*(`{3,})(?!`)[^\n]*\n[\s\S]*?(?:^[ \t]*(?:>[ \t]*)*\1`*[ \t]*\r?$|\z))"#,
        #"(`+)(?!`)[\s\S]*?(?:(?<!`)\2(?!`)|\z)"#,
        #"\[[^\]\n]*\]\(https?://(?:cdn|media)\.discordapp\.(?:com|net)/emojis/[^\s]+?\)"#,
        #"\]\([^\n]*\)"#,
        #"<[^>\n]*>"#,
        #"@(?:everyone|here)\b"#,
        #"(?:https?://|www\.)[^\s<>]+"#,
        #"\\[^\n]"#,
        #"[\p{Co}]+"#,
        #"[0-9#*]\x{FE0F}?\x{20E3}|(?=[\p{Extended_Pictographic}\p{Regional_Indicator}\p{Emoji_Modifier}])\X"#,
        #"[\r\n]+|[*_~|`\[\]<>]+"#,
        "(?m)" + blockPrefixPattern,
        ].joined(separator: "|")
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid translation syntax expression")
        }
    }()
}
