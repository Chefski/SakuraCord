import Foundation

nonisolated extension SettingsCatalog {
    static let interfacePage = page(
        .interface, group: .preferences, title: "Appearance", image: "circle.lefthalf.filled",
        help: "Choose message appearance, input bar icons, and timestamps.",
        keywords: ["messages", "bubbles", "density", "composer", "input bar", "clock", "timestamp"]
    )

    static let interfaceControls: [SettingsControlMetadata] = [
        control(
            .messageAppearance,
            page: .interface,
            section: .interfaceMessages,
            label: "Messages",
            help: "Choose SakuraCord's default message layout or conversation bubbles.",
            keywords: ["messages", "bubbles", "iMessage", "chat", "layout", "default"],
            scope: .appWideLocal
        ),
        control(
            .messageDensity,
            page: .interface,
            section: .interfaceMessages,
            label: "Density",
            help: "Adjust the vertical spacing between messages.",
            keywords: ["messages", "density", "spacing", "compact", "comfortable"],
            scope: .appWideLocal
        ),
        control(
            .composerBarAppearance,
            page: .interface,
            section: .interfaceInputBar,
            label: "Input bar",
            help: "Choose the current split input bar or SakuraCord's legacy unified input bar.",
            keywords: ["composer", "message input", "default", "legacy", "pill"],
            scope: .appWideLocal
        ),
        control(
            .resetMessageAppearance,
            page: .interface,
            section: .interfaceMessages,
            label: "Reset to Defaults",
            help: "Restore the default message layout and density without changing other Appearance settings.",
            keywords: ["messages", "defaults", "restore", "reset", "density"],
            scope: .appWideLocal,
            reset: .categoryAction
        ),
        control(
            .timestampFormat,
            page: .interface,
            section: .interfaceTime,
            label: "Timestamp format",
            help: "Use the locale-aware system clock or an explicit 12- or 24-hour clock.",
            keywords: ["clock", "time", "12 hour", "24 hour", "timestamp"],
            scope: .appWideLocal
        ),
        control(
            .timestampSeconds,
            page: .interface,
            section: .interfaceTime,
            label: "Show seconds",
            help: "Include seconds in message timestamps, including grouped messages.",
            keywords: ["clock seconds", "precise time", "grouped timestamp"],
            scope: .appWideLocal
        ),
        control(
            .alwaysShowTimestamps, page: .interface, section: .interfaceTime,
            label: "Always show timestamps", help: "Keep grouped message timestamps visible without hovering.",
            keywords: ["time", "hover", "grouped"], scope: .appWideLocal
        ),
        control(
            .composerIcons, page: .interface, section: .interfaceInputBar,
            label: "Input bar icons", help: "Drag icons to reorder them.",
            keywords: ["composer", "GIF", "sticker", "emoji", "reorder"], scope: .appWideLocal
        ),
    ]
}
