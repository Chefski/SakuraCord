import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileNameStylePicker: View {
    static let popoverSize = CGSize(width: 380, height: 500)

    let editor: ProfileEditorState
    @Environment(\.colorScheme) private var colorScheme

    private var profile: UserProfile? { editor.displayProfile }
    private var darkAppearance: Bool { colorScheme == .dark }
    private var style: DisplayNameStyle {
        profile?.user.displayNameStyle ?? DisplayNameStyle()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProfileDisplayName(name: profile?.displayName ?? "", style: profile?.user.displayNameStyle, size: 24, wraps: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 8))
                    fontOptions
                    effectOptions
                    HStack {
                        Text("Colors", bundle: #bundle).font(.subheadline)
                        Spacer()
                        ProfileStyleColorOptions(style: Binding(get: { style }, set: { setStyle($0) }), darkAppearance: darkAppearance)
                    }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(editor.isLoading || editor.isSaving || editor.requiresReload || editor.isResolvingScope)
    }

    private var fontOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font", bundle: #bundle).font(.subheadline)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(DiscordProfileNameStyles.catalog.fonts) { font in
                    ProfileNameStyleOption(label: font.id == ProfileNameFontCache.defaultFontID ? String(localized: "Default", bundle: #bundle) : font.name,
                                           isSelected: style.fontID == font.id) {
                        var value = style
                        value.fontID = font.id
                        setStyle(value)
                    } content: { _ in
                        ProfileDisplayName(name: "Gg", style: DisplayNameStyle(fontID: font.id), size: 24,
                                           showsEffects: false, animationIsActive: false)
                    }
                }
            }
        }
    }

    private var effectOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effect", bundle: #bundle).font(.subheadline)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ProfileNameEffect.allCases) { effect in
                    let selected = style.effectID == effect.rawValue
                    ProfileNameStyleOption(label: String(localized: effect.title), isSelected: selected) {
                        guard !selected else { return }
                        setStyle(style(for: effect))
                    } content: { hovering in
                        ProfileDisplayName(name: String(localized: effect.title), style: style(for: effect), size: 14,
                                           animationIsActive: hovering && effect != .solid && effect != .gradient)
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    }

    private func style(for effect: ProfileNameEffect) -> DisplayNameStyle {
        editor.nameStyle(for: effect, darkAppearance: darkAppearance)
    }

    private func setStyle(_ value: DisplayNameStyle) {
        var value = value
        // Discord's Solid default inherits the surrounding text color. The
        // swatch is only a picker preview, not a color to save on the profile.
        if value.effectID == ProfileNameEffect.solid.rawValue,
           value.colors == DiscordProfileNameStyles.defaultColors(for: .solid, darkAppearance: darkAppearance) {
            value.colors = []
        }
        editor.setStyle(value)
    }

}

private struct ProfileNameStyleOption<Content: View>: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Color.primary.opacity(isHovered ? 0.09 : 0.045)
                .frame(height: 52)
                .overlay {
                    content(isHovered)
                        .padding(.horizontal, 6)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? SakuraCordAccentColor.color : Color.primary.opacity(0.1), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onModalHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension ProfileNameEffect {
    var title: LocalizedStringResource {
        switch self {
        case .solid: LocalizedStringResource("Solid", bundle: #bundle)
        case .gradient: LocalizedStringResource("Gradient", bundle: #bundle)
        case .neon: LocalizedStringResource("Neon", bundle: #bundle)
        case .toon: LocalizedStringResource("Toon", bundle: #bundle)
        case .pop: LocalizedStringResource("Pop", bundle: #bundle)
        case .gummy: LocalizedStringResource("Gummy", bundle: #bundle)
        case .prism: LocalizedStringResource("Prism", bundle: #bundle)
        }
    }
}
