import AppKit
import CoreText
import SakuraCordModels

nonisolated enum NativeAppBadgePresentation {
    static let text = NativeIdentityTextPresentation(
        "APP", font: .systemFont(ofSize: ServerTagAppearance.fontSize, weight: .bold)
    )
    static let width = text.width + ServerTagAppearance.horizontalPadding * 2

    @MainActor
    static func draw(in frame: CGRect, color: NSColor, context: CGContext) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(
            roundedRect: frame, cornerWidth: ServerTagAppearance.cornerRadius,
            cornerHeight: ServerTagAppearance.cornerRadius, transform: nil
        ))
        context.fillPath()
        text.draw(
            in: frame.insetBy(dx: ServerTagAppearance.horizontalPadding, dy: 0),
            color: .white, context: context
        )
        context.restoreGState()
    }
}

/// Immutable CoreText content prepared with the row, including its visible
/// glyph bounds. Drawing never measures or truncates identity text.
nonisolated struct NativeIdentityTextPresentation: @unchecked Sendable {
    let line: CTLine
    let width: CGFloat
    private let glyphBounds: CGRect

    init(_ value: String, font: NSFont, maximumWidth: CGFloat = .greatestFiniteMagnitude) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let source = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(source, nil, nil, nil))
        if naturalWidth > maximumWidth {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(source, max(0, maximumWidth), .end, token) ?? token
        } else {
            line = source
        }
        width = min(max(0, maximumWidth), ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if bounds.isNull || bounds.isEmpty {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            glyphBounds = CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
        } else {
            glyphBounds = bounds
        }
    }

    @MainActor
    func draw(in frame: CGRect, color: NSColor, context: CGContext, isUnderlined: Bool = false) {
        guard frame.width > 0, frame.height > 0 else { return }
        context.saveGState()
        context.clip(to: frame)
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.setFillColor(color.cgColor)
        let baseline = frame.height / 2 - glyphBounds.midY
        context.textPosition = CGPoint(x: 0, y: baseline)
        CTLineDraw(line, context)
        if isUnderlined {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 0, y: baseline - 1.5))
            context.addLine(to: CGPoint(x: min(width, frame.width), y: baseline - 1.5))
            context.strokePath()
        }
        context.restoreGState()
    }
}

/// The same server-tag chrome as ProfileServerTag, shared by native canvases.
/// Badge space belongs to the identity even before its cached image arrives.
nonisolated struct NativeServerTagPresentation: @unchecked Sendable {
    static let height = ServerTagAppearance.height
    let identity: PrimaryGuildIdentity
    let width: CGFloat
    private let text: NativeIdentityTextPresentation
    private let font: NSFont
    private var badgeInset: CGFloat { identity.badgeURL == nil ? 0 : ServerTagAppearance.badgeSize + ServerTagAppearance.spacing }
    private var textInset: CGFloat { ServerTagAppearance.horizontalPadding + badgeInset }

    init?(identity: PrimaryGuildIdentity, font: NSFont = .systemFont(ofSize: ServerTagAppearance.fontSize)) {
        guard let tag = identity.tag, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.identity = identity
        self.font = font
        text = NativeIdentityTextPresentation(tag, font: font)
        width = text.width + ServerTagAppearance.horizontalPadding * 2 + (identity.badgeURL == nil ? 0 : ServerTagAppearance.badgeSize + ServerTagAppearance.spacing)
    }

    private init(identity: PrimaryGuildIdentity, font: NSFont, maximumWidth: CGFloat) {
        self.identity = identity
        self.font = font
        let inset = ServerTagAppearance.horizontalPadding * 2 + (identity.badgeURL == nil ? 0 : ServerTagAppearance.badgeSize + ServerTagAppearance.spacing)
        text = NativeIdentityTextPresentation(identity.tag ?? "", font: font, maximumWidth: maximumWidth - inset)
        width = min(maximumWidth, text.width + inset)
    }

    func fitting(maximumWidth: CGFloat) -> Self? {
        guard maximumWidth >= textInset + ServerTagAppearance.horizontalPadding + 14 else { return nil }
        return maximumWidth >= width ? self : Self(identity: identity, font: font, maximumWidth: maximumWidth)
    }

    func badgeFrame(in frame: CGRect) -> CGRect? {
        guard identity.badgeURL != nil else { return nil }
        return CGRect(
            x: frame.minX + ServerTagAppearance.horizontalPadding, y: frame.midY - ServerTagAppearance.badgeSize / 2,
            width: ServerTagAppearance.badgeSize, height: ServerTagAppearance.badgeSize
        )
    }

    @MainActor
    func draw(in frame: CGRect, badgeImage: CGImage?, isHighlighted: Bool, context: CGContext) {
        context.saveGState()
        let shape = CGPath(roundedRect: frame, cornerWidth: ServerTagAppearance.cornerRadius, cornerHeight: ServerTagAppearance.cornerRadius, transform: nil)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(isHighlighted ? ServerTagAppearance.highlightedBackgroundOpacity : ServerTagAppearance.backgroundOpacity).cgColor)
        context.addPath(shape)
        context.fillPath()
        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(ServerTagAppearance.outlineOpacity).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: ServerTagAppearance.cornerRadius - 0.5, cornerHeight: ServerTagAppearance.cornerRadius - 0.5, transform: nil))
        context.strokePath()
        if let badgeImage, let badgeFrame = badgeFrame(in: frame) {
            let scale = min(badgeFrame.width / CGFloat(badgeImage.width), badgeFrame.height / CGFloat(badgeImage.height))
            let size = CGSize(width: CGFloat(badgeImage.width) * scale, height: CGFloat(badgeImage.height) * scale)
            context.saveGState()
            context.translateBy(x: badgeFrame.midX - size.width / 2, y: badgeFrame.midY + size.height / 2)
            context.scaleBy(x: 1, y: -1)
            context.draw(badgeImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
        let textFrame = CGRect(
            x: frame.minX + textInset, y: frame.minY,
            width: max(0, frame.width - textInset - ServerTagAppearance.horizontalPadding), height: frame.height
        )
        text.draw(in: textFrame, color: .labelColor, context: context)
        context.restoreGState()
    }
}
