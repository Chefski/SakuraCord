import SakuraCordModels
import SwiftUI

enum ProfileEditorPicker: Hashable, Identifiable {
    case avatar, banner, nameStyle
    case collectible(ProfileCollectibleKind)
    var id: String {
        switch self {
        case .avatar: "avatar"
        case .banner: "banner"
        case .nameStyle: "name-style"
        case let .collectible(kind): "collectible-\(kind.rawValue)"
        }
    }
}

struct ProfileStylesControls: View {
    let editor: ProfileEditorState
    let profile: UserProfile
    let width: CGFloat
    let open: (ProfileEditorPicker) -> Void

    private var columnCount: Int { width >= 680 ? 4 : 2 }
    private var tileSize: CGFloat { (width - CGFloat(columnCount - 1) * 16) / CGFloat(columnCount) }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columnCount), spacing: 24) {
                ProfileStyleSection(title: "Avatar") {
                    ProfileEditorTile(label: "Avatar", height: tileSize, action: { open(.avatar) },
                                      remove: !editor.hasAvatarSelection ? nil : { editor.setAvatar(nil) },
                                      removalTitle: editor.avatarRemovalTitle, content: {
                        AvatarView(name: profile.displayName, url: profile.avatarURL, size: 80)
                    })
                }
                ProfileStyleSection(title: "Avatar Decoration") {
                    ProfileEditorTile(label: "Avatar Decoration", height: tileSize, action: { open(.collectible(.avatarDecoration)) },
                                      remove: editor.selectedCollectibleID(.avatarDecoration) == nil ? nil : { editor.setCollectible(nil, kind: .avatarDecoration) },
                                      removalTitle: editor.collectibleRemovalTitle(.avatarDecoration), content: {
                        DecoratedAvatarView(name: "", avatarURL: nil, decorationURL: profile.user.avatarDecorationURL, size: 80)
                    })
                }
                ProfileStyleSection(title: "Banner", nitro: true) {
                    ProfileEditorTile(label: "Banner", height: tileSize, action: { open(.banner) },
                                      remove: !editor.hasBannerSelection ? nil : { editor.setBanner(nil) },
                                      removalTitle: editor.bannerRemovalTitle, content: {
                        if let url = profile.bannerURL {
                            AnimatedRemoteImage(url: url, animates: false, contentMode: .fill)
                        } else {
                            Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                        }
                    })
                }
                ProfileStyleSection(title: "Theme", nitro: true) {
                    ProfileThemeTile(editor: editor, profile: profile, height: tileSize)
                }
                ProfileStyleSection(title: "Nameplate") {
                    ProfileEditorTile(label: "Nameplate", height: tileSize, action: { open(.collectible(.nameplate)) },
                                      remove: editor.selectedCollectibleID(.nameplate) == nil ? nil : { editor.setCollectible(nil, kind: .nameplate) },
                                      removalTitle: editor.collectibleRemovalTitle(.nameplate), content: {
                        ZStack {
                            if let nameplate = profile.user.nameplate { NameplateBackground(nameplate: nameplate, isAnimated: false) }
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.fill").font(.system(size: 28))
                                Capsule().frame(height: 10)
                            }
                            .foregroundStyle(.secondary.opacity(0.6)).padding(.horizontal, 10)
                        }
                        .frame(height: 42)
                        .clipShape(.rect(cornerRadius: 8))
                        .padding(12)
                    })
                }
                ProfileStyleSection(title: "Display Name Style", nitro: true) {
                    ProfileEditorTile(label: "Display Name Style", height: tileSize, action: { open(.nameStyle) },
                                      remove: !editor.hasNameStyleSelection ? nil : { editor.setStyle(nil) },
                                      removalTitle: editor.nameStyleRemovalTitle, content: {
                        ProfileDisplayName(name: profile.displayName, style: profile.user.displayNameStyle, size: 22)
                            .allowsHitTesting(false).padding(12)
                    })
                }
                ProfileStyleSection(title: "Profile Effect") {
                    ProfileEditorTile(label: "Profile Effect", height: tileSize, action: { open(.collectible(.effect)) },
                                      remove: editor.selectedCollectibleID(.effect) == nil ? nil : { editor.setCollectible(nil, kind: .effect) },
                                      removalTitle: editor.collectibleRemovalTitle(.effect), content: {
                        ProfileCosmeticTileArtwork(effect: profile.effect, kind: .effect)
                    })
                }
                ProfileStyleSection(title: "Profile Frame") {
                    ProfileEditorTile(label: "Profile Frame", height: tileSize, action: { open(.collectible(.frame)) },
                                      remove: editor.selectedCollectibleID(.frame) == nil ? nil : { editor.setCollectible(nil, kind: .frame) },
                                      removalTitle: editor.collectibleRemovalTitle(.frame), content: {
                        ProfileCosmeticTileArtwork(frame: profile.frame, kind: .frame)
                    })
                }
            }
        }
        .disabled(editor.isSaving || editor.requiresReload)
    }
}

private struct ProfileStyleSection<Content: View>: View {
    let title: LocalizedStringKey
    var nitro = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(title, bundle: #bundle).font(.headline)
                if nitro { Image(systemName: "sparkles").font(.caption).accessibilityLabel("Exclusive to Nitro") }
            }
            content
        }
    }
}

private struct ProfileEditorTile<Content: View>: View {
    let label: LocalizedStringKey
    var height: CGFloat? = 100
    let action: () -> Void
    var remove: (() -> Void)?
    var removalTitle: String?
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            artwork
                .clipShape(ConcentricRectangle(cornerRadius: 8))
                .contentShape(ConcentricRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: ConcentricRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if let remove, isHovered {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.primary, .background) }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel(removalTitle.map(Text.init) ?? Text("Remove \(Text(label))"))
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityActions {
            if let remove {
                Button(action: remove) {
                    removalTitle.map(Text.init) ?? Text("Remove \(Text(label))")
                }
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let height {
            content.frame(maxWidth: .infinity).frame(height: height)
        } else {
            content.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
}

private struct ProfileThemeTile: View {
    let editor: ProfileEditorState
    let profile: UserProfile
    let height: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var theme = ProfileThemeState()
    @State private var isColorPickerPresented = false
    @State private var isHovered = false

    private var colors: ProfileThemeColors {
        editor.changes.metadata.themeColors.applying(to: editor.snapshot?.metadata.themeColors ?? .missing).value
            ?? ProfileThemeColors(primary: nil, accent: nil)
    }

    private var canReset: Bool {
        editor.scope.guildID != nil && (colors.primary != nil || colors.accent != nil)
    }

    private var primaryColor: UInt32 { theme.colors(for: profile, scale: displayScale, isPreview: true)[0] }
    private var accentColor: UInt32 { theme.colors(for: profile, scale: displayScale, isPreview: true)[1] }

    var body: some View {
        Button { isColorPickerPresented = true } label: {
            ConcentricRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(hex: primaryColor), Color(hex: accentColor)], startPoint: .top, endPoint: .bottom))
                .overlay { Image(systemName: "pencil").foregroundStyle(.white).shadow(radius: 1) }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(ConcentricRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile theme colours")
        .sakuraCordColorPicker(isPresented: $isColorPickerPresented, colors: Binding(get: {
            [primaryColor, accentColor]
        }, set: { colors in
            editor.setTheme(ProfileThemeColors(primary: colors[0], accent: colors[1]))
        }), colorCount: 2 ... 2)
        .overlay(alignment: .topTrailing) {
            if canReset, isHovered {
                Button { editor.setTheme(nil) } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .symbolRenderingMode(.palette).foregroundStyle(.primary, .background)
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Reset Theme")
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityActions {
            if canReset { Button("Reset Theme") { editor.setTheme(nil) } }
        }
        .disabled(!editor.isNitro)
        .task(id: theme.source(for: profile, scale: displayScale, isPreview: true)) {
            await theme.load(theme.source(for: profile, scale: displayScale, isPreview: true))
        }
    }
}
