import SakuraCordModels
import SwiftUI

struct ProfilesSettingsPage: View {
    let model: AppModel
    let state: SettingsViewState
    let editor: ProfileEditorState
    @State private var picker: ProfileEditorPicker?
    @State private var nicknames: [GuildID: String] = [:]
    @State private var imageImport = ProfileImageImportRequest()
    @State private var saveBarHeight: CGFloat = 0

    private var showsSaveBar: Bool {
        editor.hasChanges || editor.requiresReload || editor.errorMessage != nil && editor.snapshot != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical) {
                VStack {
                    if let profile = editor.displayProfile {
                        ProfileEditorCanvas(model: model, editor: editor, profile: profile) { picker = $0 }
                            .disabled(editor.isLoading)
                            .allowsHitTesting(!editor.isResolvingScope)
                            .overlay {
                                if editor.isLoading {
                                    RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.12))
                                        .allowsHitTesting(false)
                                }
                            }
                            .authenticationLoading(editor.isLoading,
                                                   in: RoundedRectangle(cornerRadius: 16), intensity: 1.8, opacity: 0.28)
                    } else {
                        ContentUnavailableView {
                            Label("Profile Unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                        } description: {
                            Text(editor.errorMessage ?? String(localized: "Connect an account to edit its profile.", bundle: #bundle))
                        } actions: {
                            Button("Retry") { Task { await editor.load(editor.scope, preferCached: false) } }
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .padding(16)
                // Keep overlay clearance inside the document. Scroll content margins
                // also inset its hit region, blocking the exposed controls beside the bar.
                .padding(.bottom, showsSaveBar ? saveBarHeight : 0)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    if editor.snapshot == nil, let error = editor.errorMessage {
                        VStack(spacing: 8) {
                            Text(error).font(.callout)
                            Button("Retry") { Task { await editor.load(preferCached: false) } }
                        }
                        .padding(16).glassEffect().padding(24)
                    }
                }
            }
            if showsSaveBar {
                ProfileEditorSaveBar(editor: editor)
                    .frame(maxWidth: 640)
                    .padding(16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { saveBarHeight = $0 }
            }
        }
        .navigationTitle(state.catalog.page(.profiles).title)
        .environment(\.profileImageImportRequest, imageImport)
        .fileImporter(isPresented: $imageImport.isPresented, allowedContentTypes: ProfileImagePicker.allowedImageTypes,
                      allowsMultipleSelection: false, onCompletion: imageImport.complete, onCancellation: imageImport.cancel)
        .onDisappear { imageImport.cancel() }
        .background { ProfileEditorFocusDismissal() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProfileScopePicker(scope: editor.scope, guilds: model.snapshot?.guilds ?? [], nicknames: nicknames) { scope in
                    Task { await editor.load(scope) }
                }
                .disabled(editor.isSaving)
            }
        }
        .environment(\.profileAnimationsPaused, picker != nil)
        .windowModal(item: $picker) { selection in
            if let profile = editor.preview {
                ProfileEditorPickerContent(model: model, editor: editor, profile: profile, selection: selection)
            }
        }
        .disabled(model.isSwitchingAccounts)
        .task(id: "\(model.activeAccountID ?? ""):\(model.installedAccountSessionRevision):\(model.isSwitchingAccounts)") {
            picker = nil
            guard !model.isSwitchingAccounts else { return }
            await editor.loadIfNeeded(refreshExisting: true)
            refreshNicknames()
        }
        .onChange(of: editor.snapshot) { _, _ in refreshNicknames() }
        .onChange(of: editor.hasChanges) { _, hasChanges in
            if !hasChanges { Task { await editor.loadIfNeeded(refreshExisting: true) } }
        }
        .onChange(of: editor.isSaving) { _, isSaving in
            if !isSaving { Task { await editor.refreshIfNeeded() } }
        }
        .onChange(of: model.profileCustomStatus) { _, status in editor.receiveCustomStatus(status) }
        .onChange(of: model.profileWidgetConnectionsRevision) { _, _ in Task { await editor.refreshWidgetConnections() } }
    }

    private func refreshNicknames() {
        guard let user = model.snapshot?.currentUser else { return }
        for guild in model.snapshot?.guilds ?? [] {
            nicknames[guild.id] = model.membersByGuildID[guild.id]?[user.id]?.guildNickname
        }
        if let snapshot = editor.snapshot, let guildID = snapshot.scope.guildID { nicknames[guildID] = snapshot.identity.name.value }
    }
}

private struct ProfileEditorCanvas: View {
    let model: AppModel
    let editor: ProfileEditorState
    let profile: UserProfile
    let open: (ProfileEditorPicker) -> Void

    var body: some View {
        VStack(spacing: 32) {
            ProfileEditorExpandedPreview(model: model, editor: editor, profile: profile, open: open)
            ProfileStylesControls(editor: editor, profile: profile)
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .containerShape(.rect(cornerRadius: 16))
    }
}

struct ProfileEditorPickerContent: View {
    let model: AppModel
    let editor: ProfileEditorState
    let profile: UserProfile
    let selection: ProfileEditorPicker
    @Environment(\.windowModalContext) private var modal
    @Environment(\.stablePopoverPresentationContext) private var popover

    private func close() {
        if let popover { popover.dismiss?() } else { modal?() }
    }

    var body: some View {
        switch selection {
        case .avatar:
            ProfileImagePicker(model: model, editor: editor, purpose: .avatar, dismiss: close, apply: { selection, url in editor.setAvatar(selection, previewURL: url) })
        case .banner:
            ProfileImagePicker(model: model, editor: editor, purpose: .banner, dismiss: close, apply: { selection, url in
                if case let .upload(upload) = selection { editor.setBanner(upload, previewURL: url) }
            })
        case .nameStyle:
            ProfileNameStylePicker(editor: editor)
        case let .collectible(kind):
            ProfileCollectiblePicker(editor: editor, kind: kind, profile: profile, dismiss: close)
        }
    }
}
