import SwiftUI

/// The outer card follows the 44-point pill controls plus its content inset.
enum SakuraCordAuthenticationMetrics {
    static let controlRadius: CGFloat = 22
    static let cardInset: CGFloat = 36
    static let cardRadius = controlRadius + cardInset
    static let qrSize: CGFloat = 186
}

struct SakuraCordAuthenticationCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = SakuraCordThemeStore.shared.activeTheme.colors(for: colorScheme)
        let firstColor = colors[0]
        let cardColors = colors.enumerated().map { index, color in
            let progress = colors.count == 1
                ? 0
                : Double(index) / Double(colors.count - 1)
            return color.opacity(0.20 - 0.04 * progress)
        }
        VStack(spacing: 18) { content }
            .padding(SakuraCordAuthenticationMetrics.cardInset)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: SakuraCordAuthenticationMetrics.cardRadius, style: .continuous)
            )
            .background(
                LinearGradient(
                    colors: cardColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: SakuraCordAuthenticationMetrics.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SakuraCordAuthenticationMetrics.cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [firstColor.opacity(0.34), .primary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .containerShape(.rect(cornerRadius: SakuraCordAuthenticationMetrics.cardRadius))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.18), radius: 30, y: 18)
    }
}

struct SakuraCordAuthenticationCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help("Close")
        .accessibilityLabel("Close")
        .keyboardShortcut(.cancelAction)
    }
}

struct SakuraCordOnboardingContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Continue", bundle: #bundle)
                Image(systemName: "arrow.right")
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .keyboardShortcut(.defaultAction)
    }
}

extension View {
    func authenticationLoading<S: Shape>(_ isLoading: Bool, in shape: S, intensity: Double = 1) -> some View {
        modifier(AuthenticationLoadingSurface(isLoading: isLoading, shape: shape, intensity: intensity))
    }
}

private struct AuthenticationLoadingSurface<S: Shape>: ViewModifier {
    let isLoading: Bool
    let shape: S
    let intensity: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                let colors = SakuraCordThemeStore.shared.activeTheme.colors(for: colorScheme)
                SakuraCordAuthenticationTimeline { elapsed in
                    Rectangle()
                        .fill(.white)
                        .colorEffect(ShaderLibrary.bundle(.module).sakuraAuthenticationLoading(
                            .boundingRect,
                            .float(elapsed),
                            .color(colors[0]),
                            .color(colors[colors.count - 1]),
                            .float(intensity)
                        ))
                        .clipShape(shape)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
