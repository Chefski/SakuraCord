import SakuraCordModels
import SwiftUI

/// Discord's Change Nickname and friend-nickname dialogs. Edits stay local
/// until Save; a failed save keeps the dialog open with Discord's reason.
struct NicknameEditorView: View {
    let model: AppModel
    let presentation: NicknameEditorStore.Presentation
    @Environment(\.windowModalContext) private var modal
    @Environment(\.windowModalAvailableSize) private var availableSize

    var body: some View {
        let store = model.nicknameEditor
        let isFriend = presentation.target == .friend
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NicknameEditorCopy.title(for: presentation))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if isFriend {
                    Text("Find a friend faster with a personal nickname. It will only be visible to you in your direct messages.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(
                        "Nicknames are visible to everyone on this server. Do not change them unless you are enforcing a naming system or clearing a bad nickname.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                NicknameEditorField(
                    title: isFriend ? "Friend Nickname" : "Nickname",
                    placeholder: presentation.fallbackName,
                    draft: Bindable(store).draft,
                    submit: save
                )
                if let error = store.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Discord offers a server reset only while a nickname is set.
                if isFriend || presentation.currentNickname != nil {
                    Button(isFriend ? "Reset Friend Nickname" : "Reset Nickname") { store.draft = "" }
                        .buttonStyle(.link)
                }
            }
            .disabled(store.isSaving)
            .padding(.horizontal, 12)
            // Keep the 12-point footer inset that makes the capsules concentric with the panel.
            HStack {
                ModalGlassButton(symbol: "xmark", label: "Cancel") { modal?.dismiss() }
                    .disabled(store.isSaving)
                Spacer(minLength: 16)
                ModalGlassButton(symbol: "checkmark", label: "Save", primary: true, isLoading: store.isSaving, action: save)
                    .disabled(store.isSaving)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(.top, 12)
        .padding(12)
        .frame(width: min(400, availableSize.width))
        .windowModalDismissDisabled(store.isSaving)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NicknameEditorCopy.title(for: presentation))
    }

    private func save() {
        guard !model.nicknameEditor.isSaving else { return }
        model.saveNickname(presentation)
    }
}

nonisolated enum NicknameEditorCopy {
    static func title(for presentation: NicknameEditorStore.Presentation) -> String {
        switch presentation.target {
        case .server: "Change Nickname"
        case .friend: presentation.currentNickname == nil ? "Add Friend Nickname" : "Change Friend Nickname"
        }
    }
}

private struct NicknameEditorField: View {
    let title: String
    let placeholder: String
    @Binding var draft: String
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain).font(.body)
                .focused($isFocused)
                .onSubmit(submit)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(ModalInputSurface(isFocused: isFocused) { isFocused = true })
                .onChange(of: draft) { _, value in
                    // Discord's 32-character limit counts UTF-16 units, as its text input does.
                    guard value.utf16.count > NicknameEditorStore.maximumLength else { return }
                    var trimmed = value
                    while trimmed.utf16.count > NicknameEditorStore.maximumLength { trimmed.removeLast() }
                    draft = trimmed
                }
                .accessibilityLabel(title)
        }
        .task {
            await Task.yield()
            isFocused = true
        }
    }
}

struct NicknameEditorPresentationModifier: ViewModifier {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .windowModal(item: Bindable(model.nicknameEditor).presentation, cornerRadius: 32, cornerStyle: .circular) {
                NicknameEditorView(model: model, presentation: $0)
            }
            .onChange(of: model.nicknameEditor.settingsRequest) { _, _ in openSettings() }
    }
}
