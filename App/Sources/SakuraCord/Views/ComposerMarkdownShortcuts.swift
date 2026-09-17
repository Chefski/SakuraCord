import AppKit
import MessageRendering

extension ComposerNSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText(),
              let marker = KeyboardShortcutPolicy.markdownMarker(
                  for: event, hasSelection: selectedRange().length > 0
              )
        else { return super.performKeyEquivalent(with: event) }
        // Command-U opens the member list unless text is selected for formatting.
        wrapSelectionInMarkdown(marker)
        return true
    }

    func wrapSelectionInMarkdown(_ marker: String) {
        guard isEditable, !hasMarkedText() else { return }
        let selection = selectedRange()
        let source = string as NSString
        guard selection.length > 0, let textStorage, NSMaxRange(selection) <= source.length else { return }
        breakUndoCoalescing()
        let markerWidth = marker.utf16.count
        let formats = DiscordMarkdown.sourceFormats(string)
        var content = selection
        // Selecting the markers as well as their contents is equivalent to
        // selecting the contents. Peel every supported wrapper, not just one.
        while let format = formats.first(where: {
            !Self.styles(for: $0.delimiter).isEmpty && Self.outerRange(of: $0) == content
        }) {
            content = format.range
        }
        if let enclosing = formats.last(where: {
            Self.styles(for: $0.delimiter).contains(marker)
                && $0.range.location <= content.location
                && NSMaxRange($0.range) >= NSMaxRange(content)
        }) {
            let remaining = String(enclosing.delimiter.dropFirst(marker.count))
            let outer = Self.outerRange(of: enclosing)
            if content.length > 0, content != enclosing.range {
                let edit = ComposerMarkdownSelectionEdit.removing(
                    from: enclosing, keeping: remaining, selection: content,
                    text: textStorage, formats: formats, typingAttributes: plainTypingAttributes
                )
                insertText(edit.text, replacementRange: outer)
                setSelectedRange(NSRange(location: outer.location + edit.selection.location, length: edit.selection.length))
                return
            }
            // Remove just this pair; the other wrappers retain their order.
            let replacement = NSMutableAttributedString(string: remaining, attributes: plainTypingAttributes)
            replacement.append(textStorage.attributedSubstring(from: enclosing.range))
            replacement.append(NSAttributedString(string: remaining, attributes: plainTypingAttributes))
            insertText(replacement, replacementRange: outer)
            setSelectedRange(NSRange(
                location: content.location - enclosing.delimiter.utf16.count + remaining.utf16.count,
                length: content.length
            ))
        } else {
            // Newly applied formatting belongs immediately around the selected
            // content, inside every existing wrapper.
            let replacement = NSMutableAttributedString(string: marker, attributes: plainTypingAttributes)
            replacement.append(textStorage.attributedSubstring(from: content))
            replacement.append(NSAttributedString(string: marker, attributes: plainTypingAttributes))
            insertText(replacement, replacementRange: content)
            setSelectedRange(NSRange(location: content.location + markerWidth, length: content.length))
        }
    }

    private static func outerRange(of format: DiscordMarkdown.SourceFormat) -> NSRange {
        let width = format.delimiter.utf16.count
        return NSRange(location: format.range.location - width, length: format.range.length + 2 * width)
    }

    private static func styles(for delimiter: String) -> Set<String> {
        switch delimiter {
        case "***": ["**", "*"]
        case "___": ["__", "*"]
        case "_": ["*"]
        case "**", "*", "__": [delimiter]
        default: []
        }
    }
}
