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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(columns: 4).frame(minWidth: 680)
            controls(columns: 2)
        }
    }

    private func controls(columns: Int) -> some View {
        GlassEffectContainer(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns), spacing: 24) {
                if editor.scope == .main || editor.isNitro {
                    ProfileStyleSection(title: "Avatar") {
                        ProfileCustomizationTile(label: "Avatar", selection: .avatar, editor: editor, profile: profile, content: {
                            AvatarView(name: profile.displayName, url: profile.avatarURL, size: 80)
                        })
                    }
                }
                ProfileStyleSection(title: "Avatar Decoration") {
                    ProfileCustomizationTile(label: "Avatar Decoration", selection: .collectible(.avatarDecoration), editor: editor, profile: profile, content: {
                        ProfileEditorCosmeticPreview(profile: profile, kind: .avatarDecoration)
                    })
                }
                if editor.isNitro {
                    ProfileStyleSection(title: "Banner", nitro: true) {
                        ProfileCustomizationTile(label: "Banner", selection: .banner, editor: editor, profile: profile, content: {
                            if let url = profile.bannerURL {
                                AnimatedRemoteImage(url: url, animates: false, contentMode: .fit, usesSwiftUIRendering: true)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .padding(12)
                            } else {
                                Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                            }
                        })
                    }
                    ProfileStyleSection(title: "Theme", nitro: true) {
                        ProfileThemeTile(editor: editor, profile: profile)
                    }
                } else if editor.scope == .main {
                    ProfileStyleSection(title: "Banner Color") {
                        ProfileBannerColorTile(editor: editor, profile: profile)
                    }
                }
                ProfileStyleSection(title: "Nameplate") {
                    ProfileCustomizationTile(label: "Nameplate", selection: .collectible(.nameplate), editor: editor, profile: profile, content: {
                        ProfileEditorCosmeticPreview(profile: profile, kind: .nameplate)
                    })
                }
                if editor.isNitro {
                    ProfileStyleSection(title: "Display Name Style", nitro: true) {
                        ProfileCustomizationTile(label: "Display Name Style", selection: .nameStyle, editor: editor, profile: profile, content: {
                            ProfileDisplayName(name: profile.displayName, style: profile.user.displayNameStyle, size: 22)
                                .allowsHitTesting(false).padding(12)
                        })
                    }
                }
                ProfileStyleSection(title: "Profile Effect") {
                    ProfileCustomizationTile(label: "Profile Effect", selection: .collectible(.effect), editor: editor, profile: profile, content: {
                        ProfileEditorCosmeticPreview(profile: profile, kind: .effect)
                    })
                }
                ProfileStyleSection(title: "Profile Frame") {
                    ProfileCustomizationTile(label: "Profile Frame", selection: .collectible(.frame), editor: editor, profile: profile, content: {
                        ProfileEditorCosmeticPreview(profile: profile, kind: .frame)
                    })
                }
            }
        }
        .disabled(editor.isSaving || editor.requiresReload)
    }
}

/// The card's highlight and artwork share one hover signal, including modal suppression.
private struct ProfileEditorCosmeticPreview: View {
    let profile: UserProfile
    let kind: ProfileCollectibleKind
    @Environment(\.profileEditorCardIsHovered) private var isHovered

    var body: some View {
        switch kind {
        case .avatarDecoration:
            DecoratedAvatarView(name: "", avatarURL: nil, decorationURL: profile.user.avatarDecorationURL, size: 80, playback: .hover(isHovered))
        case .nameplate:
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 28))
                Capsule().frame(height: 10)
            }
            .foregroundStyle(.secondary.opacity(0.6)).padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if let nameplate = profile.user.nameplate {
                    NameplateBackground(nameplate: nameplate, isAnimated: isHovered, preservesTrailingArtwork: true)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .padding(12)
        case .effect:
            ProfileCosmeticTileArtwork(effect: profile.effect, kind: .effect, animates: isHovered)
        case .frame:
            ProfileCosmeticTileArtwork(frame: profile.frame, kind: .frame)
        }
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
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { content.allowsHitTesting(false) }
                .clipShape(ProfileEditorCardStyle.shape)
                .contentShape(ProfileEditorCardStyle.shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: ProfileEditorCardStyle.shape)
        .profileEditorCardHover()
        .accessibilityLabel(label)
    }

}

/// Image and cosmetic pickers share the theme picker's anchored host.
private struct ProfileCustomizationTile<Content: View>: View {
    let label: LocalizedStringKey
    let selection: ProfileEditorPicker
    let editor: ProfileEditorState
    let profile: UserProfile
    @ViewBuilder let content: Content
    @State private var presentedPicker: ProfileEditorPicker?

    var body: some View {
        ProfileEditorTile(label: label, action: { presentedPicker = selection }, content: { content })
            .modifier(ProfileEditorPickerPopover(selection: $presentedPicker, editor: editor, profile: profile))
    }
}

extension EnvironmentValues {
    @Entry var profilePickerCornerRadius: CGFloat = 16
}

struct ProfileEditorPickerPopover: ViewModifier {
    @Binding var selection: ProfileEditorPicker?
    let editor: ProfileEditorState
    let profile: UserProfile
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.profileImageImportRequest) private var imageImport

    private var contentSize: CGSize {
        switch selection {
        case .avatar: ProfileImagePicker.chooserSize(for: .avatar)
        case .banner: ProfileImagePicker.chooserSize(for: .banner)
        case .nameStyle: ProfileNameStylePicker.popoverSize
        default: CGSize(width: 320, height: 360)
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                StableAnchoredPopoverPresenter(isPresented: selection != nil, configuration: .toolbarPanel.fixedContentSize(contentSize),
                                               onDismiss: { selection = nil }, content: {
                    GeometryReader { geometry in
                        if let selection {
                            ProfileEditorPickerContent(model: editor.model, editor: editor, profile: profile, selection: selection)
                                .environment(\.windowModalAvailableSize, geometry.size)
                                .environment(\.profilePickerCornerRadius, optionCornerRadius(in: geometry))
                                .environment(\.colorScheme, colorScheme)
                                .environment(\.locale, locale)
                                .environment(\.profileImageImportRequest, imageImport)
                        }
                    }
                    .frame(width: contentSize.width, height: contentSize.height)
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: editor.draftGeneration) { _, _ in selection = nil }
            .onChange(of: editor.isResolvingScope) { _, resolving in if resolving { selection = nil } }
    }

    private func optionCornerRadius(in geometry: GeometryProxy) -> CGFloat {
        // Resolve against the stationary inset surface, not each moving grid cell.
        // Every option then keeps the same concentric corners while scrolling.
        let padding: CGFloat = selection == .avatar || selection == .banner ? 16 : 8
        guard let radii = geometry.concentricCornerRadii(in: CGRect(origin: .zero, size: geometry.size).insetBy(dx: padding, dy: padding)) else { return 16 }
        return max(16, radii.topLeading, radii.topTrailing, radii.bottomLeading, radii.bottomTrailing)
    }

}

/// Scale artwork inside the square without publishing geometry back into view state.
struct ProfileEditorPaintbrush: View {
    var body: some View {
        GeometryReader { geometry in
            Image(systemName: "paintbrush.fill")
                .font(.system(size: geometry.size.width * 0.28, weight: .medium))
                .foregroundStyle(.white).shadow(radius: 1)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
