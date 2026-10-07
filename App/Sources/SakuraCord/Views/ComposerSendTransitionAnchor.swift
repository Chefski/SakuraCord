import AppKit
import SakuraCordModels

/// Locates the composer text so a sent message can leave the field the way
/// an iMessage bubble does. The timeline owns the animation; the composer
/// only describes where the message starts.
@MainActor
final class ComposerSendTransitionAnchor {
    /// The field's leading padding before its text, matching a bubble's.
    static let fieldLeadingPadding: CGFloat = 11
    static let fieldTrailingPadding: CGFloat = 4

    weak var textView: NSTextView?

    func source(
        channelID: ChannelID,
        content: String
    ) -> NativeTimelineSendTransitionSource? {
        guard let textView,
              let window = textView.window
        else { return nil }
        let textArea = textView.enclosingScrollView ?? textView
        let textFrame = textArea.convert(textArea.bounds, to: nil)
        guard textFrame.width > 1, textFrame.height > 1 else { return nil }
        // The bubble starts as the text's part of the field, leaving the
        // field's accessory buttons uncovered.
        let height = max(textFrame.height, ChatChromeMetrics.composerControlHeight)
        let fieldFrame = CGRect(
            x: textFrame.minX - Self.fieldLeadingPadding,
            y: textFrame.midY - height / 2,
            width: textFrame.width + Self.fieldLeadingPadding + Self.fieldTrailingPadding,
            height: height
        )
        return NativeTimelineSendTransitionSource(
            channelID: channelID,
            content: content,
            capturedAt: ProcessInfo.processInfo.systemUptime,
            window: window,
            fieldFrame: fieldFrame,
            text: textSnapshot()
        )
    }

    /// Draws the laid-out glyphs rather than caching the view, which would
    /// also capture the insertion point and marked-text decorations.
    private func textSnapshot() -> NativeTimelineSendTransitionSource.Text? {
        guard let textView,
              let window = textView.window,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return nil }
        let origin = textView.textContainerOrigin
        let usedRect = layoutManager.usedRect(for: textContainer)
            .offsetBy(dx: origin.x, dy: origin.y)
        // Leave room for descenders, emoji and mention pills that overhang
        // their line fragments.
        let drawRect = usedRect.insetBy(dx: -4, dy: -4)
            .intersection(textView.visibleRect)
            .integral
        guard !drawRect.isEmpty else { return nil }
        let firstLine = layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: nil
        )
        let glyphLocation = layoutManager.location(forGlyphAt: glyphRange.location)
        let baseline = CGPoint(
            x: origin.x + firstLine.minX + glyphLocation.x,
            y: origin.y + firstLine.minY + glyphLocation.y
        )
        let scale = max(1, window.backingScaleFactor)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(drawRect.width * scale))),
            pixelsHigh: max(1, Int(ceil(drawRect.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: representation)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: drawRect.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -drawRect.minX, y: -drawRect.minY)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        }
        NSGraphicsContext.restoreGraphicsState()
        representation.size = drawRect.size
        let image = NSImage(size: drawRect.size)
        image.addRepresentation(representation)
        return NativeTimelineSendTransitionSource.Text(
            image: image,
            frame: textView.convert(drawRect, to: nil),
            baseline: textView.convert(baseline, to: nil)
        )
    }
}
