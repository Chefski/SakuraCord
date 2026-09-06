import AppKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @ObservedObject var updateController: AppUpdateController

    @Environment(\.locale) private var locale
    @Environment(\.colorSchemeContrast) private var systemColorSchemeContrast
    @SceneStorage("settings.selected-account") private var storedSelectedAccount = ""
    @State private var state = SettingsViewState()
    @State private var launchAtLogin = LaunchAtLoginController()
    @State private var isSearchPresented = false
    @State private var profileEditor: ProfileEditorState?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let navigationRouter = SettingsNavigationRouter.shared

    var body: some View {
        @Bindable var state = state
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebar(
                state: state,
                onSearchResultActivated: dismissSearchFocus
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            SettingsDetailRouter(
                model: model,
                updateController: updateController,
                state: state,
                launchAtLogin: launchAtLogin,
                selectedAccountID: $storedSelectedAccount,
                profileEditor: profileEditor
            )
            .modifier(
                SettingsContrastModifier(
                    isEnabled: model.accessibilitySettings.increasesContrast
                        && systemColorSchemeContrast == .standard
                )
            )
        }
        .searchable(
            text: $state.searchText,
            isPresented: $isSearchPresented,
            placement: .sidebar,
            prompt: LocalizedStringResource(
                "Search Settings",
                bundle: #bundle,
                comment: "Prompt for the Settings sidebar search field."
            )
        )
        .background {
            ZStack {
                SakuraCordThemeBackground()
                    .ignoresSafeArea()
                SakuraCordTextInputAccentBridge()
            }
        }
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleSearchKeyPress(press)
        }
        .task {
            state.updateLocale(locale)
            if profileEditor == nil { profileEditor = ProfileEditorState(model: model) }
            let navigationEditor = profileEditor
            state.allowsNavigation = { [weak navigationEditor] destination in
                guard let profileEditor = navigationEditor, profileEditor.hasChanges || profileEditor.isSaving else { return true }
                guard destination != .profiles else { return true }
                profileEditor.showsUnsavedReminder = true
                return false
            }
        }
        .windowResizeBehavior(.enabled)
        .windowMinimizeBehavior(.disabled)
        .dismissalConfirmationDialog("Profile Changes", shouldPresent: profileEditor?.hasChanges == true || profileEditor?.isSaving == true) {
            if profileEditor?.isSaving != true {
                Button("Discard Changes", role: .destructive) { profileEditor?.resetDraft() }
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(profileEditor?.isSaving == true ? "Wait for your profile changes to finish saving." : "Your profile has unsaved changes.", bundle: #bundle)
        }
        .task(id: navigationRouter.request?.id) {
            guard let request = navigationRouter.request else { return }
            state.navigate(
                to: request.destination,
                controlID: request.controlID
            )
            navigationRouter.consume(request.id)
        }
        .onChange(of: locale) { _, locale in
            state.updateLocale(locale)
        }
        .frame(
            minWidth: 760,
            idealWidth: 980,
            minHeight: 520,
            idealHeight: 700
        )
    }

    private func dismissSearchFocus() {
        isSearchPresented = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func handleSearchKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard isSearchPresented else { return .ignored }
        switch press.key {
        case .escape:
            state.searchText = ""
            dismissSearchFocus()
            return .handled
        case .return:
            guard state.activateSelectedSearchResult() else { return .ignored }
            dismissSearchFocus()
            return .handled
        case .downArrow:
            guard !state.searchText.isEmpty else { return .ignored }
            state.moveSearchSelection(by: 1)
            return .handled
        case .upArrow:
            guard !state.searchText.isEmpty else { return .ignored }
            state.moveSearchSelection(by: -1)
            return .handled
        default:
            guard press.modifiers.contains(.control) else { return .ignored }
            switch press.characters.lowercased() {
            case "n":
                state.moveSearchSelection(by: 1)
                return .handled
            case "p":
                state.moveSearchSelection(by: -1)
                return .handled
            default:
                return .ignored
            }
        }
    }
}

private struct SettingsContrastModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.contrast(1.12)
        } else {
            content
        }
    }
}

private struct SettingsDetailRouter: View {
    let model: AppModel
    @ObservedObject var updateController: AppUpdateController
    let state: SettingsViewState
    let launchAtLogin: LaunchAtLoginController
    @Binding var selectedAccountID: String
    let profileEditor: ProfileEditorState?

    var body: some View {
        switch state.selectedPage {
        case .myAccount:
            MyAccountSettingsPage(
                model: model,
                state: state,
                selectedAccountID: $selectedAccountID
            )
        case .profiles:
            if let profileEditor { ProfilesSettingsPage(model: model, state: state, editor: profileEditor) } else { ProgressView() }
        case .general:
            GeneralSettingsPage(
                model: model,
                state: state,
                launchAtLogin: launchAtLogin
            )
        case .appearance:
            AppearanceSettingsPage(model: model, state: state)
        case .interface:
            InterfaceSettingsPage(model: model, state: state)
        case .chat:
            ChatSettingsPage(model: model, state: state)
        case .notifications:
            NotificationsSettingsPage(model: model, state: state)
        case .voiceVideo:
            VoiceVideoSettingsPage(model: model, state: state)
        case .accessibility:
            AccessibilitySettingsPage(model: model, state: state)
        case .keyboardShortcuts:
            KeyboardShortcutsSettingsPage(state: state)
        case .privacySafety:
            PrivacySafetySettingsPage(model: model, state: state)
        case .storageDownloads:
            StorageDownloadsSettingsPage(model: model, state: state)
        case .diagnostics:
            DiagnosticsSettingsPage(
                model: model,
                updateController: updateController,
                state: state
            )
        case .softwareUpdates:
            SoftwareUpdatesSettingsPage(
                updateController: updateController,
                state: state
            )
        case .extensions:
            ExtensionsSettingsPage(state: state)
        case .about:
            AboutSettingsPage(
                updateController: updateController,
                state: state
            )
        }
    }
}
