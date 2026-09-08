import SwiftUI

struct SakuraCordWelcomeSequence: View {
    let progress: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = SakuraCordThemeStore.shared.activeTheme.colors(for: colorScheme)
        GeometryReader { geometry in
            Text(verbatim: "SakuraCord")
                .font(.system(size: min(148, geometry.size.width * 0.112), weight: .bold, design: .default))
                .tracking(-6)
                .foregroundStyle(.white)
                .padding(64)
                .modifier(SakuraCordWelcomeOptics(
                    progress: progress,
                    first: colors[0],
                    last: colors[colors.count - 1],
                    ink: colorScheme == .dark ? Color(hex: 0xF5F2FF) : Color(hex: 0x292337)
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SakuraCord")
        .accessibilityAddTraits(.isHeader)
    }
}

/// SwiftUI interpolates one finite phase; no repeating clock or work survives
/// the intro. The padded text layer leaves room for the continuous refraction.
@Animatable
private struct SakuraCordWelcomeOptics: ViewModifier {
    var progress: Double
    @AnimatableIgnored var first: Color
    @AnimatableIgnored var last: Color
    @AnimatableIgnored var ink: Color

    func body(content: Content) -> some View {
        content
            .layerEffect(
                ShaderLibrary.bundle(.module).sakuraWelcomeWordmark(
                    .boundingRect, .float(progress), .color(first), .color(last), .color(ink)
                ),
                maxSampleOffset: CGSize(width: 32, height: 24)
            )
            .shadow(color: first.opacity(0.28 * pow(sin(progress * .pi), 2)), radius: 18)
            .scaleEffect(1.06 - 0.06 * min(progress / 0.65, 1))
    }
}
