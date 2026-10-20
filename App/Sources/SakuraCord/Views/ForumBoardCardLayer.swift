import AppKit
import QuartzCore

/// One visible board item. Its chrome (fill, border, lift) is plain layer
/// state, so hover, press and selection animate on the compositor; only the
/// content bitmap is painted, and only when its presentation changes.
final class ForumBoardCard {
    enum Kind: Equatable {
        case card
        case placeholder
        case sectionHeader
        case paginationStatus
    }

    let layer = CALayer()
    let chrome = CALayer()
    let content = CALayer()
    private var shimmer: SkeletonShimmer?
    private let shimmerMask = CAShapeLayer()
    private(set) var kind: Kind = .card
    /// Paints the content in flipped, top-left-origin coordinates.
    var painter: ((CGSize) -> Void)?
    private(set) var hasContent = false

    init() {
        layer.masksToBounds = false
        chrome.cornerCurve = .continuous
        chrome.borderWidth = 1
        chrome.shadowColor = NSColor.black.cgColor
        chrome.shadowRadius = 10
        chrome.shadowOffset = CGSize(width: 0, height: -3)
        layer.addSublayer(chrome)
        content.contentsGravity = .topLeft
        // Content changes cross-fade only when the board asks for it.
        content.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer.addSublayer(content)
    }

    var frame: CGRect {
        get { layer.frame }
        set {
            let sizeChanged = layer.bounds.size != newValue.size
            layer.frame = newValue
            guard sizeChanged else { return }
            let bounds = CGRect(origin: .zero, size: newValue.size)
            chrome.frame = bounds
            content.frame = bounds
            shimmer?.layer.frame = bounds
            shimmerMask.frame = bounds
        }
    }

    func configure(kind: Kind, cornerRadius: CGFloat) {
        self.kind = kind
        chrome.cornerRadius = cornerRadius
        chrome.isHidden = kind == .sectionHeader || kind == .paginationStatus
    }

    /// Renders the content bitmap at `scale`, cross-fading from the previous
    /// bitmap when data arrives. Painting happens here, never in `draw`.
    func render(scale: CGFloat, fading: Bool) {
        let size = layer.bounds.size
        guard let painter, size.width >= 1, size.height >= 1 else {
            content.contents = nil
            hasContent = false
            return
        }
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        painter(size)
        NSGraphicsContext.restoreGraphicsState()
        if fading, hasContent {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.2
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            content.add(transition, forKey: "contents-fade")
        }
        content.contentsScale = scale
        content.contents = context.makeImage()
        hasContent = true
    }

    func clearContent() {
        content.contents = nil
        hasContent = false
        painter = nil
    }

    /// Applies the card's resting, hover, pressed and selected looks. Colors
    /// resolve against the board's appearance.
    func applyChrome(
        isHovered: Bool,
        isKeyboardFocused: Bool,
        isPressed: Bool,
        isSelected: Bool,
        appearance: NSAppearance,
        animated: Bool
    ) {
        var fill = NSColor.clear.cgColor
        var border = NSColor.separatorColor.cgColor
        var shadowOpacity: Float = 0
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch kind {
            case .card:
                let fillAlpha: CGFloat = isPressed ? 0.09 : isSelected ? 0.055 : isHovered ? 0.04 : 0
                fill = NSColor.labelColor.withAlphaComponent(fillAlpha).cgColor
                border = (
                    isSelected
                        ? NSColor.labelColor.withAlphaComponent(0.24)
                        : isHovered
                            ? NSColor.labelColor.withAlphaComponent(isDark ? 0.2 : 0.16)
                            : NSColor.separatorColor
                ).cgColor
                shadowOpacity = isHovered && !isPressed ? (isDark ? 0.32 : 0.12) : 0
            case .placeholder:
                fill = NSColor.labelColor.withAlphaComponent(0.015).cgColor
                border = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            case .sectionHeader, .paginationStatus:
                break
            }
        }
        if isKeyboardFocused, kind == .card {
            appearance.performAsCurrentDrawingAppearance {
                border = NSColor.keyboardFocusIndicatorColor.cgColor
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(isPressed ? 0.08 : 0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        chrome.backgroundColor = fill
        chrome.borderColor = border
        chrome.borderWidth = isKeyboardFocused && kind == .card ? 2 : 1
        chrome.shadowOpacity = shadowOpacity
        let scale: CGFloat = isPressed && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.985 : 1
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    /// Masks a shimmer to `frames` (card coordinates); empty frames stop it.
    func updateShimmer(frames: [CGRect], color: NSColor, animates: Bool) {
        guard !frames.isEmpty, animates else {
            shimmer?.layer.removeFromSuperlayer()
            shimmer = nil
            return
        }
        let shimmer = self.shimmer ?? {
            let value = SkeletonShimmer()
            value.layer.mask = shimmerMask
            layer.addSublayer(value.layer)
            self.shimmer = value
            return value
        }()
        let path = CGMutablePath()
        for frame in frames {
            let radius = min(InterfaceScale.metric(7), frame.height / 2)
            path.addRoundedRect(in: frame, cornerWidth: radius, cornerHeight: radius)
        }
        let bounds = CGRect(origin: .zero, size: layer.bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = bounds
        shimmerMask.path = path
        CATransaction.commit()
        shimmer.update(frame: bounds, color: color, animates: true)
    }
}
