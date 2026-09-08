import MetalKit
import SwiftUI

struct SakuraCordWelcomeSequence: View {
    let progress: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = SakuraCordThemeStore.shared.activeTheme.colors(for: colorScheme)
        SakuraCordWelcomePetals(
            progress: progress,
            first: colors[0],
            last: colors[colors.count - 1],
            isDark: colorScheme == .dark
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SakuraCord")
        .accessibilityAddTraits(.isHeader)
    }
}

/// SwiftUI owns the finite animation. The Metal view only draws when that
/// interpolated value or its size changes; it has no independent display loop.
@Animatable
private struct SakuraCordWelcomePetals: View {
    var progress: Double
    @AnimatableIgnored var first: Color
    @AnimatableIgnored var last: Color
    @AnimatableIgnored var isDark: Bool

    var body: some View {
        SakuraCordWelcomeSurface(progress: progress, first: first, last: last, isDark: isDark)
    }
}

private struct SakuraCordWelcomeSurface: NSViewRepresentable {
    let progress: Double
    let first: Color
    let last: Color
    let isDark: Bool

    func makeNSView(context: Context) -> SakuraCordWelcomeMetalView {
        SakuraCordWelcomeMetalView()
    }

    func updateNSView(_ view: SakuraCordWelcomeMetalView, context: Context) {
        view.update(progress: progress, first: first, last: last, isDark: isDark)
    }
}
