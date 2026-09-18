import Foundation

nonisolated struct SettingsDeepLinkDestination: Hashable, Sendable {
    let page: SettingsPageID
    var controlID: SettingsControlID?

    var metadata: SettingsPageMetadata { SettingsCatalog.foundation.page(page) }
    var title: String {
        switch controlID {
        case .composerBarAppearance: "Message Composer Appearance"
        case .messageAppearance: "Message Appearance"
        default: String(localized: metadata.title)
        }
    }
    var section: SettingsSectionID? {
        SettingsCatalog.foundation.controls.first { $0.id == controlID }?.destination.section
    }

    static func parse(_ path: [Substring]) -> Self? {
        guard path.first == "settings", path.count >= 2,
              let page = SettingsPageID.allCases.first(where: { $0.deepLinkPath == path[1] })
        else { return nil }
        if path.count == 2 { return Self(page: page) }
        guard path.count == 3, page == .interface else { return nil }
        switch path[2] {
        case "composer": return Self(page: page, controlID: .composerBarAppearance)
        case "messages": return Self(page: page, controlID: .messageAppearance)
        default: return nil
        }
    }
}

nonisolated extension SettingsPageID {
    var deepLinkPath: String {
        switch self {
        case .profiles: "profiles"
        case .myAccount: "my-account"
        case .general: "general"
        case .interface: "appearance"
        case .appearance: "theme"
        case .notifications: "notifications"
        case .voiceVideo: "voice-video"
        case .accessibility: "accessibility"
        case .keyboardShortcuts: "keyboard-shortcuts"
        case .privacySafety: "privacy-safety"
        case .storageDownloads: "storage-downloads"
        case .diagnostics: "diagnostics"
        case .softwareUpdates: "software-updates"
        case .extensions: "extensions"
        case .about: "about"
        }
    }
}
