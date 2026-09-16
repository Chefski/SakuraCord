import SwiftUI

struct KeyboardShortcutsSettingsPage: View {
    private struct Conflict: Identifiable {
        let action: KeyboardShortcutAction
        let existingAction: KeyboardShortcutAction
        let shortcut: KeyboardShortcutChord
        var id: String { "\(action.rawValue):\(existingAction.rawValue)" }
    }

    let state: SettingsViewState
    private let shortcuts = KeyboardShortcutSettingsStore.shared
    @State private var validationError: String?
    @State private var conflict: Conflict?
    @State private var showsResetConfirmation = false

    private var isUsingDefaults: Bool {
        KeyboardShortcutAction.allCases.allSatisfy {
            shortcuts.shortcut(for: $0) == $0.defaultShortcut
        }
    }

    var body: some View {
        SettingsPageForm(page: .keyboardShortcuts, state: state) {
            ForEach(KeyboardShortcutGroup.allCases) { group in
                shortcutSection(group)
            }
            resetSection
        }
        .alert(
            "Shortcut Already Used",
            isPresented: Binding(
                get: { conflict != nil },
                set: { if !$0 { conflict = nil } }
            ),
            presenting: conflict
        ) { conflict in
            Button("Replace \(conflict.existingAction.localizedTitle)") {
                replaceConflict(conflict)
            }
            Button("Cancel", role: .cancel) {
                self.conflict = nil
            }
        } message: { conflict in
            Text("\(conflict.shortcut.displayName) is assigned to \(conflict.existingAction.localizedTitle). Replacing it will clear that action and assign it to \(conflict.action.localizedTitle).")
        }
        .alert(
            "Shortcut Unavailable",
            isPresented: Binding(
                get: { validationError != nil },
                set: { if !$0 { validationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationError ?? "")
        }
        .settingsResetConfirmation(
            "Reset All Keyboard Shortcuts?",
            isPresented: $showsResetConfirmation,
            resetTitle: "Reset All Shortcuts",
            message: "This resets all of SakuraCord's keyboard shortcuts. Are you sure you want to do this?",
            reset: shortcuts.resetAll
        )
    }

    private func shortcutSection(_ group: KeyboardShortcutGroup) -> some View {
        Section {
            ForEach(actions(in: group)) { action in
                shortcutRow(action)
            }
        } header: {
            Text(group.title)
        }
    }

    private func shortcutRow(_ action: KeyboardShortcutAction) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(action.title)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                KeyboardShortcutRecorder(
                    actionTitle: action.localizedTitle,
                    shortcut: shortcuts.shortcut(for: action),
                    capture: { assign($0, to: action) },
                    clear: { shortcuts.set(nil, for: action) },
                    cancel: {}
                )
                .frame(width: 142, height: 32)

                Button {
                    assign(action.defaultShortcut, to: action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset \(action.localizedTitle)")
                .accessibilityLabel("Reset \(action.localizedTitle)")
            }
        }
        .settingsControlAnchor(action.controlID, state: state)
    }

    private var resetSection: some View {
        Section {
            Button("Reset All…", role: .destructive) {
                showsResetConfirmation = true
            }
            .disabled(isUsingDefaults)
            .settingsControlAnchor(.shortcutReset, state: state)
        }
    }

    private func actions(
        in group: KeyboardShortcutGroup
    ) -> [KeyboardShortcutAction] {
        KeyboardShortcutAction.allCases.filter { $0.group == group }
    }

    private func assign(
        _ shortcut: KeyboardShortcutChord?,
        to action: KeyboardShortcutAction
    ) {
        switch shortcuts.set(shortcut, for: action) {
        case .valid:
            break
        case let .conflict(existingAction):
            guard let shortcut else { return }
            conflict = Conflict(
                action: action,
                existingAction: existingAction,
                shortcut: shortcut
            )
        case let .invalid(message):
            validationError = message
        }
    }

    private func replaceConflict(_ conflict: Conflict) {
        shortcuts.set(nil, for: conflict.existingAction)
        self.conflict = nil
        assign(conflict.shortcut, to: conflict.action)
    }

}
