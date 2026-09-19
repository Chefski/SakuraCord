import SwiftUI

struct CompactProfileWidgetHover: ViewModifier {
    var backgroundOpacity = 0.035
    var cornerRadius: CGFloat = 10
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                .primary.opacity(backgroundOpacity + (isHovered && isEnabled ? 0.04 : 0)),
                in: ConcentricRectangle(cornerRadius: cornerRadius)
            )
            .onModalHover { isHovered = $0 }
            .onDisappear { isHovered = false }
    }
}

struct ProfileWidgetHover: ViewModifier {
    var tilts = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.windowModalInputAllowed) private var inputAllowed
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var size: CGSize = .zero
    @State private var pointer: CGPoint = .zero

    private var active: Bool { isHovered && inputAllowed && isEnabled }
    private var rotates: Bool { active && tilts && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .brightness(active ? (tilts ? -0.08 : 0.06) : 0)
            .rotation3DEffect(.degrees(rotates ? pointer.y * 8 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(rotates ? -pointer.x * 8 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .scaleEffect(rotates ? 1.04 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.85), value: pointer)
            // Track the untransformed bounds so the tilted edges don't move the hit area.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    isHovered = true
                    guard tilts, !reduceMotion, inputAllowed, isEnabled, size.width > 0, size.height > 0 else { return }
                    pointer = CGPoint(
                        x: min(1, max(-1, location.x / size.width * 2 - 1)),
                        y: min(1, max(-1, location.y / size.height * 2 - 1))
                    )
                case .ended:
                    isHovered = false
                    pointer = .zero
                }
            }
            .onChange(of: inputAllowed) { _, allowed in
                if !allowed { isHovered = false; pointer = .zero }
            }
            .onDisappear { isHovered = false; pointer = .zero }
    }
}
