import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileNameStylePicker: View {
    let profile: UserProfile
    let hasNitro: Bool
    let apply: (DisplayNameStyle) -> Void

    @Environment(\.profileEditorModal) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: DisplayNameStyle
    @State private var previewIsDark = true

    init(profile: UserProfile, hasNitro: Bool, apply: @escaping (DisplayNameStyle) -> Void) {
        self.profile = profile
        self.hasNitro = hasNitro
        self.apply = apply
        _draft = State(initialValue: profile.user.displayNameStyle ?? DisplayNameStyle(colors: [0xD4D5D8]))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Change Display Name Style", bundle: #bundle)
                            .font(.title2.bold())
                            .padding(.bottom, 2)
                        ProfileFontOptions(selectedID: $draft.fontID)
                        ProfileEffectOptions(effectID: $draft.effectID, colors: $draft.colors, darkAppearance: colorScheme == .dark)
                        ProfileStyleColorOptions(style: $draft, darkAppearance: colorScheme == .dark)
                    }
                    .padding(24)
                }
                .frame(width: 422)
                ProfileNameStylePreviews(profile: profile, style: draft, isDark: $previewIsDark)
                    .frame(width: 410)
            }
            Divider()
            HStack(spacing: 8) {
                if !hasNitro {
                    Link("Get Nitro", destination: URL(string: "https://discord.com/settings/premium")!)
                }
                Spacer()
                Button {
                    surprise()
                } label: {
                    Label("Surprise Me", systemImage: "dice")
                }
                .controlSize(.large)
                Button("Apply") {
                    apply(draft)
                    dismiss?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasNitro || draft == profile.user.displayNameStyle)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 88)
        }
        .profileEditorModalSize(width: 832, height: 736)
        .overlay(alignment: .topTrailing) {
            HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
                .padding(16)
        }
        .onAppear {
            if profile.user.displayNameStyle == nil {
                draft.colors = DiscordProfileNameStyles.defaultColors(for: .solid, darkAppearance: colorScheme == .dark)
            }
        }
    }

    private func surprise() {
        let catalog = DiscordProfileNameStyles.catalog
        guard let font = catalog.fonts.randomElement(), let effect = ProfileNameEffect.allCases.randomElement() else { return }
        let palettes: [[UInt32]] = switch effect {
        case .gradient: catalog.gradients
        case .gummy: catalog.gummyPalettes
        case .prism: catalog.prismPalettes
        default: catalog.solidColors.map { [$0] }
        }
        draft = DisplayNameStyle(fontID: font.id, effectID: effect.rawValue,
                                 colors: palettes.randomElement() ?? DiscordProfileNameStyles.defaultColors(for: effect, darkAppearance: colorScheme == .dark))
    }
}

private struct ProfileFontOptions: View {
    @Binding var selectedID: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileStyleSectionHeading(title: "Choose Font")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(DiscordProfileNameStyles.catalog.fonts) { font in
                    ProfileStyleOption(isSelected: selectedID == font.id, isNew: font.isNew, label: font.name) {
                        selectedID = font.id
                    } content: { _ in
                        ProfileDisplayName(name: "Gg", style: DisplayNameStyle(fontID: font.id), size: 24, showsEffects: false)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

private struct ProfileEffectOptions: View {
    @Binding var effectID: Int
    @Binding var colors: [UInt32]
    let darkAppearance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileStyleSectionHeading(title: "Choose Effect")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(ProfileNameEffect.allCases) { effect in
                    ProfileStyleOption(isSelected: effectID == effect.rawValue, isNew: effect == .gummy || effect == .prism,
                                       label: String(localized: effect.title)) {
                        effectID = effect.rawValue
                        colors = DiscordProfileNameStyles.defaultColors(for: effect, darkAppearance: darkAppearance)
                    } content: { hovering in
                        ProfileDisplayName(
                            name: String(localized: effect.title),
                            style: DisplayNameStyle(effectID: effect.rawValue, colors: DiscordProfileNameStyles.defaultColors(for: effect, darkAppearance: darkAppearance)),
                            size: 14, animationIsActive: hovering
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

private struct ProfileStyleSectionHeading: View {
    let title: LocalizedStringKey
    var body: some View {
        HStack(spacing: 5) {
            Text(title, bundle: #bundle).font(.headline)
            Image(systemName: "sparkles").font(.caption).accessibilityLabel("Exclusive to Nitro")
        }
    }
}

private struct ProfileStyleOption<Content: View>: View {
    let isSelected: Bool
    let isNew: Bool
    let label: String
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content(isHovered)
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(.primary.opacity(isHovered ? 0.09 : 0.045), in: ConcentricRectangle(cornerRadius: 8))
                .overlay {
                    ConcentricRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : .primary.opacity(0.1), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isNew { Circle().fill(.tint).frame(width: 4, height: 4).padding(6) }
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
