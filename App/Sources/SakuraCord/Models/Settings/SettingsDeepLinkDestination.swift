import Foundation

nonisolated struct SettingsDeepLinkDestination: Hashable, Sendable {
    let page: SettingsPageID
    var controlID: SettingsControlID?

    var metadata: SettingsPageMetadata { SettingsCatalog.foundation.page(page) }
    private var control: SettingsControlMetadata? {
        SettingsCatalog.foundation.controls.first { $0.id == controlID && $0.destination.page == page }
    }

    var title: String {
        switch controlID {
        case .composerBarAppearance: "Message Composer Appearance"
        case .messageAppearance: "Message Appearance"
        default: String(localized: control?.label ?? metadata.title)
        }
    }
    var section: SettingsSectionID? {
        control?.destination.section
    }

    var url: URL {
        let pageURL = URL(string: "https://sakuracord.app/settings")!.appendingPathComponent(page.deepLinkPath)
        guard let control else { return pageURL }
        return pageURL.appendingPathComponent(control.deepLinkPath)
    }

    static func parse(_ path: [Substring]) -> Self? {
        guard path.first == "settings", path.count >= 2,
              let page = SettingsPageID.allCases.first(where: { $0.deepLinkPath == path[1] })
        else { return nil }
        if path.count == 2 { return Self(page: page) }
        guard path.count == 3,
              let control = SettingsCatalog.foundation.controls.first(where: {
                  $0.destination.page == page && $0.deepLinkPath == path[2]
              })
        else { return nil }
        return Self(page: page, controlID: control.id)
    }
}

nonisolated extension SettingsControlMetadata {
    var deepLinkPath: String {
        // Keep published links and use the stable identifier for every other control.
        if id == .composerBarAppearance { return "composer" }
        return String(id.rawValue.split(separator: ".", maxSplits: 1).last ?? Substring(id.rawValue))
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
        case .importExport: "import-export"
        case .about: "about"
        }
    }
}
