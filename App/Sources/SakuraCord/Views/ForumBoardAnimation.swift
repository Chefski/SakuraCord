import AppKit
import QuartzCore

extension ForumBoardView {
    /// List and gallery cards differ too much to glide between; the whole
    /// board cross-fades, then tiles settle in.
    func crossFadeBoard() {
        guard !reducesMotion else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.22
        cardsLayer.add(fade, forKey: "morph")
    }

    /// Reduce Motion replaces travel and scaling with cross-fades.
    var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func animateMove(_ card: ForumBoardCard, from oldFrame: CGRect) {
        if reducesMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.4
            fade.toValue = 1
            fade.duration = 0.22
            card.layer.add(fade, forKey: "move")
            return
        }
        let spring = CASpringAnimation(keyPath: "position")
        spring.fromValue = NSValue(point: CGPoint(
            x: oldFrame.minX + oldFrame.width * card.layer.anchorPoint.x,
            y: oldFrame.minY + oldFrame.height * card.layer.anchorPoint.y
        ))
        spring.toValue = NSValue(point: card.layer.position)
        spring.damping = 26
        spring.stiffness = 260
        spring.mass = 1
        spring.duration = min(spring.settlingDuration, 0.55)
        card.layer.add(spring, forKey: "move")
    }

    func animateEntrance(_ card: ForumBoardCard, delay: CFTimeInterval) {
        let group = CAAnimationGroup()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let lift = CABasicAnimation(keyPath: "transform")
        lift.fromValue = NSValue(caTransform3D: CATransform3DConcat(
            CATransform3DMakeScale(0.97, 0.97, 1),
            CATransform3DMakeTranslation(0, InterfaceScale.metric(8), 0)
        ))
        lift.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        group.animations = reducesMotion ? [fade] : [fade, lift]
        group.duration = 0.28
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        card.layer.add(group, forKey: "entrance")
    }

    /// Placeholders appear only if loading lasts long enough to notice, so a
    /// fast load never flashes skeletons.
    func animatePlaceholderEntrance(_ card: ForumBoardCard) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        fade.beginTime = CACurrentMediaTime() + 0.12
        fade.fillMode = .backwards
        card.layer.add(fade, forKey: "placeholder-entrance")
    }

    func animateExit(_ card: ForumBoardCard) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                // The card owns its layer until the fade ends.
                guard let self else {
                    card.layer.removeFromSuperlayer()
                    return
                }
                self.recycle(card)
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = card.layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.18
        card.layer.opacity = 0
        card.layer.add(fade, forKey: "exit")
        CATransaction.commit()
    }
}
