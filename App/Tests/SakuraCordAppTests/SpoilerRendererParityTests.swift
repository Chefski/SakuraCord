import AppKit
import CoreText
@testable import SakuraCord
import Testing

@MainActor @Test(arguments: [CGFloat(80), 180, 320], [CGFloat(11), 15, 24, 36])
func `native and selectable spoiler covers agree for mixed formatted content`(width: CGFloat, fontSize: CGFloat) throws {
    let sources = [
        "||first cover||||second cover||",
        "||line above||\n||line below||\n||third line||",
        "||A longer spoiler wraps onto several consecutive lines beside another spoiler.|| ||next||",
        "||[hidden link](https://example.com) 😀 <:star:456>|| ||**bold** and *italic*||"
    ]
    for source in sources {
        let bounds = CGRect(x: 0, y: 0, width: width, height: 1_000)
        let prepared = RichMessageAttributedText.prepare(source: source)
        let native = NativeTimelineCoreText.make(prepared: prepared, emojiSize: fontSize + 3, baseFontSize: fontSize, mentionPresentations: [:])
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(native), CFRange(location: 0, length: 0), CGPath(rect: bounds, transform: nil), nil)
        let nativeRects = NativeTimelineTextSpoilers.ranges(in: native).flatMap {
            NativeTimelineTextSpoilerGeometry.rects(in: frame, outerFrame: bounds, range: $0)
        }
        let selectable = NSMutableAttributedString(attributedString: RichMessageAttributedText.make(prepared: prepared, emojiSize: fontSize + 3, baseFontSize: fontSize, mentionPresentations: [:]))
        RichMessageAttributedText.concealSpoilers(in: selectable)
        let view = RichMessageNSTextView(frame: bounds)
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = bounds.size
        view.textStorage?.setAttributedString(selectable)
        let selectableRects = SelectableTextSpoilerGeometry.rects(in: view)
        #expect(nativeRects.count == selectableRects.count, "\(source): \(nativeRects) / \(selectableRects)")
        for (nativeRect, selectableRect) in zip(nativeRects, selectableRects) {
            #expect(abs(nativeRect.minX - selectableRect.minX) < 0.01, "\(source)")
            #expect(abs(nativeRect.minY - selectableRect.minY) < 0.01, "\(source): \(nativeRect) / \(selectableRect)")
            #expect(abs(nativeRect.width - selectableRect.width) < 0.01, "\(source)")
            #expect(abs(nativeRect.height - selectableRect.height) < 0.01, "\(source): \(nativeRect) / \(selectableRect)")
        }
    }
}
