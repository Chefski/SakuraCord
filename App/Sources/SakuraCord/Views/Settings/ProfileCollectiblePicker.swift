import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileCollectiblePicker: View {
    let editor: ProfileEditorState
    let kind: ProfileCollectibleKind
    let profile: UserProfile

    @Environment(\.windowModalContext) private var dismiss
    @Environment(\.windowModalAvailableSize) private var availableSize
    @State private var selectedID: String?
    @State private var hasSelected = false
    @State private var loadError: String?

    private var title: String {
        switch kind {
        case .avatarDecoration: String(localized: "Avatar Decoration", bundle: #bundle)
        case .effect: String(localized: "Profile Effect", bundle: #bundle)
        case .nameplate: String(localized: "Nameplate", bundle: #bundle)
        case .frame: String(localized: "Profile Frame", bundle: #bundle)
        }
    }
    private var originalID: String? {
        editor.selectedCollectibleID(kind)
    }
    private var itemID: String? { hasSelected ? selectedID : originalID }
    private var item: ProfileCollectibleItem? { itemID.flatMap { editor.inventory?.item(id: $0) } }
    private var product: ProfileCollectibleProduct? { itemID.flatMap { editor.inventory?.product(itemID: $0) } }
    private var isAvailable: Bool {
        guard let itemID else { return true }
        return editor.inventory?.canUse(itemID: itemID, hasFullNitro: editor.isNitro) == true
    }
    private var allItems: [ProfileCollectibleItem] { editor.inventory?.items(of: kind) ?? [] }
    private var showsPreview: Bool { availableSize.width >= 700 }
    private var purchasedItems: [ProfileCollectibleItem] {
        allItems.filter { editor.inventory?.owns(itemID: $0.id) == true && editor.inventory?.requiresNitro(itemID: $0.id) == false }
    }
    private var premiumItems: [ProfileCollectibleItem] {
        guard editor.isNitro else { return [] }
        return allItems.filter { editor.inventory?.requiresNitro(itemID: $0.id) == true && editor.inventory?.canUse(itemID: $0.id, hasFullNitro: true) == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Change \(title)", bundle: #bundle).font(.title2.bold())
                Spacer()
                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Your \(title)s", bundle: #bundle).font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) {
                            entryTile(editor.scope.guildID == nil ? "None" : "Use Main Profile", image: "nosign", selected: itemID == nil) { selectedID = nil; hasSelected = true }
                            choices(purchasedItems)
                        }
                        if !premiumItems.isEmpty {
                            Text("Exclusive to Nitro", bundle: #bundle).font(.headline).padding(.top, 12)
                            LazyVGrid(columns: columns, spacing: 12) { choices(premiumItems) }
                        }
                    }
                }
                .frame(width: showsPreview ? min(420, availableSize.width - 348) : nil)
                if showsPreview {
                    VStack(alignment: .leading, spacing: 12) {
                        preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text(product?.name ?? String(localized: "None", bundle: #bundle)).font(.headline)
                            if let date = product?.purchasedAt {
                                Text("Acquired on \(date.formatted(.dateTime.month(.wide).year()))", bundle: #bundle)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let date = product?.expiresAt {
                                Text("Available until \(date.formatted(date: .abbreviated, time: .omitted))", bundle: #bundle)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if !isAvailable { Label("Requires Nitro or ownership", systemImage: "lock.fill").font(.caption) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .overlay { ConcentricRectangle(cornerRadius: 4).stroke(.primary.opacity(0.15), lineWidth: 2) }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 276)
                }
            }
            .padding(.horizontal, 24)
            if let loadError {
                HStack { Text(loadError).font(.callout); Button("Retry") { Task { await load() } } }
                    .padding(12)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss?() }.keyboardShortcut(.cancelAction)
                Button("Apply") { editor.setCollectible(item, kind: kind); dismiss?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isAvailable || itemID == originalID || editor.inventory == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(24)
        }
        .windowModalSize(width: 768, height: 560)
        .overlay { if editor.inventory == nil, loadError == nil { ProgressView().padding().glassEffect() } }
        .task { await load() }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: kind == .nameplate ? 1 : 3)
    }

    private var resolvedProfile: UserProfile {
        var result = profile
        let inherited = editor.scope.guildID == nil ? nil : editor.snapshot?.mainPresentation
        switch kind {
        case .avatarDecoration: result.user.avatarDecorationURL = inherited?.user.avatarDecorationURL
        case .effect: result.effect = inherited?.effect
        case .nameplate: result.user.nameplate = inherited?.user.nameplate
        case .frame: result.frame = inherited?.frame
        }
        if let item { result.applyCollectiblePreview(item) }
        return result
    }

    private func choices(_ items: [ProfileCollectibleItem]) -> some View {
        ForEach(items) { candidate in
            ProfileCollectibleChoice(item: candidate, profile: profile, selected: itemID == candidate.id) {
                selectedID = candidate.id; hasSelected = true
            }
            .overlay(alignment: .topTrailing) {
                if editor.inventory?.canUse(itemID: candidate.id, hasFullNitro: editor.isNitro) != true {
                    Image(systemName: "lock.fill").font(.caption).padding(6).allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if kind == .nameplate {
            VStack(spacing: 8) {
                ForEach(0 ..< 2) { _ in ProfileAnonymousMemberRow() }
                ProfileMemberNameplateRow(profile: resolvedProfile)
                ForEach(0 ..< 2) { _ in ProfileAnonymousMemberRow() }
            }
            .padding(.horizontal, 26)
            .frame(height: 190)
            .background(.black.opacity(0.2), in: ConcentricRectangle(cornerRadius: 10))
            .clipped()
        } else {
            MemberProfilePopover(member: Member(user: resolvedProfile.user, roleName: "", status: resolvedProfile.status), profile: resolvedProfile,
                                 isLoading: false, errorMessage: nil, maximumPopoverHeight: 340, showsRoles: false, footer: EmptyView())
                .scaleEffect(276 / 330, anchor: .topLeading)
                .frame(width: 276, height: 284, alignment: .topLeading)
        }
    }

    private func entryTile(_ label: LocalizedStringKey, image: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: image).font(.title)
                Text(label, bundle: #bundle)
            }
            .frame(maxWidth: .infinity).frame(height: kind == .nameplate ? 80 : 132)
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.05), in: ConcentricRectangle(cornerRadius: 10))
        .overlay { if selected { ConcentricRectangle(cornerRadius: 10).stroke(SakuraCordAccentColor.color, lineWidth: 2) } }
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
    let item: ProfileCollectibleItem
    let profile: UserProfile
    let selected: Bool
    let choose: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: choose) {
            ZStack {
                Color.clear
                switch item.artwork {
                case let .nameplate(nameplate):
                    ProfileAnonymousMemberRow().padding(.horizontal, 8)
                        .frame(height: 42)
                        .background { NameplateBackground(nameplate: nameplate, isAnimated: isHovered) }
                case let .avatarDecoration(url):
                    DecoratedAvatarView(name: profile.displayName, avatarURL: profile.avatarURL, decorationURL: url, size: 64, animatesDecoration: isHovered)
                        .frame(maxWidth: .infinity).frame(height: 132)
                case let .effect(effect):
                    ProfileCosmeticTileArtwork(effect: effect, kind: .effect, fillsTile: true, animates: isHovered)
                        .frame(height: 132)
                case let .frame(frame):
                    ProfileCosmeticTileArtwork(frame: frame, kind: .frame)
                        .frame(height: 132)
                }
            }
            .frame(height: item.kind == .nameplate ? 42 : 132)
            .contentShape(Rectangle())
            .clipShape(ConcentricRectangle(cornerRadius: 10))
            .overlay { if selected { ConcentricRectangle(cornerRadius: 10).stroke(SakuraCordAccentColor.color, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .onModalHover { isHovered = $0 }
        .help(item.label)
        .accessibilityLabel(item.label)
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

extension UserProfile {
    mutating func applyCollectiblePreview(_ item: ProfileCollectibleItem) {
        switch item.artwork {
        case let .avatarDecoration(url): user.avatarDecorationURL = url
        case let .effect(effect): self.effect = effect
        case let .nameplate(nameplate): user.nameplate = nameplate
        case let .frame(frame): self.frame = frame
        }
    }
}
