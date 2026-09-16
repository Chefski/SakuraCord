import AppKit

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
        let selection = selectedRange()
        let source = string as NSString
        guard let textStorage, NSMaxRange(selection) <= source.length else { return }
        let content = source.substring(with: selection)
        let markerLength = (marker as NSString).length
        if content.hasPrefix(marker), content.hasSuffix(marker), selection.length >= markerLength * 2 {
            let innerRange = NSRange(location: selection.location + markerLength, length: selection.length - markerLength * 2)
            insertText(textStorage.attributedSubstring(from: innerRange), replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location, length: innerRange.length))
        } else if selection.location >= markerLength,
                  NSMaxRange(selection) + markerLength <= source.length,
                  source.substring(with: NSRange(location: selection.location - markerLength, length: markerLength)) == marker,
                  source.substring(with: NSRange(location: NSMaxRange(selection), length: markerLength)) == marker {
            let outerRange = NSRange(location: selection.location - markerLength, length: selection.length + markerLength * 2)
            insertText(textStorage.attributedSubstring(from: selection), replacementRange: outerRange)
            setSelectedRange(NSRange(location: outerRange.location, length: selection.length))
        } else {
            let wrapped = NSMutableAttributedString(string: marker, attributes: plainTypingAttributes)
            wrapped.append(textStorage.attributedSubstring(from: selection))
            wrapped.append(NSAttributedString(string: marker, attributes: plainTypingAttributes))
            insertText(wrapped, replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + markerLength, length: selection.length))
        }
    }
}
