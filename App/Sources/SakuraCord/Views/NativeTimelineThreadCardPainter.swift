import AppKit
import SakuraCordModels

@MainActor
extension NativeTimelineThreadCard {
    enum Interaction {
        case idle, hovered, pressed

        init(isHovered: Bool, isPressed: Bool) {
            self = isHovered ? (isPressed ? .pressed : .hovered) : .idle
        }
    }

    static var cornerRadius: CGFloat { InterfaceScale.metric(10) }
    static var horizontalPadding: CGFloat { InterfaceScale.metric(12) }
    /// Below this width the activity time gives way to the message preview.
    static var minimumWidthForActivity: CGFloat { InterfaceScale.metric(280) }
    private static var chevronNudge: CGFloat { InterfaceScale.metric(2) }

    static func glyphName(for thread: MessageThreadSummary) -> String {
        if thread.isLocked { return "lock.fill" }
        if thread.isArchived { return "archivebox.fill" }
        return SakuraCordSystemSymbol.thread
    }

    static var nameFont: NSFont { .interfaceSystemFont(ofSize: 13, weight: .semibold) }
    static var countFont: NSFont { .interfaceSystemFont(ofSize: 12, weight: .semibold) }
    static var activityFont: NSFont { .interfaceSystemFont(ofSize: 11) }

    /// Measured widths, so a hover redraw does not typeset the strings again.
    private static let widthCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 512
        return cache
    }()

    static func width(of value: String, font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(value)" as NSString
        if let cached = widthCache.object(forKey: key) { return CGFloat(cached.doubleValue) }
        let width = NativeTimelineReplyMetrics.textWidth(value, font: font)
        widthCache.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }

    /// Where each part of the card sits, in the same space as `frame`.
    struct Geometry {
        let glyphFrame: CGRect
        let nameFrame: CGRect
        let countText: String?
        let countFrame: CGRect
        let chevronFrame: CGRect
        let activityFrame: CGRect?
        let previewFrame: CGRect
    }

    static func geometry(
        thread: MessageThreadSummary,
        activity: String,
        in frame: CGRect,
        inset: CGFloat,
        isHovered: Bool
    ) -> Geometry {
        let rowHeight = InterfaceScale.metric(18)
        let row1Y = frame.minY + InterfaceScale.metric(7)
        let left = frame.minX + inset
        let right = frame.maxX - inset
        let glyphSize = InterfaceScale.metric(14)
        let glyphFrame = CGRect(
            x: left, y: row1Y + (rowHeight - glyphSize) / 2, width: glyphSize, height: glyphSize
        )
        let chevronWidth = InterfaceScale.metric(8)
        let chevronHeight = InterfaceScale.metric(12)
        let restingChevronX = right - chevronWidth - chevronNudge
        let chevronFrame = CGRect(
            x: restingChevronX + (isHovered ? chevronNudge : 0),
            y: row1Y + (rowHeight - chevronHeight) / 2,
            width: chevronWidth,
            height: chevronHeight
        )
        let countRight = restingChevronX - InterfaceScale.metric(4)
        let nameX = glyphFrame.maxX + InterfaceScale.metric(6)
        let room = max(0, countRight - nameX)
        let gap = InterfaceScale.metric(10)
        let nameWidth = width(of: thread.name, font: nameFont)

        // The count keeps its full label while the name still gets a useful
        // share; otherwise it shrinks to the number, then yields entirely.
        var countText: String?
        var countWidth: CGFloat = 0
        for (candidate, share) in [
            (NativeTimelineThreadCard.countText(thread), 0.5),
            (NativeTimelineThreadCard.compactCountText(thread), 0.4),
        ] {
            guard let candidate else { continue }
            let candidateWidth = width(of: candidate, font: countFont)
            if room - candidateWidth - gap >= min(nameWidth, room * share) {
                countText = candidate
                countWidth = candidateWidth
                break
            }
        }
        let nameLimit = max(0, room - (countText == nil ? 0 : countWidth + gap))
        let nameFrame = CGRect(
            x: nameX, y: row1Y, width: min(nameWidth, nameLimit), height: rowHeight
        )
        let countFrame = CGRect(
            x: countRight - countWidth, y: row1Y, width: countWidth, height: rowHeight
        )

        let row2 = CGRect(
            x: left,
            y: frame.minY + InterfaceScale.metric(28),
            width: max(0, right - left),
            height: InterfaceScale.metric(20)
        )
        var activityFrame: CGRect?
        var previewWidth = row2.width
        if frame.width >= minimumWidthForActivity {
            let activityWidth = width(of: activity, font: activityFont)
            activityFrame = CGRect(
                x: row2.maxX - activityWidth, y: row2.minY + 1, width: activityWidth,
                height: InterfaceScale.metric(18)
            )
            previewWidth = max(0, row2.width - activityWidth - InterfaceScale.metric(8))
        }
        return Geometry(
            glyphFrame: glyphFrame,
            nameFrame: nameFrame,
            countText: countText,
            countFrame: countFrame,
            chevronFrame: chevronFrame,
            activityFrame: activityFrame,
            previewFrame: CGRect(x: row2.minX, y: row2.minY, width: previewWidth, height: row2.height)
        )
    }

    static func emptyText(for thread: MessageThreadSummary) -> String {
        thread.isArchived || thread.messageCount > 0
            ? "There are no recent messages in this thread."
            : "There are no messages in this thread yet."
    }
}

extension NativeTimelineRowPainter {
    /// Discord's thread card: the name and message count, then the thread's
    /// latest message or an empty state. It is a button, so it reacts to the
    /// pointer; inside a bubble it tints the bubble section instead of
    /// drawing its own surface.
    static func threadCard(
        _ thread: MessageThreadSummary,
        preview: Message?,
        message: Message,
        model: AppModel?,
        in frame: CGRect,
        bubbleRegion: NativeTimelineBubbleRegion? = nil,
        interaction: NativeTimelineThreadCard.Interaction = .idle
    ) {
        threadCardSurface(in: frame, bubbleRegion: bubbleRegion, interaction: interaction)
        let isOutgoing = bubbleRegion?.isOutgoing == true
        let foreground = NativeTimelineBubbleDrawing.foregroundColor(for: bubbleRegion)
        let secondary = NativeTimelineBubbleDrawing.secondaryForegroundColor(for: bubbleRegion)
        let isDormant = thread.isArchived || thread.isLocked
        let activity = NativeTimelineThreadCard.activityText(
            thread.lastMessageID?.createdAt ?? thread.createdAt ?? thread.id.createdAt
        )
        let layout = NativeTimelineThreadCard.geometry(
            thread: thread,
            activity: activity,
            in: frame,
            inset: bubbleRegion == nil ? NativeTimelineThreadCard.horizontalPadding : 0,
            isHovered: interaction != .idle
        )
        let accent: NSColor = isOutgoing ? .white : isDormant ? secondary : .sakuraCordAccentColor

        systemSymbol(
            NativeTimelineThreadCard.glyphName(for: thread),
            in: layout.glyphFrame,
            color: secondary,
            inset: 0,
            weight: .medium
        )
        text(
            thread.name,
            in: layout.nameFrame,
            font: NativeTimelineThreadCard.nameFont,
            color: isDormant && !isOutgoing ? secondary : foreground
        )
        if let countText = layout.countText {
            text(
                countText,
                in: layout.countFrame,
                font: NativeTimelineThreadCard.countFont,
                color: accent,
                alignment: .right
            )
        }
        systemSymbol(
            "chevron.right",
            in: layout.chevronFrame,
            color: interaction == .idle ? accent.withAlphaComponent(0.7) : accent,
            inset: 0,
            weight: .semibold
        )

        if let activityFrame = layout.activityFrame {
            text(
                activity,
                in: activityFrame,
                font: NativeTimelineThreadCard.activityFont,
                color: isOutgoing ? secondary : .tertiaryLabelColor
            )
        }
        guard !thread.isArchived, thread.messageCount > 0, let preview else {
            text(
                NativeTimelineThreadCard.emptyText(for: thread),
                in: layout.previewFrame,
                font: NativeTimelineReplyMetrics.summaryFont,
                color: secondary
            )
            return
        }
        replyPreviewLine(
            MessageReplyPreview.presenting(preview),
            frame: layout.previewFrame,
            avatarFrame: NativeTimelineAvatarPresentation.replyAvatarFrame(in: layout.previewFrame),
            trailingInset: 0,
            showsReplyMention: false,
            message: message,
            model: model,
            foregroundColor: isOutgoing ? foreground : nil
        )
    }

    private static func threadCardSurface(
        in frame: CGRect,
        bubbleRegion: NativeTimelineBubbleRegion?,
        interaction: NativeTimelineThreadCard.Interaction
    ) {
        let overlayAlpha: CGFloat = switch interaction {
        case .idle: 0
        case .hovered: 0.07
        case .pressed: 0.12
        }
        if let bubbleRegion {
            bubbleIntegratedSection(
                frame, bubbleRegion: bubbleRegion, accentColor: nil,
                drawsTopSeparator: frame.minY - bubbleRegion.frame.minY > 8.5, drawsNeutralRail: false
            )
            guard overlayAlpha > 0 else { return }
            NSGraphicsContext.saveGraphicsState()
            NativeTimelineBubbleDrawing.bodyPath(for: bubbleRegion).addClip()
            NativeTimelineBubbleDrawing.foregroundColor(for: bubbleRegion)
                .withAlphaComponent(overlayAlpha).setFill()
            frame.fill()
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let radius = NativeTimelineThreadCard.cornerRadius
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        if overlayAlpha > 0 {
            NSColor.labelColor.withAlphaComponent(overlayAlpha).setFill()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        }
        let borderAlpha: CGFloat = switch interaction {
        case .idle: 0.10
        case .hovered: 0.22
        case .pressed: 0.28
        }
        NSColor.labelColor.withAlphaComponent(borderAlpha).setStroke()
        let border = NSBezierPath(
            roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5
        )
        border.lineWidth = 1
        border.stroke()
    }
}
