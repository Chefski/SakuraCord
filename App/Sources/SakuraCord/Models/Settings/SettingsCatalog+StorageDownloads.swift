import Foundation

nonisolated extension SettingsCatalog {
    static let storageDownloadsPage = page(
        .storageDownloads, group: .dataSecurity, title: "Storage & Downloads", image: "internaldrive",
        help: "Manage media cache, downloads, drafts, and SakuraCord-owned temporary files.",
        keywords: ["cache", "disk", "folder", "downloads", "drafts", "clear cache"]
    )

    static let storageDownloadsControls: [SettingsControlMetadata] = [
        control(
            .localStorageLimit,
            page: .storageDownloads,
            section: .localStorage,
            label: "Local Storage Limit",
            help: "Set the shared maximum size for drafts and disposable media.",
            keywords: ["disk", "storage", "limit", "drafts", "media"],
            scope: .appWideLocal
        ),
        control(
            .localStorageUsage, page: .storageDownloads, section: .localStorage,
            label: "Local Storage Usage",
            help: "Measure the combined space used by drafts and disposable media.",
            keywords: ["bytes", "size", "drafts", "media"], owner: .appModel,
            scope: .appWideLocal, persistence: .sessionOnly, reset: .notApplicable
        ),
        control(
            .mediaCacheClear, page: .storageDownloads, section: .localStorage,
            label: "Clear Media Cache",
            help: "Clear disposable disk media after confirmation without removing visible in-memory media.",
            keywords: ["delete", "purge", "free space"], owner: .appModel,
            scope: .appWideLocal, persistence: .notApplicable, reset: .categoryAction
        ),
        control(
            .downloadFolderName, page: .storageDownloads,
            section: .storageDownloads, label: "Default Download Folder",
            help: "Choose the sandbox-authorized default folder used by direct media saves.",
            keywords: ["directory", "location", "choose"], owner: .macOS,
            scope: .appWideLocal, persistence: .appPreferences,
            reset: .categoryAction
        ),
        control(
            .revealCompletedDownloads, page: .storageDownloads,
            section: .storageDownloads, label: "Reveal Completed Downloads",
            help: "Select successfully saved media in Finder.",
            keywords: ["Finder", "show", "completed"], scope: .appWideLocal
        ),
        control(
            .clearAllAccountDrafts, page: .storageDownloads,
            section: .localStorage, label: "Clear Drafts",
            help: "Delete local drafts for every saved account after confirmation and return their allocation to the media cache.",
            keywords: ["delete", "unsent", "all accounts"], owner: .appModel,
            scope: .mixed, persistence: .notApplicable, reset: .categoryAction
        ),
    ]
}
