import Foundation

nonisolated extension SettingsCatalog {
    static let softwareUpdatesPage = page(
        .softwareUpdates, group: .sakuraCord, title: "Updates", image: "arrow.triangle.2.circlepath",
        help: "Manage signed SakuraCord update checks, downloads, and release tracks.",
        keywords: ["update", "release", "regular", "nightly", "Sparkle", "version"]
    )

    static let softwareUpdatesControls: [SettingsControlMetadata] = [
        control(
            .updateReleaseTrack,
            page: .softwareUpdates,
            section: .softwareUpdates,
            label: "Release track",
            help: "Choose the signed Regular or Nightly update feed.",
            keywords: ["regular", "nightly", "channel"],
            scope: .appWideLocal,
            reset: .categoryAction
        ),
        control(
            .updateAutomaticChecks,
            page: .softwareUpdates,
            section: .softwareUpdates,
            label: "Automatically check for updates",
            help: "Let SakuraCord periodically check its configured signed feed.",
            keywords: ["scheduled", "Sparkle"],
            owner: .sparkle,
            scope: .appWideLocal,
            persistence: .systemManaged,
            reset: .categoryAction
        ),
        control(
            .updateAutomaticDownloads,
            page: .softwareUpdates,
            section: .softwareUpdates,
            label: "Automatically download updates",
            help: "Download verified updates when Sparkle allows automatic updates.",
            keywords: ["download", "Sparkle"],
            owner: .sparkle,
            scope: .appWideLocal,
            persistence: .systemManaged,
            reset: .categoryAction
        ),
        control(
            .checkForUpdates,
            page: .softwareUpdates,
            section: .softwareUpdates,
            label: "Check for Updates",
            help: "Ask the existing updater to check now.",
            keywords: ["update now", "new version"],
            owner: .sparkle,
            scope: .appWideLocal,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
        control(
            .updateChangelog,
            page: .softwareUpdates,
            section: .softwareUpdates,
            label: "Open Changelog",
            help: "Show the release notes included with SakuraCord.",
            keywords: ["release notes", "version history"],
            scope: .appWideLocal,
            persistence: .notApplicable,
            reset: .notApplicable
        ),
    ]
}
