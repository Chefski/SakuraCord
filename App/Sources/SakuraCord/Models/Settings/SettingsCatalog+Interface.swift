import Foundation

nonisolated extension SettingsCatalog {
    static let interfacePage = page(
        .interface, group: .preferences, title: "Interface", image: "macwindow",
        help: "Choose message appearance, timestamps, grouping, links, member-list, and role presentation.",
        keywords: ["messages", "bubbles", "density", "composer", "input bar", "clock", "timestamp", "roles", "member list", "links", "grouping", "message actions"]
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
            section: .interfaceMessages,
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
            help: "Restore the default message layout, density, and input bar without changing other Interface settings.",
            keywords: ["messages", "defaults", "restore", "reset", "density", "input bar"],
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
            label: "Show seconds in full timestamps",
            help: "Include seconds in expanded message timestamps and their accessibility value.",
            keywords: ["clock seconds", "precise time", "expanded timestamp"],
            scope: .appWideLocal
        ),
        control(
            .groupingInterval,
            page: .interface,
            section: .interfaceTime,
            label: "Consecutive-message grouping",
            help: "Choose how many minutes consecutive messages from one author remain grouped.",
            keywords: ["group interval", "continuation", "author", "minutes"],
            scope: .appWideLocal
        ),
        control(
            .underlineLinks,
            page: .interface,
            section: .interfaceVisibility,
            label: "Underline links",
            help: "Underline links in message content in addition to using the system link color.",
            keywords: ["URL", "hyperlink", "decoration", "readability"],
            scope: .appWideLocal
        ),
        control(
            .showMemberList,
            page: .interface,
            section: .interfaceVisibility,
            label: "Show member list",
            help: "Show the member inspector for ordinary conversations.",
            keywords: ["members", "people", "inspector", "right sidebar"],
            scope: .appWideLocal
        ),
        control(
            .showActivityDetails,
            page: .interface,
            section: .interfaceVisibility,
            label: "Show activity and presence details",
            help: "Show member activity text and presence indicators in the member list.",
            keywords: ["presence", "status", "activity", "game", "member details"],
            scope: .appWideLocal
        ),
        control(
            .messageActionVisibility,
            page: .interface,
            section: .interfaceVisibility,
            label: "Message actions",
            help: "Reveal message actions on hover or keep an action affordance visible.",
            keywords: ["hover", "always visible", "reply", "reaction", "toolbar"],
            scope: .appWideLocal
        ),
        control(
            .showRoleColors,
            page: .interface,
            section: .interfaceVisibility,
            label: "Show Discord role colors",
            help: "Use role colors for member and message author names when Discord provides them.",
            keywords: ["roles", "author color", "member color", "Discord color"],
            scope: .appWideLocal
        ),
        control(
            .interfacePreview,
            page: .interface,
            section: .interfacePreview,
            label: "Interface preview",
            help: "Preview sidebar and message presentation without using Discord data.",
            keywords: ["sample", "live preview", "appearance"],
            owner: .appModel,
            scope: .appWideLocal,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
        control(
            .exportInterfaceSettings,
            page: .interface,
            section: .interfaceLocalData,
            label: "Export Interface Settings",
            help: "Export registered Interface preferences as versioned JSON.",
            keywords: ["backup", "JSON", "save preferences"],
            scope: .appWideLocal,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
        control(
            .resetInterfaceSettings,
            page: .interface,
            section: .interfaceLocalData,
            label: "Reset Interface Settings",
            help: "Restore registered Interface preferences without changing credentials or Discord state.",
            keywords: ["defaults", "restore", "clear interface preferences"],
            scope: .appWideLocal,
            persistence: .appPreferences,
            reset: .categoryAction
        ),
    ]
}
