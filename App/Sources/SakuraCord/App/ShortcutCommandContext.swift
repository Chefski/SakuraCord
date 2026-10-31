import SwiftUI

/// Commands follow the key scene rather than the app's shared workspace model.
enum ShortcutCommandContext {
    case workspace(AppModel)
    case settings(model: AppModel, focusSearch: () -> Void)

    var allowsWorkspaceNavigation: Bool {
        guard case let .workspace(model) = self else { return false }
        return model.sessionState == .workspace
    }

    func isEnabled(_ action: KeyboardShortcutAction) -> Bool {
        switch self {
        case let .workspace(model): model.keyboardShortcutActionIsEnabled(action)
        case let .settings(model, _):
            action.group == .interface
                ? model.keyboardShortcutActionIsEnabled(action)
                : action == .messageSearch || action == .searchCurrentConversation
        }
    }

    func perform(_ action: KeyboardShortcutAction) {
        guard isEnabled(action) else { return }
        switch self {
        case let .workspace(model): model.performKeyboardShortcutAction(action)
        case let .settings(model, focusSearch):
            if action.group == .interface {
                model.performKeyboardShortcutAction(action)
            } else {
                focusSearch()
            }
        }
    }

    func navigate(to number: Int) {
        guard allowsWorkspaceNavigation, case let .workspace(model) = self else { return }
        model.navigateUsingShortcut(number)
    }
}

private struct ShortcutCommandContextKey: FocusedValueKey {
    typealias Value = ShortcutCommandContext
}

extension FocusedValues {
    var shortcutCommandContext: ShortcutCommandContext? {
        get { self[ShortcutCommandContextKey.self] }
        set { self[ShortcutCommandContextKey.self] = newValue }
    }
}
