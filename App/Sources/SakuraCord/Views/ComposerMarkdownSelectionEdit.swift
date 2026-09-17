import AppKit
import MessageRendering

/// Splits a surrounding Markdown span without changing styles outside the selection.
@MainActor
enum ComposerMarkdownSelectionEdit {
    static func removing(
        from format: DiscordMarkdown.SourceFormat,
        keeping remainingDelimiter: String,
        selection: NSRange,
        text: NSAttributedString,
        formats: [DiscordMarkdown.SourceFormat],
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> (text: NSAttributedString, selection: NSRange) {
        func literal(_ range: NSRange, clippedTo clip: NSRange) -> Fragment {
            let range = NSIntersectionRange(range, clip)
            guard range.length > 0 else { return Fragment() }
            let selected = NSIntersectionRange(range, selection)
            return Fragment(
                text: NSMutableAttributedString(attributedString: text.attributedSubstring(from: range)),
                selection: selected.length > 0
                    ? NSRange(location: selected.location - range.location, length: selected.length) : nil
            )
        }

        func body(_ range: NSRange, clippedTo clip: NSRange) -> Fragment {
            var result = Fragment()
            var cursor = range.location
            // Source formats are ordered with parents before their children.
            // Advancing past each complete child also skips its descendants.
            for child in formats {
                let width = child.delimiter.utf16.count
                let outer = NSRange(location: child.range.location - width, length: child.range.length + 2 * width)
                guard outer.location >= cursor, NSMaxRange(outer) <= NSMaxRange(range) else { continue }
                result.append(literal(NSRange(location: cursor, length: outer.location - cursor), clippedTo: clip))
                if NSIntersectionRange(child.range, clip).length > 0 {
                    result.append(body(child.range, clippedTo: clip).wrapped(in: child.delimiter, attributes: typingAttributes))
                }
                cursor = NSMaxRange(outer)
            }
            result.append(literal(NSRange(location: cursor, length: NSMaxRange(range) - cursor), clippedTo: clip))
            return result
        }

        let before = NSRange(location: format.range.location, length: selection.location - format.range.location)
        let after = NSRange(location: NSMaxRange(selection), length: NSMaxRange(format.range) - NSMaxRange(selection))
        var result = body(format.range, clippedTo: before).wrapped(in: format.delimiter, attributes: typingAttributes)
        result.append(body(format.range, clippedTo: selection).wrapped(in: remainingDelimiter, attributes: typingAttributes))
        result.append(body(format.range, clippedTo: after).wrapped(in: format.delimiter, attributes: typingAttributes))
        return (result.text, result.selection ?? NSRange(location: 0, length: 0))
    }

    private struct Fragment {
        var text = NSMutableAttributedString()
        var selection: NSRange?

        mutating func append(_ other: Fragment) {
            if let selected = other.selection {
                let shifted = NSRange(location: text.length + selected.location, length: selected.length)
                selection = selection.map { NSUnionRange($0, shifted) } ?? shifted
            }
            text.append(other.text)
        }

        func wrapped(in delimiter: String, attributes: [NSAttributedString.Key: Any]) -> Fragment {
            guard !delimiter.isEmpty, text.length > 0 else { return self }
            let source = text.string as NSString
            let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
            let first = source.rangeOfCharacter(from: nonWhitespace)
            guard first.location != NSNotFound else { return self }
            let last = source.rangeOfCharacter(from: nonWhitespace, options: .backwards)
            let end = NSMaxRange(last)
            let marker = NSAttributedString(string: delimiter, attributes: attributes)
            let wrapped = NSMutableAttributedString(attributedString: text)
            // Keep boundary whitespace outside the new markers so a split does
            // not produce unsupported Markdown such as ** word**.
            wrapped.insert(marker, at: end)
            wrapped.insert(marker, at: first.location)
            let selected = selection.map { range in
                let start = range.location + (range.location >= first.location ? marker.length : 0)
                    + (range.location >= end ? marker.length : 0)
                let finish = NSMaxRange(range) + (NSMaxRange(range) > first.location ? marker.length : 0)
                    + (NSMaxRange(range) > end ? marker.length : 0)
                return NSRange(location: start, length: finish - start)
            }
            return Fragment(text: wrapped, selection: selected)
        }
    }
}
