import Foundation

nonisolated extension SettingsCatalog {
    static let generalPage = page(
        .general, group: .preferences, title: "General", image: "gearshape",
        help: "Choose startup, restoration, and confirmation behavior.",
        keywords: ["startup", "launch", "restore", "confirmation", "quit"]
    )

    static let generalControls: [SettingsControlMetadata] = [
        control(
            .launchAtLogin,
            page: .general,
            section: .startupRestoration,
            label: "Launch at Login",
            help: "Ask macOS to launch SakuraCord after this user logs in.",
            keywords: ["startup", "login item", "open automatically", "Service Management"],
            owner: .macOS,
            scope: .appWideLocal,
            persistence: .systemManaged,
            reset: .notApplicable
        ),
        control(
            .launchDestination,
            page: .general,
            section: .startupRestoration,
            label: "Launch destination",
            help: "Choose which account and safely restored conversation SakuraCord opens at launch.",
            keywords: ["last conversation", "last location", "account picker", "startup page"],
            scope: .appWideLocal
        ),
        control(
            .showMainWindowAtLaunch,
            page: .general,
            section: .startupRestoration,
            label: "Show the main window at launch",
            help: "Present SakuraCord's main window immediately when the app launches.",
            keywords: ["background", "hidden", "window", "Dock"],
            scope: .appWideLocal
        ),
        control(
            .rememberMemberListVisibility,
            page: .general,
            section: .startupRestoration,
            label: "Remember member list visibility",
            help: "Restore whether the conversation member list was visible when SakuraCord last quit.",
            keywords: ["inspector", "members", "sidebar", "restore"],
            scope: .appWideLocal
        ),
        control(
            .confirmQuitActiveWork,
            page: .general,
            section: .confirmations,
            label: "Confirm quitting during active work",
            help: "Ask before quitting during a call, screen share, or active upload.",
            keywords: ["quit warning", "call", "screen share", "upload"],
            scope: .appWideLocal
        ),
        control(
            .confirmDiscardComposer,
            page: .general,
            section: .confirmations,
            label: "Confirm discarding composer changes",
            help: "Ask before discarding meaningful unsent attachments, command input, or edited message text.",
            keywords: ["draft", "unsent", "edit", "discard warning", "attachments"],
            scope: .appWideLocal
        ),
    ]
}
