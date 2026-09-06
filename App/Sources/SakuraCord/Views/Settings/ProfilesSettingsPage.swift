import SakuraCordModels
import SwiftUI

struct ProfilesSettingsPage: View {
    let model: AppModel
    let state: SettingsViewState
    let editor: ProfileEditorState
    @State private var picker: ProfileEditorPicker?
    @State private var nicknames: [GuildID: String] = [:]

    var body: some View {
        SettingsPageForm(page: .profiles, state: state) {
            if editor.isLoading {
                ProgressView("Loading Profile…").frame(maxWidth: .infinity, minHeight: 160)
            } else if let profile = editor.preview {
                ProfileEditorCanvas(model: model, editor: editor, profile: profile) { picker = $0 }
                    .id(editor.scope)
            } else {
                ContentUnavailableView {
                    Label("Profile Unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(editor.errorMessage ?? String(localized: "Connect an account to edit its profile.", bundle: #bundle))
                } actions: {
                    Button("Retry") { Task { await editor.load(editor.scope) } }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProfileScopePicker(scope: editor.scope, guilds: model.snapshot?.guilds ?? [], nicknames: nicknames) { scope in
                    Task { await editor.load(scope) }
                }
                .disabled(editor.isSaving || editor.isLoading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editor.hasChanges || editor.requiresReload || editor.errorMessage != nil && editor.snapshot != nil {
                saveBar.frame(maxWidth: 640)
            }
        }
        .environment(\.profileAnimationsPaused, picker != nil)
        .profileEditorOverlay(item: $picker) { selection in
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
        .onChange(of: model.profileCustomStatus) { _, status in editor.receiveCustomStatus(status) }
        .onChange(of: model.profileWidgetConnectionsRevision) { _, _ in Task { await editor.refreshWidgetConnections() } }
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = editor.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Text(editor.requiresReload ? "Reload the saved profile before continuing." : "Careful — you have unsaved changes!", bundle: #bundle)
                    .font(.callout)
                Spacer()
                if editor.requiresReload {
                    Button("Discard Changes") { editor.resetDraft() }.disabled(editor.isSaving)
                    Button("Reload") { Task { await editor.load(editor.scope) } }.disabled(editor.isLoading)
                } else {
                    Button("Reset") { editor.resetDraft() }.disabled(editor.isSaving)
                    Button { Task { await editor.save() } } label: {
                        if editor.isSaving { ProgressView().controlSize(.small) } else { Text("Save Changes", bundle: #bundle) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!editor.canSave)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: ConcentricRectangle(cornerRadius: 10))
        .overlay { if editor.showsUnsavedReminder { ConcentricRectangle(cornerRadius: 10).stroke(.orange, lineWidth: 2) } }
        .padding(16)
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
    @State private var contentWidth: CGFloat = 680

    var body: some View {
        let sideBySide = contentWidth >= 680
        VStack(spacing: 32) {
            let layout = sideBySide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .center, spacing: 24))
            layout {
                MemberProfilePopover(member: Member(user: profile.user, roleName: "", status: profile.status), profile: profile,
                                     isLoading: false, errorMessage: nil, layout: .editor, maximumPopoverHeight: 10_000,
                                     showsRoles: false, footer: EmptyView(),
                                     editor: editor, openEditorPicker: open)
                    .disabled(editor.isSaving || editor.requiresReload)
                ProfileWidgetsBoard(model: model, editor: editor)
                    .frame(maxWidth: sideBySide ? .infinity : 440)
            }
            ProfileStylesControls(editor: editor, profile: profile, width: contentWidth, open: open)
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 820)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .frame(maxWidth: .infinity)
        // Keep the form's implicit row shape from replacing the profile's concentric corners.
        .containerShape(.rect(cornerRadius: 16))
    }
}

private struct ProfileEditorPickerContent: View {
    let model: AppModel
    let editor: ProfileEditorState
    let profile: UserProfile
    let selection: ProfileEditorPicker
    var body: some View {
        switch selection {
        case .avatar:
            ProfileImagePicker(model: model, editor: editor, purpose: .avatar) { selection, url in editor.setAvatar(selection, previewURL: url) }
        case .banner:
            ProfileImagePicker(model: model, editor: editor, purpose: .banner) { selection, url in
                if case let .upload(upload) = selection { editor.setBanner(upload, previewURL: url) }
            }
        case .nameStyle:
            ProfileNameStylePicker(profile: profile, hasNitro: editor.isNitro) { editor.setStyle($0) }
        case let .collectible(kind):
            ProfileCollectiblePicker(editor: editor, kind: kind, profile: profile)
        }
    }
}
