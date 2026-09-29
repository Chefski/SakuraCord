import AppKit

@MainActor
enum SelectionFieldTokenRenderer {
    struct Result {
        let normal: NSImage
        let hover: NSImage
        let removalStartX: CGFloat?
    }

    static func images<ID: Hashable & Sendable>(
        option: SelectionFieldOption<ID>,
        font: NSFont,
        usesCard: Bool,
        leadingImage: NSImage?,
        maximumWidth: CGFloat = 180
    ) -> Result {
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
        let width = contentWidth
        let removalStartX: CGFloat? = nil

        func image(hovered: Bool) -> NSImage {
            NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
                let card = CGRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: contentWidth,
                    height: bounds.height
                )
                if usesCard {
                    let shape = NSBezierPath(
                        concentricRoundedRect: card,
                        cornerRadius: height / 2
                    )
                    NSColor.labelColor.withAlphaComponent(
                        hovered ? 0.26 : 0.085
                    ).setFill()
                    shape.fill()
                }

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
                drawSystemImage("xmark", in: CGRect(x: contentWidth - 18, y: 10, width: 8, height: 8), color: .secondaryLabelColor)
                return true
            }
        }

        return Result(
            normal: image(hovered: false),
            hover: image(hovered: true),
            removalStartX: removalStartX
        )
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
            drawSystemImage(name, in: rect, color: .secondaryLabelColor)
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

    private static func drawSystemImage(
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
