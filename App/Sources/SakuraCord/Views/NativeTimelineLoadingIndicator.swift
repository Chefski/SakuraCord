import AppKit
import QuartzCore

final class NativeTimelineLoadingIndicator: NSView {
    let replicator = CAReplicatorLayer()
    let spoke = CALayer()
    var controlSize: NSControl.ControlSize = .mini {
        didSet {
            needsLayout = true
            replicator.removeAnimation(forKey: "rotation")
            startAnimating()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        replicator.instanceCount = 8
        replicator.instanceAlphaOffset = -0.095
        replicator.instanceTransform = CATransform3DMakeRotation(
            .pi / 4,
            0,
            0,
            1
        )
        layer?.addSublayer(replicator)
        replicator.addSublayer(spoke)
        updateColorsForEffectiveAppearance()
        startAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColorsForEffectiveAppearance()
    }

    private func updateColorsForEffectiveAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            spoke.backgroundColor = NSColor.secondaryLabelColor
                .withAlphaComponent(0.82).cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        replicator.frame = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        let thickness = max(1.25, side * 0.12)
        let length = max(3, side * 0.28)
        spoke.bounds = CGRect(
            x: 0,
            y: 0,
            width: thickness,
            height: length
        )
        spoke.position = CGPoint(x: side / 2, y: side / 2)
        spoke.anchorPoint = CGPoint(x: 0.5, y: 1.55)
        spoke.cornerRadius = thickness / 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColorsForEffectiveAppearance()
        if window == nil {
            replicator.removeAnimation(forKey: "rotation")
        } else {
            startAnimating()
        }
    }

    func startAnimating() {
        guard replicator.animation(forKey: "rotation") == nil else {
            return
        }
        let rotation = CABasicAnimation(
            keyPath: "transform.rotation.z"
        )
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = controlSize == .small ? 0.9 : 0.8
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(
            name: .linear
        )
        replicator.add(rotation, forKey: "rotation")
    }
}
