import Foundation

nonisolated extension SettingsCatalog {
    static let privacySafetyPage = page(
        .privacySafety, group: .dataSecurity, title: "Privacy", image: "hand.raised",
        help: "Control local privacy, external links, and scoped data clearing.",
        keywords: ["links", "security", "typing indicators", "read receipts", "clear data"]
    )

    static let privacySafetyControls: [SettingsControlMetadata] = [
        control(
            .privacyTypingIndicators, page: .privacySafety,
            section: .privacyDiscordActivity, label: "Send Typing Indicators",
            help: "Send Discord typing events while composing.",
            keywords: ["typing status", "Discord", "composer"],
            scope: .appWideLocal, persistence: .appPreferences, reset: .notApplicable
        ),
        control(
            .privacyReadAcknowledgements, page: .privacySafety,
            section: .privacyDiscordActivity, label: "Automatically Mark Messages as Read",
            help: "Acknowledge visible messages automatically; turn this off to require an explicit Mark Read action.",
            keywords: ["read receipt", "unread", "manual", "automatic"], owner: .appModel,
            scope: .mixed, persistence: .appPreferences, reset: .notApplicable
        ),
        control(
            .externalLinkProtection, page: .privacySafety,
            section: .privacyLinksServices,
            label: "Ask Permission When Opening External Links",
            help: "Choose whether SakuraCord asks before opening untrusted domains, all external links, or no external links.",
            keywords: ["URL", "domain", "phishing", "warning", "browser", "confirm"],
            scope: .appWideLocal, persistence: .appPreferences,
            reset: .registeredLocalValue
        ),
        control(
            .trustedDomains, page: .privacySafety,
            section: .privacyLinksServices, label: "Manage Trusted Domains",
            help: "Search, add, or remove exact domains that can open without confirmation under the default policy.",
            keywords: ["URL", "domain", "allow list", "trusted", "browser"],
            scope: .appWideLocal, persistence: .appPreferences,
            reset: .registeredLocalValue
        ),
        control(
            .clearLocalActivity, page: .privacySafety,
            section: .privacyLocalData, label: "Clear Local Activity",
            help: "Clear the current account's recent Quick Switch and forwarding destinations plus app-wide local emoji recents and learned usage.",
            keywords: ["history", "frecency", "forward", "quick switch", "recent emoji", "learning"],
            owner: .appModel, scope: .accountAndAppWideLocal,
            persistence: .notApplicable, reset: .categoryAction
        ),
    ]
}
