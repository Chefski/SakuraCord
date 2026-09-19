import SakuraCordModels
import SwiftUI

struct ProfileThemeTile: View {
    let editor: ProfileEditorState
    let profile: UserProfile
    @Environment(\.displayScale) private var displayScale
    @State private var theme = ProfileThemeState()
    @State private var selectedColor: Endpoint?

    private enum Endpoint { case primary, accent }

    private var colors: [UInt32] {
        theme.colors(for: editor.preview ?? profile, scale: displayScale, allowsTheme: true)
    }

    var body: some View {
        ProfileEditorCardStyle.shape
            .fill(LinearGradient(colors: colors.map(Color.init(hex:)), startPoint: .top, endPoint: .bottom))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        ProfileThemeColorButton(title: "Primary", color: colorBinding(for: .primary), isPresented: presentation(for: .primary))
                            .settingsControlAnchor(.profileThemePrimary)
                        ProfileThemeColorButton(title: "Accent", color: colorBinding(for: .accent), isPresented: presentation(for: .accent))
                            .settingsControlAnchor(.profileThemeAccent)
                    }
                }
                .padding(12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Profile theme colours")
            .contextMenu {
                if editor.scope.guildID != nil {
                    Button("Use Main Profile Theme") { editor.setTheme(nil) }
                }
            }
            .disabled(!editor.isNitro)
            .onChange(of: editor.draftGeneration) { _, _ in selectedColor = nil }
            .onChange(of: editor.isResolvingScope) { _, resolving in if resolving { selectedColor = nil } }
            .task(id: theme.source(for: profile, scale: displayScale, allowsTheme: true)) {
                await theme.load(theme.source(for: profile, scale: displayScale, allowsTheme: true))
            }
    }

    private func colorBinding(for endpoint: Endpoint) -> Binding<UInt32> {
        Binding(get: {
            colors[endpoint == .primary ? 0 : 1]
        }, set: { color in
            // Read the current draft so changing one endpoint preserves the other exactly.
            let current = colors
            editor.setTheme(ProfileThemeColors(
                primary: endpoint == .primary ? color : current[0],
                accent: endpoint == .accent ? color : current[1]
            ))
        })
    }

    private func presentation(for endpoint: Endpoint) -> Binding<Bool> {
        Binding(get: { selectedColor == endpoint }, set: { isPresented in
            if isPresented {
                selectedColor = endpoint
            } else if selectedColor == endpoint {
                selectedColor = nil
            }
        })
    }
}

private struct ProfileThemeColorButton: View {
    let title: LocalizedStringKey
    @Binding var color: UInt32
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: color))
                    .overlay { Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 1) }
                    .frame(width: 24, height: 24)
                Text(title, bundle: #bundle)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(title)
        .accessibilityValue(String(format: "#%06X", color))
        .accessibilityHint("Opens the color picker")
        .sakuraCordColorPicker(isPresented: $isPresented, color: $color)
    }
}
