import SakuraCordModels
import SwiftUI

struct ProfileFrameAnchor {
    let frame: ProfileFrame
    let bounds: Anchor<CGRect>
}

struct ProfileFrameAnchorKey: PreferenceKey {
    static var defaultValue: ProfileFrameAnchor? { nil }

    static func reduce(value: inout ProfileFrameAnchor?, nextValue: () -> ProfileFrameAnchor?) {
        value = nextValue() ?? value
    }
}

/// The profile surface host draws the artwork outside its clip without changing the card.
struct ProfileFrameDecoration: View {
    let anchor: ProfileFrameAnchor?
    let order: String

    var body: some View {
        GeometryReader { geometry in
            if let anchor {
                let bounds = geometry[anchor.bounds]
                ProfileFrameOverlay(frame: anchor.frame, order: order)
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
