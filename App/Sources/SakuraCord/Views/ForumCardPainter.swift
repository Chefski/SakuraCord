import AppKit
import CoreText
import SakuraCordModels

/// Interactive regions inside a card, in card coordinates. The painter and
/// the board's pointer handling share them, so hit targets always match what
/// is drawn.
struct ForumCardRegions: Equatable {
    var statusRowFrame: CGRect?
    var titleFrame: CGRect = .zero
    var excerptFrame: CGRect?
    var thumbnailFrame: CGRect?
    var heroFrame: CGRect?
    var reactionRegionFrame: CGRect?
    var timestampFrame: CGRect?
    var countFrame: CGRect?
    var footerFrame: CGRect = .zero
    /// Rounded bars the card's loading shimmer is masked to.
    var skeletonFrames: [CGRect] = []
}

/// Live interaction state that changes how a card draws.
struct ForumCardInteraction: Equatable {
    var isReactionHovered = false
    var isRetryHovered = false
}

/// Draws forum board cards with Core Graphics and Core Text into the current
/// flipped graphics context. Card size never depends on what is drawn here.
@MainActor
enum ForumCardPainter {
    private static var tagFont: NSFont { .interfaceSystemFont(ofSize: 12, weight: .semibold) }
    private static var footerFont: NSFont { .interfaceSystemFont(ofSize: 12) }
    private static var footerEmphasisFont: NSFont { .interfaceSystemFont(ofSize: 12, weight: .semibold) }
    private static var captionFont: NSFont { .interfaceSystemFont(ofSize: 12) }
    private static var badgeFont: NSFont { .interfaceSystemFont(ofSize: 10, weight: .bold) }
    static let newBadgeFill = NSColor(srgbRed: 0xC9 / 255, green: 0xD2 / 255, blue: 1, alpha: 1)
    static let newBadgeText = NSColor(srgbRed: 0x58 / 255, green: 0x65 / 255, blue: 0xF2 / 255, alpha: 1)

    // MARK: Regions

    static func regions(
        for presentation: ForumCardPresentation?,
        mode: ForumLayout,
        size: CGSize,
        titleLines: Int,
        metrics: ForumBoardMetrics
    ) -> ForumCardRegions {
        mode == .gallery
            ? galleryRegions(for: presentation, size: size, metrics: metrics)
            : listRegions(for: presentation, size: size, titleLines: titleLines, metrics: metrics)
    }

    private static func listRegions(
        for presentation: ForumCardPresentation?,
        size: CGSize,
        titleLines: Int,
        metrics: ForumBoardMetrics
    ) -> ForumCardRegions {
        var regions = ForumCardRegions()
        let padding = metrics.cardPadding
        let hasThumbnail = presentation?.thumbnail != nil
        let textMaxX = size.width - padding - (hasThumbnail ? metrics.thumbnailSize + metrics.thumbnailSpacing : 0)
        var cursorY = padding
        let hasStatusRow = presentation?.geometry.hasStatusRow ?? true
        if hasStatusRow {
            regions.statusRowFrame = CGRect(x: padding, y: cursorY, width: textMaxX - padding, height: metrics.statusRowHeight)
            cursorY += metrics.statusRowHeight + metrics.statusRowSpacing
        }
        let lines = presentation == nil ? 1 : titleLines
        regions.titleFrame = CGRect(
            x: padding, y: cursorY, width: textMaxX - padding,
            height: CGFloat(lines) * metrics.titleLineHeight
        )
        cursorY = regions.titleFrame.maxY + metrics.titleSpacing
        let excerptFrame = CGRect(
            x: padding, y: cursorY, width: textMaxX - padding,
            height: CGFloat(metrics.excerptLines) * metrics.excerptLineHeight
        )
        regions.excerptFrame = excerptFrame
        cursorY = excerptFrame.maxY + metrics.footerSpacing
        regions.footerFrame = CGRect(x: padding, y: cursorY, width: size.width - padding * 2, height: metrics.footerHeight)
        if hasThumbnail {
            regions.thumbnailFrame = CGRect(
                x: size.width - padding - metrics.thumbnailSize,
                y: padding,
                width: metrics.thumbnailSize,
                height: metrics.thumbnailSize
            )
        }
        guard let presentation else {
            regions.skeletonFrames = placeholderListBars(regions: regions, metrics: metrics)
            return regions
        }
        layoutFooter(presentation, in: &regions, alignsReactionTrailing: false)
        if presentation.excerpt == .pending {
            regions.skeletonFrames = excerptBars(in: excerptFrame, metrics: metrics)
        }
        return regions
    }

    private static func galleryRegions(
        for presentation: ForumCardPresentation?,
        size: CGSize,
        metrics: ForumBoardMetrics
    ) -> ForumCardRegions {
        var regions = ForumCardRegions()
        let padding = metrics.cardPadding
        let innerWidth = size.width - padding * 2
        regions.statusRowFrame = CGRect(x: padding, y: padding, width: innerWidth, height: metrics.galleryHeaderHeight)
        var cursorY = padding + metrics.galleryHeaderHeight + metrics.statusRowSpacing
        regions.titleFrame = CGRect(x: padding, y: cursorY, width: innerWidth, height: metrics.galleryTitleHeight)
        cursorY = regions.titleFrame.maxY + metrics.statusRowSpacing
        regions.heroFrame = CGRect(x: padding, y: cursorY, width: innerWidth, height: metrics.galleryHeroHeight)
        regions.footerFrame = CGRect(
            x: padding,
            y: size.height - padding - metrics.footerHeight,
            width: innerWidth,
            height: metrics.footerHeight
        )
        guard let presentation else {
            let title = regions.titleFrame
            regions.skeletonFrames = [
                CGRect(x: padding, y: padding + 3, width: innerWidth * 0.42, height: metrics.galleryHeaderHeight - 6),
                CGRect(x: title.minX, y: title.minY + 5, width: title.width * 0.78, height: metrics.titleLineHeight - 10),
                regions.heroFrame ?? .zero,
                CGRect(x: padding, y: regions.footerFrame.minY + 6, width: InterfaceScale.metric(54), height: metrics.footerHeight - 12),
            ]
            return regions
        }
        layoutFooter(presentation, in: &regions, alignsReactionTrailing: true)
        if presentation.hero == .pending, let hero = regions.heroFrame {
            regions.skeletonFrames = [hero]
        }
        return regions
    }

    private static func layoutFooter(
        _ presentation: ForumCardPresentation,
        in regions: inout ForumCardRegions,
        alignsReactionTrailing: Bool
    ) {
        let footer = regions.footerFrame
        let spacing = InterfaceScale.metric(12)
        var cursorX = footer.minX
        if let summary = presentation.reaction {
            let size = NativeTimelineRowLayout.reactionSize(summary.reaction)
            let originX = alignsReactionTrailing ? footer.maxX - size.width : cursorX
            regions.reactionRegionFrame = CGRect(x: originX, y: footer.midY - size.height / 2, width: size.width, height: size.height)
            if !alignsReactionTrailing { cursorX += size.width + spacing }
        }
        let countWidth = countContentWidth(presentation)
        regions.countFrame = CGRect(x: cursorX, y: footer.minY, width: countWidth, height: footer.height)
        cursorX += countWidth + spacing
        if !alignsReactionTrailing {
            let text = ForumTimestampPresentation.roundedRelativeText(for: presentation.lastActivityAt, relativeTo: .now)
            let width = ceil(NativeTimelineRowPainter.measuredTextWidth(text, font: footerFont)) + 2
            regions.timestampFrame = CGRect(x: cursorX, y: footer.minY, width: width, height: footer.height)
        }
    }

    private static func excerptBars(in frame: CGRect, metrics: ForumBoardMetrics) -> [CGRect] {
        let barHeight = round(metrics.excerptLineHeight * 0.5)
        return (0 ..< metrics.excerptLines).map { line in
            let lineY = frame.minY + CGFloat(line) * metrics.excerptLineHeight
            let fraction: CGFloat = line == metrics.excerptLines - 1 ? 0.58 : 0.92
            return CGRect(
                x: frame.minX,
                y: lineY + (metrics.excerptLineHeight - barHeight) / 2,
                width: floor(frame.width * fraction),
                height: barHeight
            )
        }
    }

    private static func placeholderListBars(regions: ForumCardRegions, metrics: ForumBoardMetrics) -> [CGRect] {
        var bars: [CGRect] = []
        if let status = regions.statusRowFrame {
            bars.append(CGRect(x: status.minX, y: status.minY, width: InterfaceScale.metric(74), height: status.height))
            bars.append(CGRect(x: status.minX + InterfaceScale.metric(82), y: status.minY, width: InterfaceScale.metric(58), height: status.height))
        }
        let title = regions.titleFrame
        bars.append(CGRect(
            x: title.minX,
            y: title.minY + metrics.titleLineHeight * 0.2,
            width: floor(title.width * 0.64),
            height: round(metrics.titleLineHeight * 0.6)
        ))
        if let excerpt = regions.excerptFrame {
            bars += excerptBars(in: excerpt, metrics: metrics)
        }
        let footer = regions.footerFrame
        bars.append(CGRect(x: footer.minX, y: footer.minY, width: InterfaceScale.metric(58), height: footer.height))
        bars.append(CGRect(
            x: footer.minX + InterfaceScale.metric(70),
            y: footer.midY - InterfaceScale.metric(6),
            width: InterfaceScale.metric(90),
            height: InterfaceScale.metric(12)
        ))
        return bars
    }

    private static func countContentWidth(_ presentation: ForumCardPresentation) -> CGFloat {
        let iconWidth = InterfaceScale.metric(14) + InterfaceScale.metric(4)
        var width = iconWidth + NativeTimelineRowPainter.measuredTextWidth(
            presentation.messageCount.formatted(), font: footerFont
        )
        if presentation.unreadCount > 0 {
            width += InterfaceScale.metric(4) + NativeTimelineRowPainter.measuredTextWidth(
                "(\(presentation.unreadCount.formatted()) New)", font: footerEmphasisFont
            )
        }
        return ceil(width) + 1
    }

    // MARK: Drawing

    struct DrawInput {
        let presentation: ForumCardPresentation
        let mode: ForumLayout
        let regions: ForumCardRegions
        let titleLines: Int
        let excerpt: ForumPostPreviewTextRenderer?
        let interaction: ForumCardInteraction
        let model: AppModel?
        let metrics: ForumBoardMetrics
    }

    static func draw(_ input: DrawInput) {
        let presentation = input.presentation
        let regions = input.regions
        let excerpt = input.excerpt
        let interaction = input.interaction
        let model = input.model
        let metrics = input.metrics
        let titleLines = input.titleLines
        let mode = input.mode
        if mode == .gallery {
            drawGalleryHeader(presentation, in: regions.statusRowFrame ?? .zero)
            drawTitle(presentation, in: regions.titleFrame, maximumLines: 2, metrics: metrics)
            if let hero = regions.heroFrame {
                drawHero(presentation, in: hero, excerpt: excerpt)
            }
            drawFooter(presentation, regions: regions, interaction: interaction, model: model)
        } else {
            if let status = regions.statusRowFrame {
                drawStatusRow(presentation, in: status)
            }
            drawTitle(presentation, in: regions.titleFrame, maximumLines: titleLines, metrics: metrics)
            if let excerptFrame = regions.excerptFrame {
                drawExcerpt(presentation, in: excerptFrame, renderer: excerpt, metrics: metrics)
            }
            if let thumbnail = presentation.thumbnail, let frame = regions.thumbnailFrame {
                drawMedia(thumbnail, in: frame, cornerRadius: InterfaceScale.metric(11), isCompact: true)
            }
            drawFooter(presentation, regions: regions, interaction: interaction, model: model)
        }
    }

    /// Skeleton bars, drawn beneath the shimmer layer that animates over them.
    static func drawSkeleton(_ frames: [CGRect]) {
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        for frame in frames {
            let radius = min(InterfaceScale.metric(7), frame.height / 2)
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        }
    }

    private static func drawStatusRow(_ presentation: ForumCardPresentation, in frame: CGRect) {
        var cursorX = frame.minX
        let iconSize = InterfaceScale.metric(14)
        for (shown, symbol) in [(presentation.isPinned, "pin.fill"), (presentation.isLocked, "lock.fill")] where shown {
            NativeTimelineRowPainter.systemSymbol(
                symbol,
                in: CGRect(x: cursorX, y: frame.midY - iconSize / 2, width: iconSize, height: iconSize),
                color: .secondaryLabelColor,
                inset: 0,
                weight: .semibold
            )
            cursorX += iconSize + InterfaceScale.metric(7)
        }
        drawTags(presentation.tags, in: CGRect(x: cursorX, y: frame.minY, width: frame.maxX - cursorX, height: frame.height), style: .standard)
    }

    enum TagStyle {
        case standard
        case overMedia
    }

    /// Fits as many tag chips as the width allows, ending with "+N" for the
    /// rest. Chips never wrap, so the status row height stays fixed.
    static func drawTags(_ tags: [ForumCardPresentation.Tag], in frame: CGRect, style: TagStyle, maximumVisible: Int = 5) {
        guard !tags.isEmpty, frame.width > 0 else { return }
        let spacing = InterfaceScale.metric(6)
        let widths = tags.map { tagWidth($0) }
        var visible = min(tags.count, maximumVisible)
        func overflowWidth(_ hidden: Int) -> CGFloat {
            hidden > 0 ? chipWidth(text: "+\(hidden)", hasEmoji: false) + spacing : 0
        }
        while visible > 0 {
            let total = widths.prefix(visible).reduce(0, +) + CGFloat(visible - 1) * spacing
                + overflowWidth(tags.count - visible)
            if total <= frame.width { break }
            visible -= 1
        }
        var cursorX = frame.minX
        for (tag, width) in zip(tags.prefix(visible), widths) {
            drawChip(text: tag.name, emoji: tag.emoji, frame: CGRect(x: cursorX, y: frame.minY, width: width, height: frame.height), style: style)
            cursorX += width + spacing
        }
        let hidden = tags.count - visible
        if hidden > 0 {
            let text = "+\(hidden)"
            let width = min(chipWidth(text: text, hasEmoji: false), frame.maxX - cursorX)
            guard width > 0 else { return }
            drawChip(text: text, emoji: nil, frame: CGRect(x: cursorX, y: frame.minY, width: width, height: frame.height), style: style)
        }
    }

    private static func tagWidth(_ tag: ForumCardPresentation.Tag) -> CGFloat {
        chipWidth(text: tag.name, hasEmoji: tag.emoji != nil)
    }

    private static func chipWidth(text: String, hasEmoji: Bool) -> CGFloat {
        let padding = InterfaceScale.metric(9)
        let emoji = hasEmoji ? InterfaceScale.metric(14) + InterfaceScale.metric(4) : 0
        let textWidth = min(NativeTimelineRowPainter.measuredTextWidth(text, font: tagFont), InterfaceScale.metric(160))
        return ceil(padding * 2 + emoji + textWidth)
    }

    private static func drawChip(
        text: String,
        emoji: ForumTagEmojiPresentation?,
        frame: CGRect,
        style: TagStyle
    ) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
        switch style {
        case .standard:
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            shape.fill()
            NSColor.labelColor.withAlphaComponent(0.1).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        case .overMedia:
            NSColor.black.withAlphaComponent(0.58).setFill()
            shape.fill()
        }
        let padding = InterfaceScale.metric(9)
        var cursorX = frame.minX + padding
        if let emoji {
            let size = InterfaceScale.metric(14)
            drawEmoji(emoji, in: CGRect(x: cursorX, y: frame.midY - size / 2, width: size, height: size))
            cursorX += size + InterfaceScale.metric(4)
        }
        let color: NSColor = style == .overMedia ? .white : .labelColor
        let lineHeight = ForumBoardMetrics.lineHeight(of: tagFont)
        NativeTimelineRowPainter.text(
            text,
            in: CGRect(x: cursorX, y: frame.midY - lineHeight / 2, width: max(0, frame.maxX - padding - cursorX), height: lineHeight),
            font: tagFont,
            color: color
        )
    }

    static func drawEmoji(_ emoji: ForumTagEmojiPresentation, in frame: CGRect) {
        switch emoji {
        case let .unicode(value):
            NativeTimelineRowPainter.drawImage(
                ComponentUnicodeEmojiRenderer.image(for: value),
                in: frame,
                cornerRadius: 0,
                fillsFrame: false
            )
        case .custom:
            if let key = emoji.mediaKey, let image = NativeTimelineRowPainter.mediaImage(for: key) {
                NativeTimelineRowPainter.drawImage(image, in: frame, cornerRadius: 0, fillsFrame: false)
            } else {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                NSBezierPath(ovalIn: frame.insetBy(dx: 1, dy: 1)).fill()
            }
        }
    }

    // MARK: Title

    private static func drawTitle(
        _ presentation: ForumCardPresentation,
        in frame: CGRect,
        maximumLines: Int,
        metrics: ForumBoardMetrics
    ) {
        let color: NSColor = presentation.isEmphasized ? .labelColor : .secondaryLabelColor
        let badgeSize = newBadgeSize()
        let badgeReserve = presentation.isNew ? badgeSize.width + InterfaceScale.metric(8) : 0
        let lastLineEnd = drawLines(
            presentation.title,
            font: metrics.titleFont,
            color: color,
            in: frame,
            lineHeight: metrics.titleLineHeight,
            maximumLines: max(1, maximumLines),
            lastLineReserve: badgeReserve
        )
        guard presentation.isNew else { return }
        let badgeFrame = CGRect(
            x: lastLineEnd.x + InterfaceScale.metric(8),
            y: lastLineEnd.y + (metrics.titleLineHeight - badgeSize.height) / 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
        newBadgeFill.setFill()
        NSBezierPath(roundedRect: badgeFrame, xRadius: badgeFrame.height / 2, yRadius: badgeFrame.height / 2).fill()
        let lineHeight = ForumBoardMetrics.lineHeight(of: badgeFont)
        NativeTimelineRowPainter.text(
            "NEW",
            in: CGRect(x: badgeFrame.minX, y: badgeFrame.midY - lineHeight / 2, width: badgeFrame.width, height: lineHeight),
            font: badgeFont,
            color: newBadgeText,
            alignment: .center,
            lineBreakMode: .byClipping
        )
    }

    static func newBadgeSize() -> CGSize {
        CGSize(
            width: ceil(NativeTimelineRowPainter.measuredTextWidth("NEW", font: badgeFont) + InterfaceScale.metric(16)),
            height: InterfaceScale.metric(18)
        )
    }

    /// Breaks text into at most `maximumLines` lines, truncating the last
    /// with an ellipsis, and returns where the last line ends (its top and
    /// trailing edge) so a badge can follow it.
    @discardableResult
    static func drawLines(
        _ text: String,
        font: NSFont,
        color: NSColor,
        in frame: CGRect,
        lineHeight: CGFloat,
        maximumLines: Int,
        lastLineReserve: CGFloat = 0
    ) -> CGPoint {
        guard let context = NSGraphicsContext.current?.cgContext, frame.width > 0 else { return frame.origin }
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = attributed.length
        var location = 0
        var lineIndex = 0
        var end = frame.origin
        let ellipsis = CTLineCreateWithAttributedString(
            NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: color])
        )
        while location < length, lineIndex < maximumLines {
            var isLast = lineIndex == maximumLines - 1
            var width = Double(max(1, frame.width - (isLast ? lastLineReserve : 0)))
            var count = CTTypesetterSuggestLineBreak(typesetter, location, width)
            if count <= 0 { break }
            // A line that ends the text carries the trailing badge too.
            if !isLast, lastLineReserve > 0, location + count >= length {
                width = Double(max(1, frame.width - lastLineReserve))
                count = CTTypesetterSuggestLineBreak(typesetter, location, width)
                if count <= 0 { break }
                isLast = location + count >= length
            }
            var line = CTTypesetterCreateLine(typesetter, CFRange(location: location, length: count))
            if isLast, location + count < length {
                count = length - location
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: location, length: count))
                line = CTLineCreateTruncatedLine(rest, width, .end, ellipsis) ?? line
            }
            let lineY = frame.minY + CGFloat(lineIndex) * lineHeight
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: frame.minX, y: lineY + font.ascender + (lineHeight - (font.ascender - font.descender)) / 2)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            end = CGPoint(x: frame.minX + ceil(lineWidth), y: lineY)
            location += count
            lineIndex += 1
        }
        return end
    }

    // MARK: Excerpt and hero

    private static func drawExcerpt(
        _ presentation: ForumCardPresentation,
        in frame: CGRect,
        renderer: ForumPostPreviewTextRenderer?,
        metrics: ForumBoardMetrics
    ) {
        switch presentation.excerpt {
        case .pending:
            return
        case .empty:
            let text = presentation.thumbnail == nil ? "No message" : "Attachment"
            NativeTimelineRowPainter.text(
                text,
                in: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: metrics.excerptLineHeight),
                font: metrics.excerptFont,
                color: .tertiaryLabelColor
            )
        case .message:
            renderer?.draw(at: frame.origin)
        }
    }

    private static func drawHero(
        _ presentation: ForumCardPresentation,
        in frame: CGRect,
        excerpt: ForumPostPreviewTextRenderer?
    ) {
        let radius = InterfaceScale.metric(12)
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        shape.fill()
        switch presentation.hero {
        case .pending:
            break
        case let .media(media):
            drawMedia(media, in: frame, cornerRadius: radius, isCompact: false)
        case .text:
            excerpt?.draw(at: CGPoint(x: frame.minX + InterfaceScale.metric(16), y: frame.minY + InterfaceScale.metric(14)))
        case .empty:
            let size = InterfaceScale.metric(34)
            NativeTimelineRowPainter.systemSymbol(
                "bubble.left.and.text.bubble.right",
                in: CGRect(x: frame.midX - size / 2, y: frame.midY - size / 2, width: size, height: size),
                color: .tertiaryLabelColor,
                inset: 0,
                weight: .medium
            )
        }
        let chipHeight = InterfaceScale.metric(24)
        let inset = InterfaceScale.metric(10)
        let isOverMedia: Bool = if case .media = presentation.hero { true } else { false }
        drawTags(
            presentation.tags,
            in: CGRect(x: frame.minX + inset, y: frame.maxY - inset - chipHeight, width: frame.width - inset * 2, height: chipHeight),
            style: isOverMedia ? .overMedia : .standard,
            maximumVisible: 3
        )
        NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
    }

    static func drawMedia(
        _ media: ForumCardPresentation.Media,
        in frame: CGRect,
        cornerRadius: CGFloat,
        isCompact: Bool
    ) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        shape.fill()
        switch media {
        case let .image(key):
            if let image = NativeTimelineRowPainter.mediaImage(for: key) {
                NativeTimelineRowPainter.drawImage(image, in: frame, cornerRadius: cornerRadius, fillsFrame: true)
            }
        case let .video(poster, filename):
            if let poster, let image = NativeTimelineRowPainter.mediaImage(for: poster) {
                NativeTimelineRowPainter.drawImage(image, in: frame, cornerRadius: cornerRadius, fillsFrame: true)
                let badge = InterfaceScale.metric(34)
                let badgeFrame = CGRect(x: frame.midX - badge / 2, y: frame.midY - badge / 2, width: badge, height: badge)
                NSColor.black.withAlphaComponent(0.55).setFill()
                NSBezierPath(ovalIn: badgeFrame).fill()
                NativeTimelineRowPainter.systemSymbol("play.fill", in: badgeFrame, color: .white, inset: InterfaceScale.metric(10), weight: .semibold)
            } else if poster == nil {
                drawFileTile(symbol: "play.rectangle.fill", filename: filename, in: frame, isCompact: isCompact)
            }
        case let .audio(filename):
            drawFileTile(symbol: "waveform", filename: filename, in: frame, isCompact: isCompact)
        case let .file(filename):
            drawFileTile(symbol: "doc.fill", filename: filename, in: frame, isCompact: isCompact)
        case .spoiler:
            let size = InterfaceScale.metric(isCompact ? 20 : 26)
            let labelHeight = ForumBoardMetrics.lineHeight(of: badgeFont)
            let total = size + InterfaceScale.metric(6) + labelHeight
            NativeTimelineRowPainter.systemSymbol(
                "eye.slash.fill",
                in: CGRect(x: frame.midX - size / 2, y: frame.midY - total / 2, width: size, height: size),
                color: .secondaryLabelColor,
                inset: 0
            )
            NativeTimelineRowPainter.text(
                "SPOILER",
                in: CGRect(x: frame.minX, y: frame.midY - total / 2 + size + InterfaceScale.metric(6), width: frame.width, height: labelHeight),
                font: badgeFont,
                color: .secondaryLabelColor,
                alignment: .center,
                lineBreakMode: .byClipping
            )
        }
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        border.lineWidth = 1
        border.stroke()
    }

    private static func drawFileTile(symbol: String, filename: String, in frame: CGRect, isCompact: Bool) {
        let size = InterfaceScale.metric(isCompact ? 22 : 30)
        let lineHeight = ForumBoardMetrics.lineHeight(of: captionFont)
        let total = size + InterfaceScale.metric(7) + lineHeight * 2
        let top = frame.midY - total / 2
        NativeTimelineRowPainter.systemSymbol(
            symbol,
            in: CGRect(x: frame.midX - size / 2, y: top, width: size, height: size),
            color: .secondaryLabelColor,
            inset: 0
        )
        let inset = InterfaceScale.metric(8)
        drawLines(
            filename,
            font: captionFont,
            color: .secondaryLabelColor,
            in: CGRect(x: frame.minX + inset, y: top + size + InterfaceScale.metric(7), width: frame.width - inset * 2, height: lineHeight * 2),
            lineHeight: lineHeight,
            maximumLines: 2
        )
    }

    // MARK: Header and footer

    private static func drawGalleryHeader(_ presentation: ForumCardPresentation, in frame: CGRect) {
        let iconSize = InterfaceScale.metric(12)
        var trailing = frame.maxX
        for (shown, symbol) in [(presentation.isLocked, "lock.fill"), (presentation.isPinned, "pin.fill")] where shown {
            trailing -= iconSize
            NativeTimelineRowPainter.systemSymbol(
                symbol,
                in: CGRect(x: trailing, y: frame.midY - iconSize / 2, width: iconSize, height: iconSize),
                color: .secondaryLabelColor,
                inset: 0,
                weight: .semibold
            )
            trailing -= InterfaceScale.metric(6)
        }
        let lineHeight = ForumBoardMetrics.lineHeight(of: captionFont)
        let textY = frame.midY - lineHeight / 2
        var cursorX = frame.minX
        let posted = ForumTimestampPresentation.roundedRelativeText(for: presentation.createdAt, relativeTo: .now)
        let postedWidth = ceil(NativeTimelineRowPainter.measuredTextWidth(posted, font: captionFont)) + 1
        if let author = presentation.galleryAuthor {
            let bulletWidth = ceil(NativeTimelineRowPainter.measuredTextWidth(" • ", font: captionFont))
            let available = max(0, trailing - InterfaceScale.metric(6) - cursorX - postedWidth - bulletWidth)
            let font = ProfileNameFontCache.font(id: author.fontID, fallback: captionFont)
            ProfileNameFontLoader.shared.request(id: author.fontID)
            if let dot = author.roleDotColor {
                let dotSize = InterfaceScale.metric(7)
                dot.setFill()
                NSBezierPath(ovalIn: CGRect(x: cursorX, y: frame.midY - dotSize / 2, width: dotSize, height: dotSize)).fill()
                cursorX += dotSize + InterfaceScale.metric(4)
            }
            let nameWidth = min(available, ceil(NativeTimelineRowPainter.measuredTextWidth(author.name, font: font)) + 1)
            NativeTimelineRowPainter.text(
                author.name,
                in: CGRect(x: cursorX, y: frame.midY - ForumBoardMetrics.lineHeight(of: font) / 2, width: nameWidth, height: ForumBoardMetrics.lineHeight(of: font)),
                font: font,
                color: author.color ?? .labelColor
            )
            cursorX += nameWidth
            NativeTimelineRowPainter.text(" • ", in: CGRect(x: cursorX, y: textY, width: bulletWidth, height: lineHeight), font: captionFont, color: .tertiaryLabelColor)
            cursorX += bulletWidth
        }
        NativeTimelineRowPainter.text(
            posted,
            in: CGRect(x: cursorX, y: textY, width: max(0, min(postedWidth, trailing - cursorX)), height: lineHeight),
            font: captionFont,
            color: .secondaryLabelColor
        )
    }

    private static func drawFooter(
        _ presentation: ForumCardPresentation,
        regions: ForumCardRegions,
        interaction: ForumCardInteraction,
        model: AppModel?
    ) {
        if let summary = presentation.reaction, let frame = regions.reactionRegionFrame {
            NSGraphicsContext.saveGraphicsState()
            if summary.isDisabled {
                NSGraphicsContext.current?.cgContext.setAlpha(0.45)
            }
            NativeTimelineRowPainter.reaction(
                NativeTimelineRowLayout.reactionRegion(summary.reaction, frame: frame),
                model: model,
                isHovered: interaction.isReactionHovered && !summary.isDisabled,
                countTransition: nil,
                hasAnimatedEmojiOverlay: false
            )
            NSGraphicsContext.restoreGraphicsState()
        }
        if let frame = regions.countFrame {
            let lineHeight = ForumBoardMetrics.lineHeight(of: footerFont)
            let iconSize = InterfaceScale.metric(13)
            NativeTimelineRowPainter.systemSymbol(
                "bubble.left.fill",
                in: CGRect(x: frame.minX, y: frame.midY - iconSize / 2, width: iconSize, height: iconSize),
                color: .secondaryLabelColor,
                inset: 0
            )
            var cursorX = frame.minX + InterfaceScale.metric(14) + InterfaceScale.metric(4)
            let count = presentation.messageCount.formatted()
            let countWidth = ceil(NativeTimelineRowPainter.measuredTextWidth(count, font: footerFont)) + 1
            NativeTimelineRowPainter.text(
                count,
                in: CGRect(x: cursorX, y: frame.midY - lineHeight / 2, width: countWidth, height: lineHeight),
                font: footerFont,
                color: .secondaryLabelColor
            )
            cursorX += countWidth + InterfaceScale.metric(3)
            if presentation.unreadCount > 0 {
                NativeTimelineRowPainter.text(
                    "(\(presentation.unreadCount.formatted()) New)",
                    in: CGRect(x: cursorX, y: frame.midY - lineHeight / 2, width: max(0, frame.maxX - cursorX), height: lineHeight),
                    font: footerEmphasisFont,
                    color: .sakuraCordAccentColor
                )
            }
        }
        if let frame = regions.timestampFrame {
            let lineHeight = ForumBoardMetrics.lineHeight(of: footerFont)
            NativeTimelineRowPainter.text(
                ForumTimestampPresentation.roundedRelativeText(for: presentation.lastActivityAt, relativeTo: .now),
                in: CGRect(x: frame.minX, y: frame.midY - lineHeight / 2, width: frame.width, height: lineHeight),
                font: footerFont,
                color: .secondaryLabelColor
            )
        }
    }

    // MARK: Board chrome

    static func drawSectionHeader(_ title: String, in frame: CGRect) {
        let font = NSFont.interfaceSystemFont(ofSize: 11, weight: .bold)
        let lineHeight = ForumBoardMetrics.lineHeight(of: font)
        NativeTimelineRowPainter.text(
            title.uppercased(),
            in: CGRect(x: frame.minX + InterfaceScale.metric(2), y: frame.maxY - lineHeight - InterfaceScale.metric(4), width: frame.width, height: lineHeight),
            font: font,
            color: .secondaryLabelColor
        )
    }

    /// The failed-page notice; returns its retry button frame.
    static func paginationRetryFrame(in frame: CGRect) -> CGRect {
        let font = NSFont.interfaceSystemFont(ofSize: 13, weight: .medium)
        let width = ceil(NativeTimelineRowPainter.measuredTextWidth("Try Again", font: font)) + InterfaceScale.metric(24)
        let height = InterfaceScale.metric(28)
        return CGRect(x: frame.maxX - InterfaceScale.metric(12) - width, y: frame.midY - height / 2, width: width, height: height)
    }

    static func drawPaginationError(_ message: String, in frame: CGRect, isRetryHovered: Bool) {
        let radius = InterfaceScale.metric(12)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        let iconSize = InterfaceScale.metric(16)
        NativeTimelineRowPainter.systemSymbol(
            "exclamationmark.triangle.fill",
            in: CGRect(x: frame.minX + InterfaceScale.metric(12), y: frame.midY - iconSize / 2, width: iconSize, height: iconSize),
            color: .systemOrange,
            inset: 0
        )
        let retry = paginationRetryFrame(in: frame)
        let textX = frame.minX + InterfaceScale.metric(12) + iconSize + InterfaceScale.metric(10)
        let titleFont = NSFont.interfaceSystemFont(ofSize: 13, weight: .semibold)
        let titleHeight = ForumBoardMetrics.lineHeight(of: titleFont)
        let detailHeight = ForumBoardMetrics.lineHeight(of: captionFont)
        let top = frame.midY - (titleHeight + detailHeight) / 2
        NativeTimelineRowPainter.text(
            "Couldn’t load more posts",
            in: CGRect(x: textX, y: top, width: retry.minX - textX - 8, height: titleHeight),
            font: titleFont,
            color: .labelColor
        )
        NativeTimelineRowPainter.text(
            message,
            in: CGRect(x: textX, y: top + titleHeight, width: retry.minX - textX - 8, height: detailHeight),
            font: captionFont,
            color: .secondaryLabelColor
        )
        let buttonShape = NSBezierPath(roundedRect: retry, xRadius: retry.height / 2, yRadius: retry.height / 2)
        NSColor.labelColor.withAlphaComponent(isRetryHovered ? 0.16 : 0.1).setFill()
        buttonShape.fill()
        let font = NSFont.interfaceSystemFont(ofSize: 13, weight: .medium)
        let lineHeight = ForumBoardMetrics.lineHeight(of: font)
        NativeTimelineRowPainter.text(
            "Try Again",
            in: CGRect(x: retry.minX, y: retry.midY - lineHeight / 2, width: retry.width, height: lineHeight),
            font: font,
            color: .labelColor,
            alignment: .center,
            lineBreakMode: .byClipping
        )
    }
}
