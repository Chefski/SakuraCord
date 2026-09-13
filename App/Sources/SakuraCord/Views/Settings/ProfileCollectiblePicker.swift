import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileCollectiblePicker: View {
    let editor: ProfileEditorState
    let kind: ProfileCollectibleKind
    let profile: UserProfile
    let dismiss: () -> Void
    @State private var loadError: String?

    private var items: [ProfileCollectibleItem] {
        (editor.inventory?.items(of: kind) ?? []).filter {
            editor.inventory?.canUse(itemID: $0.id, hasFullNitro: editor.isNitro) == true
        }
    }

    private var ownedItems: [ProfileCollectibleItem] {
        items.filter { editor.inventory?.requiresNitro(itemID: $0.id) == false }
    }

    private var nitroItems: [ProfileCollectibleItem] {
        items.filter { editor.inventory?.requiresNitro(itemID: $0.id) == true }
    }

    var body: some View {
        Group {
            if editor.inventory != nil {
                options
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError).font(.callout)
                    Button("Retry") { Task { await load() } }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                choiceGroup(ownedItems, includesNone: true)
                if !nitroItems.isEmpty {
                    Label("Included with Nitro", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    choiceGroup(nitroItems)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder private func choiceGroup(_ items: [ProfileCollectibleItem], includesNone: Bool = false) -> some View {
        if kind == .nameplate {
            // A short, fixed-height list needs no estimated lazy layout. Keeping
            // its full extent stable lets NSScrollView own the elastic overscroll.
            VStack(spacing: 8) {
                if includesNone { choice(nil) }
                ForEach(items) { choice($0) }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                if includesNone { choice(nil) }
                ForEach(items) { choice($0) }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: kind == .nameplate ? 1 : 3)
    }

    private func choice(_ item: ProfileCollectibleItem?) -> some View {
        ProfileCollectibleChoice(item: item, kind: kind, profile: profile, noneTitle: noneTitle,
                                 selected: editor.selectedCollectibleID(kind) == item?.id) {
            editor.setCollectible(item, kind: kind)
            dismiss()
        }
    }

    private var noneTitle: String {
        editor.scope.guildID == nil ? String(localized: "None", bundle: #bundle) : String(localized: "Use Main Profile", bundle: #bundle)
    }

    private func load() async {
        loadError = nil
        do { try await editor.loadInventory() } catch {
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            loadError = error.localizedDescription
        }
    }
}

private struct ProfileCollectibleChoice: View {
    let item: ProfileCollectibleItem?
    let kind: ProfileCollectibleKind
    let profile: UserProfile
    let noneTitle: String
    let selected: Bool
    let choose: () -> Void
    @State private var isHovered = false
    @Environment(\.profilePickerCornerRadius) private var cornerRadius

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius) }

    var body: some View {
        Button(action: choose) {
            ZStack {
                Color.clear
                switch item?.artwork {
                case nil:
                    Label(noneTitle, systemImage: "nosign")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .padding(8)
                case let .nameplate(nameplate):
                    ProfileAnonymousMemberRow().padding(.horizontal, 8)
                        .frame(height: 42)
                        .background { NameplateBackground(nameplate: nameplate, isAnimated: isHovered) }
                case let .avatarDecoration(url):
                    DecoratedAvatarView(name: profile.displayName, avatarURL: profile.avatarURL, decorationURL: url, size: 56, playback: .hover(isHovered))
                        .frame(maxWidth: .infinity).frame(height: 108)
                case let .effect(effect):
                    ProfileCosmeticTileArtwork(effect: effect, kind: .effect, fillsTile: true, animates: isHovered)
                        .frame(height: 108)
                case let .frame(frame):
                    ProfileCosmeticTileArtwork(frame: frame, kind: .frame)
                        .frame(height: 108)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: kind == .nameplate ? 42 : 108)
            .background(.primary.opacity(0.05))
            .contentShape(shape)
            .clipShape(shape)
            .overlay {
                shape.fill(.primary.opacity(isHovered ? 0.08 : 0))
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .overlay {
                shape.strokeBorder(selected ? SakuraCordAccentColor.color : .primary.opacity(isHovered ? 0.3 : 0), lineWidth: selected ? 2 : 1)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
            }
        }
        .buttonStyle(.plain)
        .onModalHover { isHovered = $0 }
        .help(item?.label ?? noneTitle)
        .accessibilityLabel(item?.label ?? noneTitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct ProfileAnonymousMemberRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(.primary.opacity(0.25)).frame(width: 32, height: 32)
            Capsule().fill(.primary.opacity(0.2)).frame(height: 14)
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}
