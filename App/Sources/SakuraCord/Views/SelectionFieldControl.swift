import AppKit

@MainActor
enum SelectionFieldLayoutMetrics {
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let minimumHeight: CGFloat = 44
    static let tokenHeight: CGFloat = 25
    static let verticalInset: CGFloat = 5
    static let leadingInset: CGFloat = 11
    static let trailingAccessoryInset: CGFloat = 38
    static let expandedAccessoryWidth: CGFloat = 49
    static let expandedAccessoryWidthWithClear: CGFloat = 76

    static func tokenWidth<ID: Hashable & Sendable>(_ option: SelectionFieldOption<ID>, availableWidth: CGFloat) -> CGFloat {
        let titleWidth = (option.title as NSString).size(withAttributes: [.font: font]).width
        let leadingWidth: CGFloat = option.leading == .none ? 0 : 28
        return min(max(40, availableWidth), min(220, ceil(titleWidth + leadingWidth + 35)))
    }

    static func preferredHeight<ID: Hashable & Sendable>(
        options: [SelectionFieldOption<ID>],
        width: CGFloat,
        usesCards: Bool
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

@MainActor
enum SelectionFieldChromeRenderer {
    static func chevronRect(in frame: CGRect) -> CGRect {
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
        isExpanded: Bool,
        in frame: CGRect,
        opacity: CGFloat = 1
    ) {
        drawSystemImage(
            isExpanded ? "chevron.up" : "chevron.down",
            in: chevronRect(in: frame),
            pointSize: 12,
            weight: .semibold,
            opacity: opacity
        )
    }

    static func drawSystemImage(
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
}
