import AppKit
@testable import SakuraCord
import Testing

@MainActor @Test(arguments: [CGFloat(80), 180, 320], [CGFloat(11), 15, 24, 36])
func `concealing spoiler attachments preserves layout and removes their visible payload`(width: CGFloat, fontSize: CGFloat) throws {
    let source = "||[hidden link](https://example.com) 😀 <:star:456> <@123>|| ||**bold** and *italic*||"
    let value = NSMutableAttributedString(attributedString: RichMessageAttributedText.make(
        source: source, emojiSize: fontSize + 3, baseFontSize: fontSize, mentionPresentations: [:]
    ))
    var originalAttachments: [(NSRange, NSTextAttachment)] = []
    value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { raw, range, _ in
        if let attachment = raw as? NSTextAttachment { originalAttachments.append((range, attachment)) }
    }
    #expect(originalAttachments.count == 2)
    func layout(_ text: NSAttributedString) throws -> [CGRect] {
        let view = RichMessageNSTextView(frame: CGRect(x: 0, y: 0, width: width, height: 1_000))
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = view.bounds.size
        view.textStorage?.setAttributedString(text)
        let manager = try #require(view.layoutManager); let container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        var result: [CGRect] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, used, _, _, _ in
            result.append(rect); result.append(used)
        }
        return result
    }
    let originalLayout = try layout(value)
    RichMessageAttributedText.concealSpoilers(in: value)
    #expect(try layout(value) == originalLayout)
    for (range, original) in originalAttachments {
        let replacement = try #require(value.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment)
        #expect(replacement !== original)
        #expect(replacement.bounds == original.bounds)
        #expect(!(replacement is MentionTextAttachment))
        #expect(value.attribute(.link, at: range.location, effectiveRange: nil) == nil)
        let image = try #require(replacement.image)
        #expect(image !== original.image)
        let bitmap = NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        var isTransparent = true
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide where bitmap.colorAt(x: x, y: y)?.alphaComponent != 0 {
                isTransparent = false
            }
        }
        #expect(isTransparent)
    }
}
