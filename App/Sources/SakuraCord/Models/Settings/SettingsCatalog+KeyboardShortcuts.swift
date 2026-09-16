import Foundation

nonisolated extension SettingsCatalog {
    static let keyboardShortcutsPage = page(
        .keyboardShortcuts, group: .preferences, title: "Keyboard Shortcuts", image: "keyboard",
        help: "Review and customize SakuraCord keyboard commands.",
        keywords: ["keys", "bindings", "hotkeys", "commands", "recorder"]
    )

    static let keyboardShortcutsControls: [SettingsControlMetadata] = KeyboardShortcutAction.allCases.map { action in
        SettingsControlMetadata(
            id: action.controlID,
            destination: SettingsDestination(
                page: .keyboardShortcuts,
                section: action.group.settingsSection
            ),
            label: action.title,
            help: action.help,
            keywords: action.keywords,
            owner: .applicationPreferences,
            scope: .appWideLocal,
            persistence: .appPreferences,
            resetCapability: .registeredLocalValue,
            availability: .available
        )
    } + [
        control(
            .shortcutReset, page: .keyboardShortcuts,
            section: .shortcutLocalData, label: "Reset All Keyboard Shortcuts",
            help: "Restore every shortcut to SakuraCord's defaults.",
            keywords: ["defaults", "restore", "clear shortcuts"], scope: .appWideLocal,
            persistence: .appPreferences, reset: .categoryAction
        ),
    ]
}
