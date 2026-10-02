import AppKit

@MainActor
enum SelectionFieldLayoutMetrics {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let minimumHeight: CGFloat = 44
    static let leadingInset: CGFloat = 11

    static func tokenWidth<ID: Hashable & Sendable>(_ option: SelectionFieldOption<ID>, availableWidth: CGFloat) -> CGFloat {
        let titleWidth = (option.title as NSString).size(withAttributes: [.font: font]).width
        let leadingWidth: CGFloat = option.leading == .none ? 0 : 28
        return min(max(40, availableWidth), min(220, ceil(titleWidth + leadingWidth + 35)))
    }

    static func preferredHeight<ID: Hashable & Sendable>(
        options: [SelectionFieldOption<ID>],
        width: CGFloat
    ) -> CGFloat {
        let available = max(40, width - 50)
        var lineWidth: CGFloat = 0
        var lines = 1
        let widths = options.map { tokenWidth($0, availableWidth: available) }
        for tokenWidth in widths {
            if lineWidth > 0, lineWidth + tokenWidth > available {
                lines += 1
                lineWidth = 0
            }
            lineWidth += tokenWidth + 6
        }
        return max(minimumHeight, CGFloat(lines) * 28 + CGFloat(lines - 1) * 6 + 14)
    }

}

/// AppKit rendering for collapsed message-component fields; interactive fields use SwiftUI.
@MainActor
enum SelectionFieldRenderer {
    private static func chevronRect(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.maxX - 31,
            y: frame.midY - 10,
            width: 20,
            height: 20
        )
    }

    static func drawText(
        _ value: String,
        in frame: CGRect,
        color: NSColor,
        opacity: CGFloat = 1
    ) {
        guard !value.isEmpty else { return }
        let font = SelectionFieldLayoutMetrics.font
        let lineHeight = ceil(font.boundingRectForFont.height)
        (value as NSString).draw(
            in: CGRect(
                x: frame.minX + SelectionFieldLayoutMetrics.leadingInset,
                y: floor(frame.midY - lineHeight / 2),
                width: max(1, frame.width - 65),
                height: lineHeight + 2
            ),
            withAttributes: [
                .font: font,
                .foregroundColor: color.withAlphaComponent(
                    color.alphaComponent * opacity
                ),
            ]
        )
    }

    static func drawChevron(
        in frame: CGRect,
        opacity: CGFloat = 1
    ) {
        drawSystemImage(
            "chevron.down",
            in: chevronRect(in: frame),
            pointSize: 12,
            weight: .semibold,
            opacity: opacity
        )
    }

    private static func drawSystemImage(
        _ name: String,
        in rect: CGRect,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        opacity: CGFloat = 1
    ) {
        let color = NSColor.secondaryLabelColor.withAlphaComponent(opacity)
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: weight
        ).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        else { return }
        let destination = NativeTimelineSymbolGeometry.opticallyFitted(
            sourceSize: image.size,
            alignmentRect: image.alignmentRect,
            in: rect
        )
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    static func tokenImage<ID: Hashable & Sendable>(
        option: SelectionFieldOption<ID>,
        font: NSFont,
        leadingImage: NSImage?,
        maximumWidth: CGFloat = 180
    ) -> NSImage {
        let labelFont = NSFont.systemFont(
            ofSize: font.pointSize,
            weight: .medium
        )
        let labelSize = (option.title as NSString).size(
            withAttributes: [.font: labelFont]
        )
        let height: CGFloat = 28
        let leadingSize: CGFloat = 20
        let hasLeading = option.leading != .none
        let closeWidth: CGFloat = 26
        let contentWidth = maximumWidth
        return NSImage(size: NSSize(width: contentWidth, height: height), flipped: false) { bounds in
            let card = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: contentWidth,
                height: bounds.height
            )
            let shape = NSBezierPath(
                concentricRoundedRect: card,
                cornerRadius: height / 2
            )
            NSColor.labelColor.withAlphaComponent(0.085).setFill()
            shape.fill()

            var contentX: CGFloat = 9
            if hasLeading {
                let rect = CGRect(
                    x: contentX,
                    y: (height - leadingSize) / 2,
                    width: leadingSize,
                    height: leadingSize
                )
                draw(
                    option.leading,
                    image: leadingImage,
                    in: rect
                )
                contentX = rect.maxX + 8
            }
            let textY = floor((height - labelSize.height) / 2)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (option.title as NSString).draw(
                in: CGRect(x: contentX, y: textY, width: max(0, contentWidth - contentX - closeWidth), height: labelSize.height),
                withAttributes: [
                    .font: labelFont,
                    .paragraphStyle: paragraph,
                    .foregroundColor: titleColor(
                        for: option.titleStyle
                    ),
                ]
            )
            drawTokenSymbol("xmark", in: CGRect(x: contentWidth - 18, y: 10, width: 8, height: 8), color: .secondaryLabelColor)
            return true
        }
    }

    private static func draw(
        _ leading: SelectionFieldLeading,
        image: NSImage?,
        in rect: CGRect
    ) {
        switch leading {
        case .none:
            return
        case .systemImage(let name):
            drawTokenSymbol(name, in: rect, color: .secondaryLabelColor)
        case .text(let value):
            let font = NSFont.systemFont(ofSize: rect.height * 0.75)
            let size = (value as NSString).size(withAttributes: [.font: font])
            (value as NSString).draw(
                at: CGPoint(
                    x: rect.midX - size.width / 2,
                    y: rect.midY - size.height / 2
                ),
                withAttributes: [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        case let .role(colorHex, _, unicodeEmoji):
            if let image {
                image.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: false,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else if let unicodeEmoji, !unicodeEmoji.isEmpty {
                let font = NSFont.systemFont(ofSize: rect.height * 0.75)
                let size = (unicodeEmoji as NSString).size(
                    withAttributes: [.font: font]
                )
                (unicodeEmoji as NSString).draw(
                    at: CGPoint(
                        x: rect.midX - size.width / 2,
                        y: rect.midY - size.height / 2
                    ),
                    withAttributes: [
                        .font: font,
                        .foregroundColor: NSColor.labelColor,
                    ]
                )
            } else {
                RoleColorIndicatorRenderer.draw(
                    colorHex: colorHex,
                    in: rect.insetBy(dx: 3, dy: 3)
                )
            }
        case .remoteImage(_, let fallback, let shape):
            let path = switch shape {
            case .circle:
                NSBezierPath(ovalIn: rect)
            case .roundedRectangle:
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            }
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            if let image {
                image.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: false,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else {
                NSColor.sakuraCordAccentColor.withAlphaComponent(0.65).setFill()
                path.fill()
                let value = String(fallback.prefix(1)).uppercased() as NSString
                let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                let size = value.size(withAttributes: [.font: font])
                value.draw(
                    at: CGPoint(
                        x: rect.midX - size.width / 2,
                        y: rect.midY - size.height / 2
                    ),
                    withAttributes: [
                        .font: font,
                        .foregroundColor: NSColor.white,
                    ]
                )
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func titleColor(
        for style: SelectionFieldTitleStyle
    ) -> NSColor {
        switch style {
        case .standard:
            .labelColor
        case .memberColor(let colorHex):
            if SakuraCordAccentColor.usesAccentFallback(
                forRoleColorHex: colorHex
            ) {
                .labelColor
            } else {
                SakuraCordAccentColor.nsColor(
                    forRoleColorHex: colorHex
                )
            }
        case .roleColor(let colorHex):
            SakuraCordAccentColor.nsColor(forRoleColorHex: colorHex)
        }
    }

    private static func drawTokenSymbol(
        _ name: String,
        in rect: CGRect,
        color: NSColor
    ) {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: rect.height,
            weight: .semibold
        ).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        else { return }
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
