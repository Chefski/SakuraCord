import Foundation

nonisolated extension SettingsCatalog {
    static let profilesPage = page(
        .profiles, group: .account, title: "Edit Profile", image: "square.and.pencil.circle.fill",
        help: "Customize your active Discord account's main and per-server profiles.",
        keywords: ["profile", "avatar", "banner", "nameplate", "decoration", "font", "display name", "bio", "pronouns", "server profile", "profile effect", "frame", "gradient", "Nitro"]
    )

    static let myAccountPage = page(
        .myAccount, group: .account, title: "Manage Accounts", image: "person.crop.circle",
        help: "Manage saved Discord accounts and choose which account opens at launch.",
        keywords: ["account", "profile", "login", "logout", "switch account"]
    )

    static let myAccountControls: [SettingsControlMetadata] = [
        control(
            .selectedAccount,
            page: .myAccount,
            section: .accountIdentity,
            label: "Saved account",
            help: "Choose a saved account to switch to or remove.",
            keywords: ["selected account", "inspect", "profile", "saved account"],
            owner: .accountPreferences,
            scope: .accountLocal,
            persistence: .sessionOnly,
            reset: .notApplicable
        ),
        control(
            .switchAccount,
            page: .myAccount,
            section: .accountIdentity,
            label: "Switch to Account",
            help: "Replace the active workspace with the selected saved Discord session.",
            keywords: ["activate", "change account", "connect"],
            owner: .appModel,
            scope: .discordSynchronized,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
        control(
            .addAccount,
            page: .myAccount,
            section: .accountIdentity,
            label: "Add Account",
            help: "Open SakuraCord's existing Discord authentication flow.",
            keywords: ["login", "sign in", "QR", "another account"],
            owner: .appModel,
            scope: .discordSynchronized,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
        control(
            .reopenLastAccount,
            page: .myAccount,
            section: .accountLaunch,
            label: "Reopen the last active account",
            help: "Reconnect the account that was active most recently when SakuraCord launches.",
            keywords: ["startup", "launch", "restore", "last used"],
            scope: .appWideLocal
        ),
        control(
            .preferredLaunchAccount,
            page: .myAccount,
            section: .accountLaunch,
            label: "Preferred launch account",
            help: "Choose a fixed saved account to reconnect when SakuraCord launches.",
            keywords: ["startup account", "default account", "preferred account"],
            scope: .appWideLocal
        ),
        control(
            .removeSavedSession,
            page: .myAccount,
            section: .accountIdentity,
            label: "Log Out or Remove Saved Account",
            help: "Remove the selected account's saved session from macOS Keychain; an active account is disconnected first.",
            keywords: ["sign out", "disconnect", "forget account", "delete login", "Keychain"],
            owner: .appModel,
            scope: .mixed,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
    ]
}
