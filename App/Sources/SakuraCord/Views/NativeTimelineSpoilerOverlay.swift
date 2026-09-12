import AppKit
import QuartzCore

struct NativeTimelineSpoilerOverlayPresentation: Hashable {
    let cornerRadius: CGFloat
}

nonisolated enum NativeTimelineSpoilerAppearance {
    static let pillHeight: CGFloat = 24
    static let pillHorizontalPadding: CGFloat = 10
    static let textCornerRadius: CGFloat = 4

    static func textBackgroundAlpha(isHovered: Bool) -> CGFloat {
        isHovered ? 0.62 : 0.46
    }

    static func pillFrame(
        in bounds: CGRect,
        measuredLabelWidth: CGFloat
    ) -> CGRect {
        let width = min(
            max(1, bounds.width),
            ceil(measuredLabelWidth) + pillHorizontalPadding * 2
        )
        let height = min(max(1, bounds.height), pillHeight)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func labelFrame(
        in bounds: CGRect,
        measuredLabelHeight: CGFloat
    ) -> CGRect {
        let height = min(
            max(1, bounds.height),
            ceil(measuredLabelHeight)
        )
        return CGRect(
            x: bounds.minX,
            y: bounds.midY - height / 2,
            width: bounds.width,
            height: height
        )
    }

    static func isActivationKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 36, 49, 76:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class NativeTimelineSpoilerOverlayHost: NSView {
    let cornerRadius: CGFloat
    let revealAction: () -> Void
    let pillView = NSView()
    let pillLabel = NSTextField(labelWithString: "SPOILER")
    var trackingArea: NSTrackingArea?
    var isHovered = false
    var isPressed = false
    var didActivate = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(
        frame: CGRect,
        cornerRadius: CGFloat,
        reveal: @escaping () -> Void
    ) {
        self.cornerRadius = cornerRadius
        revealAction = reveal
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            srgbRed: 0.12,
            green: 0.125,
            blue: 0.14,
            alpha: 1
        ).cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        pillView.wantsLayer = true
        pillView.layer?.cornerRadius =
            NativeTimelineSpoilerAppearance.pillHeight / 2
        pillView.layer?.masksToBounds = true
        pillView.setAccessibilityElement(false)
        addSubview(pillView)

        let labelParagraphStyle = NSMutableParagraphStyle()
        labelParagraphStyle.alignment = .center
        pillLabel.attributedStringValue = NSAttributedString(
            string: "SPOILER",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white,
                .kern: 0.4,
                .paragraphStyle: labelParagraphStyle,
            ]
        )
        pillLabel.alignment = .center
        pillLabel.lineBreakMode = .byClipping
        pillLabel.setAccessibilityElement(false)
        pillView.addSubview(pillLabel)
        updateAppearance()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Reveal spoiler")
        setAccessibilityHelp(
            "Reveals this media without opening it"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let labelSize = pillLabel.attributedStringValue.size()
        pillView.frame = NativeTimelineSpoilerAppearance.pillFrame(
            in: bounds,
            measuredLabelWidth: labelSize.width
        )
        pillLabel.frame = NativeTimelineSpoilerAppearance.labelFrame(
            in: pillView.bounds,
            measuredLabelHeight: labelSize.height
        )
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        guard WindowModalCoordinator.allowsInput(for: self) else { return }
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        window?.makeFirstResponder(self)
        isPressed = true
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        let activates =
            isPressed
            && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        updateAppearance()
        if activates {
            activate()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func otherMouseDown(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        if NativeTimelineSpoilerAppearance.isActivationKey(event) {
            activate()
        } else {
            super.keyDown(with: event)
        }
    }

    nonisolated override func accessibilityActionNames()
        -> [NSAccessibility.Action]
    {
        [.press]
    }

    nonisolated override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated {
            activate()
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            NSColor.sakuraCordAccentColor.setStroke()
            let focus = NSBezierPath(
                concentricRoundedRect: bounds.insetBy(dx: 2, dy: 2),
                cornerRadius: max(1, cornerRadius - 2)
            )
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    func updateAppearance() {
        layer?.backgroundColor = (
            isHovered
                ? NSColor(
                    srgbRed: 0.18,
                    green: 0.19,
                    blue: 0.21,
                    alpha: 1
                )
                : NSColor(
                    srgbRed: 0.12,
                    green: 0.125,
                    blue: 0.14,
                    alpha: 1
                )
        ).cgColor
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(
            isPressed ? 0.72 : (isHovered ? 0.62 : 0.52)
        ).cgColor
    }

#if DEBUG
    var hasPersistentPillForTesting: Bool {
        pillView.superview === self
            && pillLabel.superview === pillView
            && !pillView.isHidden
    }
#endif

    func activate() {
        guard !didActivate else { return }
        didActivate = true
        revealAction()
    }
}

/// Presents decoded raster animation frames on Core Animation's compositor.
/// The outer view is deliberately transparent so the selection tint can
/// extend beyond the clipped media box exactly as the Core Text painter does.
