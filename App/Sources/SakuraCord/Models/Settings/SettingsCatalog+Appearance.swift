import Foundation

nonisolated extension SettingsCatalog {
    static let appearancePage = page(
        .appearance, group: .preferences, title: "Theme", image: "paintbrush.fill",
        help: "Choose how SakuraCord's interface looks.",
        keywords: ["appearance", "look", "style", "accent", "color", "theme"]
    )

    static let appearanceControls: [SettingsControlMetadata] = [
        control(
            .appColorScheme,
            page: .appearance,
            section: .appearanceTheme,
            label: "Appearance",
            help: "Follow the system appearance or choose SakuraCord's light or dark appearance.",
            keywords: ["appearance", "theme", "system", "light", "dark", "mode", "sun", "moon"],
            scope: .appWideLocal
        ),
        control(
            .themeDesigner,
            page: .appearance,
            section: .appearanceTheme,
            label: "Theme Designer",
            help: "Create a theme with color, intensity, brightness, and randomisation controls.",
            keywords: ["gradient", "theme", "designer", "color", "intensity", "brightness", "randomise"],
            scope: .appWideLocal
        ),
    ]
}
