import Foundation

nonisolated enum SettingsPageID: String, CaseIterable, Codable, Identifiable, Sendable {
    case profiles
    case myAccount
    case general
    case interface
    case appearance
    case chat
    case notifications
    case voiceVideo
    case accessibility
    case keyboardShortcuts
    case privacySafety
    case storageDownloads
    case diagnostics
    case softwareUpdates
    case extensions
    case about

    var id: String { rawValue }
}

nonisolated enum SettingsSidebarGroupID: String, CaseIterable, Identifiable, Sendable {
    case account
    case preferences
    case dataSecurity
    case sakuraCord

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .account:
            LocalizedStringResource("Account", bundle: #bundle)
        case .preferences:
            LocalizedStringResource("Preferences", bundle: #bundle)
        case .dataSecurity:
            LocalizedStringResource("Data & Security", bundle: #bundle)
        case .sakuraCord:
            LocalizedStringResource("SakuraCord", bundle: #bundle)
        }
    }
}

nonisolated struct SettingsSectionID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

nonisolated struct SettingsControlID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

nonisolated struct SettingsDestination: Hashable, Codable, Sendable {
    let page: SettingsPageID
    let section: SettingsSectionID?

    init(page: SettingsPageID, section: SettingsSectionID? = nil) {
        self.page = page
        self.section = section
    }
}

nonisolated enum SettingsValueScope: String, Codable, Sendable {
    case appWideLocal
    case accountLocal
    case accountAndAppWideLocal
    case discordSynchronized
    case mixed

    var title: LocalizedStringResource {
        switch self {
        case .appWideLocal:
            LocalizedStringResource(
                "App-wide on this Mac",
                bundle: #bundle,
                comment: "Settings scope label for a preference shared by all accounts on this Mac."
            )
        case .accountLocal:
            LocalizedStringResource(
                "Selected account on this Mac",
                bundle: #bundle,
                comment: "Settings scope label for a local preference belonging to one account."
            )
        case .accountAndAppWideLocal:
            LocalizedStringResource(
                "Selected account and app-wide on this Mac",
                bundle: #bundle,
                comment: "Settings scope label for an action affecting both the selected account and app-wide local data."
            )
        case .discordSynchronized:
            LocalizedStringResource(
                "Synchronized by Discord",
                bundle: #bundle,
                comment: "Settings scope label for a preference stored by Discord."
            )
        case .mixed:
            LocalizedStringResource(
                "Local and Discord-controlled",
                bundle: #bundle,
                comment: "Settings scope label for a page containing both local and Discord-controlled values."
            )
        }
    }
}

nonisolated enum SettingsResetCapability: String, Codable, Sendable {
    case registeredLocalValue
    case categoryAction
    case notApplicable
}

nonisolated enum SettingsValueOwner: String, Codable, Sendable {
    case applicationPreferences
    case accountPreferences
    case appModel
    case macOS
    case sparkle
    case discord
}

nonisolated enum SettingsPersistence: String, Codable, Sendable {
    case appPreferences
    case accountPreferences
    case sessionOnly
    case systemManaged
    case discordManaged
    case notApplicable
}

nonisolated enum SettingsAvailability: Equatable, Sendable {
    case available
    case unavailable(LocalizedStringResource)
}

nonisolated struct SettingsPageMetadata: Identifiable, Sendable {
    let id: SettingsPageID
    let group: SettingsSidebarGroupID
    let title: LocalizedStringResource
    let systemImage: String
    let help: LocalizedStringResource
    let keywords: [LocalizedStringResource]
    let overviewControlID: SettingsControlID
}

nonisolated struct SettingsControlMetadata: Identifiable, Sendable {
    let id: SettingsControlID
    let destination: SettingsDestination
    let label: LocalizedStringResource
    let help: LocalizedStringResource
    let keywords: [LocalizedStringResource]
    let owner: SettingsValueOwner
    let scope: SettingsValueScope
    let persistence: SettingsPersistence
    let resetCapability: SettingsResetCapability
    let availability: SettingsAvailability
}

nonisolated struct SettingsCatalog: Sendable {
    let pages: [SettingsPageMetadata]
    let controls: [SettingsControlMetadata]

    static let foundation = SettingsCatalog(
        pages: SettingsCatalog.foundationPages,
        controls: SettingsCatalog.foundationControls
    )

    func page(_ id: SettingsPageID) -> SettingsPageMetadata {
        pages.first { $0.id == id } ?? pages[0]
    }

    func pages(in group: SettingsSidebarGroupID) -> [SettingsPageMetadata] {
        pages.filter { $0.group == group }
    }
}

nonisolated extension SettingsSectionID {
    static let accountIdentity = Self(rawValue: "account-identity")
    static let accountLaunch = Self(rawValue: "account-launch")
    static let accountLocalData = Self(rawValue: "account-local-data")
    static let startupRestoration = Self(rawValue: "startup-restoration")
    static let confirmations = Self(rawValue: "confirmations")
    static let appearanceTheme = Self(rawValue: "appearance-theme")
    static let interfaceMessages = Self(rawValue: "interface-messages")
    static let interfaceTime = Self(rawValue: "interface-time")
    static let interfaceVisibility = Self(rawValue: "interface-visibility")
    static let interfacePreview = Self(rawValue: "interface-preview")
    static let interfaceLocalData = Self(rawValue: "interface-local-data")
    static let chatComposer = Self(rawValue: "chat-composer")
    static let chatMessages = Self(rawValue: "chat-messages")
    static let chatMedia = Self(rawValue: "chat-media")
    static let chatEmoji = Self(rawValue: "chat-emoji")
    static let chatLocalData = Self(rawValue: "chat-local-data")
    static let softwareUpdates = Self(rawValue: "software-updates")
    static let notificationDelivery = Self(rawValue: "notification-delivery")
    static let notificationEvents = Self(rawValue: "notification-events")
    static let notificationQuietHours = Self(rawValue: "notification-quiet-hours")
    static let notificationLocalData = Self(rawValue: "notification-local-data")
    static let voiceDevices = Self(rawValue: "voice-devices")
    static let voiceLevels = Self(rawValue: "voice-levels")
    static let voiceCallDefaults = Self(rawValue: "voice-call-defaults")
    static let voiceCamera = Self(rawValue: "voice-camera")
    static let voiceScreenShare = Self(rawValue: "voice-screen-share")
    static let voicePermissions = Self(rawValue: "voice-permissions")
    static let voiceLocalData = Self(rawValue: "voice-local-data")
    static let accessibilityMotion = Self(rawValue: "accessibility-motion")
    static let accessibilityReadability = Self(rawValue: "accessibility-readability")
    static let accessibilityVoiceOver = Self(rawValue: "accessibility-voiceover")
    static let accessibilityLocalData = Self(rawValue: "accessibility-local-data")
    static let shortcutNavigation = Self(rawValue: "shortcut-navigation")
    static let shortcutMessaging = Self(rawValue: "shortcut-messaging")
    static let shortcutVoiceVideo = Self(rawValue: "shortcut-voice-video")
    static let shortcutLocalData = Self(rawValue: "shortcut-local-data")
    static let privacyDiscordActivity = Self(rawValue: "privacy-discord-activity")
    static let privacyLinksServices = Self(rawValue: "privacy-links-services")
    static let privacyLocalData = Self(rawValue: "privacy-local-data")
    static let localStorage = Self(rawValue: "local-storage")
    static let storageDownloads = Self(rawValue: "storage-downloads")
    static let diagnosticsStatus = Self(rawValue: "diagnostics-status")
    static let diagnosticsSupport = Self(rawValue: "diagnostics-support")
    static let apiDiagnostics = Self(rawValue: "api-diagnostics")
    static let aboutVersion = Self(rawValue: "about-version")
    static let aboutLinks = Self(rawValue: "about-links")
    static let aboutAcknowledgements = Self(rawValue: "about-acknowledgements")
    static let aboutLegal = Self(rawValue: "about-legal")
}

nonisolated extension SettingsControlID {
    static func overview(_ page: SettingsPageID) -> Self {
        Self(rawValue: "\(page.rawValue).overview")
    }

    static let selectedAccount = Self(rawValue: "my-account.selected-account")
    static let switchAccount = Self(rawValue: "my-account.switch-account")
    static let addAccount = Self(rawValue: "my-account.add-account")
    static let reopenLastAccount = Self(rawValue: "my-account.reopen-last-account")
    static let preferredLaunchAccount = Self(rawValue: "my-account.preferred-launch-account")
    static let removeSavedSession = Self(rawValue: "my-account.remove-saved-session")
    static let exportAccountPreferences = Self(rawValue: "my-account.export-preferences")
    static let resetAccountPreferences = Self(rawValue: "my-account.reset-preferences")
    static let launchAtLogin = Self(rawValue: "general.launch-at-login")
    static let launchDestination = Self(rawValue: "general.launch-destination")
    static let showMainWindowAtLaunch = Self(rawValue: "general.show-main-window")
    static let rememberMemberListVisibility = Self(rawValue: "general.remember-member-list")
    static let confirmQuitActiveWork = Self(rawValue: "general.confirm-quit-active-work")
    static let confirmDiscardComposer = Self(rawValue: "general.confirm-discard-composer")
    static let appColorScheme = Self(rawValue: "appearance.color-scheme")
    static let legacyAccentColorMigration = Self(rawValue: "appearance.accent-color")
    static let themeDesigner = Self(rawValue: "appearance.theme-designer")
    static let composerBarAppearance = Self(rawValue: "appearance.composer-bar")
    static let messageAppearance = Self(rawValue: "appearance.messages")
    static let messageDensity = Self(rawValue: "appearance.message-density")
    static let resetMessageAppearance = Self(rawValue: "interface.reset-message-appearance")
    static let timestampFormat = Self(rawValue: "interface.timestamp-format")
    static let timestampSeconds = Self(rawValue: "interface.timestamp-seconds")
    static let groupingInterval = Self(rawValue: "interface.grouping-interval")
    static let underlineLinks = Self(rawValue: "interface.underline-links")
    static let showMemberList = Self(rawValue: "interface.show-member-list")
    static let showActivityDetails = Self(rawValue: "interface.show-activity-details")
    static let messageActionVisibility = Self(rawValue: "interface.message-actions")
    static let showRoleColors = Self(rawValue: "interface.show-role-colors")
    static let interfacePreview = Self(rawValue: "interface.preview")
    static let exportInterfaceSettings = Self(rawValue: "interface.export")
    static let resetInterfaceSettings = Self(rawValue: "interface.reset")
    static let sendWithReturn = Self(rawValue: "chat.send-with-return")
    static let chatSpellCheck = Self(rawValue: "chat.spell-check")
    static let chatAutomaticCorrection = Self(rawValue: "chat.automatic-correction")
    static let chatSmartQuotes = Self(rawValue: "chat.smart-quotes")
    static let chatSmartDashes = Self(rawValue: "chat.smart-dashes")
    static let chatTypingIndicators = Self(rawValue: "chat.typing-indicators")
    static let chatFocusComposerOnTyping = Self(rawValue: "chat.focus-composer-on-typing")
    static let chatCharacterCounter = Self(rawValue: "chat.character-counter")
    static let chatDiscardConfirmationLink = Self(rawValue: "chat.discard-confirmation-link")
    static let chatReadAcknowledgement = Self(rawValue: "chat.read-acknowledgement")
    static let chatEditedMarkers = Self(rawValue: "chat.edited-markers")
    static let chatExpandEmbeds = Self(rawValue: "chat.expand-embeds")
    static let chatSpoilerReveal = Self(rawValue: "chat.spoiler-reveal")
    static let chatInternalDiscordLinks = Self(rawValue: "chat.internal-discord-links")
    static let chatAutoplayGIFs = Self(rawValue: "chat.autoplay-gifs")
    static let chatAutoplayStickers = Self(rawValue: "chat.autoplay-stickers")
    static let chatAutoplayVideos = Self(rawValue: "chat.autoplay-videos")
    static let chatLinkPreviews = Self(rawValue: "chat.link-previews")
    static let chatInlineMediaSize = Self(rawValue: "chat.inline-media-size")
    static let reduceAnimatedMedia = Self(rawValue: "chat.reduce-animated-media")
    static let chatEmojiSkinTone = Self(rawValue: "chat.emoji-skin-tone")
    static let chatEmojiSource = Self(rawValue: "chat.emoji-source")
    static let chatExport = Self(rawValue: "chat.export")
    static let chatReset = Self(rawValue: "chat.reset")
    static let updateReleaseTrack = Self(rawValue: "software-updates.release-track")
    static let updateAutomaticChecks = Self(rawValue: "software-updates.automatic-checks")
    static let updateAutomaticDownloads = Self(rawValue: "software-updates.automatic-downloads")
    static let checkForUpdates = Self(rawValue: "software-updates.check-now")
    static let updateChangelog = Self(rawValue: "software-updates.changelog")
    static let aboutVersionInformation = Self(rawValue: "about.version-information")
    static let aboutCheckForUpdates = Self(rawValue: "about.check-for-updates")
    static let aboutChangelog = Self(rawValue: "about.changelog")
    static let aboutWebsite = Self(rawValue: "about.website")
    static let aboutRoadmap = Self(rawValue: "about.roadmap")
    static let aboutSource = Self(rawValue: "about.source")
    static let aboutSupport = Self(rawValue: "about.support")
    static let aboutAcknowledgements = Self(rawValue: "about.acknowledgements")
    static let aboutDisclaimer = Self(rawValue: "about.disclaimer")
    static let localStorageLimit = Self(rawValue: "storage.local-storage-limit")
    static let localStorageUsage = Self(rawValue: "storage.local-storage-usage")
    static let mediaCacheClear = Self(rawValue: "storage.media-cache-clear")
    static let mediaCacheLastCleared = Self(rawValue: "storage.media-cache-last-cleared")
    static let downloadFolderBookmark = Self(rawValue: "storage.download-folder-bookmark")
    static let downloadFolderName = Self(rawValue: "storage.download-folder-name")
    static let revealCompletedDownloads = Self(rawValue: "storage.reveal-completed-downloads")
    static let clearAllAccountDrafts = Self(rawValue: "storage.clear-all-drafts")
    static let diagnosticsStatusOverview = Self(rawValue: "diagnostics.status-overview")
    static let diagnosticsRefresh = Self(rawValue: "diagnostics.refresh")
    static let diagnosticsSupportPreview = Self(rawValue: "diagnostics.support-preview")
    static let diagnosticsSupportCopy = Self(rawValue: "diagnostics.support-copy")
    static let diagnosticsSupportExport = Self(rawValue: "diagnostics.support-export")
    static let diagnosticsOpenFolder = Self(rawValue: "diagnostics.open-folder")
    static let notificationPermission = Self(rawValue: "notifications.system-permission")
    static let notificationEnabled = Self(rawValue: "notifications.enabled")
    static let notificationPreview = Self(rawValue: "notifications.preview")
    static let notificationSound = Self(rawValue: "notifications.sound")
    static let notificationDockBadge = Self(rawValue: "notifications.dock-badge")
    static let notificationFocus = Self(rawValue: "notifications.focus")
    static let notificationDirectMessages = Self(rawValue: "notifications.direct-messages")
    static let notificationGroupDirectMessages = Self(rawValue: "notifications.group-direct-messages")
    static let notificationMentions = Self(rawValue: "notifications.mentions")
    static let notificationReplies = Self(rawValue: "notifications.replies")
    static let notificationIncomingCalls = Self(rawValue: "notifications.incoming-calls")
    static let notificationServerActivity = Self(rawValue: "notifications.server-activity")
    static let notificationOnlyInBackground = Self(rawValue: "notifications.only-in-background")
    static let notificationSuppressCurrent = Self(rawValue: "notifications.suppress-current")
    static let notificationGroupBursts = Self(rawValue: "notifications.group-bursts")
    static let notificationClearWhenRead = Self(rawValue: "notifications.clear-when-read")
    static let notificationCallsBypassSuppression = Self(rawValue: "notifications.calls-bypass-suppression")
    static let notificationQuietHours = Self(rawValue: "notifications.quiet-hours")
    static let notificationQuietDays = Self(rawValue: "notifications.quiet-days")
    static let notificationQuietStart = Self(rawValue: "notifications.quiet-start")
    static let notificationQuietEnd = Self(rawValue: "notifications.quiet-end")
    static let notificationWeekendQuietStart = Self(rawValue: "notifications.weekend-quiet-start")
    static let notificationWeekendQuietEnd = Self(rawValue: "notifications.weekend-quiet-end")
    static let notificationAllowDirectMessages = Self(rawValue: "notifications.allow-direct-messages")
    static let notificationAllowCalls = Self(rawValue: "notifications.allow-calls")
    static let notificationDiscordOwnership = Self(rawValue: "notifications.discord-ownership")
    static let notificationExport = Self(rawValue: "notifications.export")
    static let notificationReset = Self(rawValue: "notifications.reset")
    static let voiceInputDevice = Self(rawValue: "voice-video.input-device")
    static let voiceOutputDevice = Self(rawValue: "voice-video.output-device")
    static let voiceCamera = Self(rawValue: "voice-video.camera")
    static let voiceInputVolume = Self(rawValue: "voice-video.input-volume")
    static let voiceOutputVolume = Self(rawValue: "voice-video.output-volume")
    static let voiceRefreshDevices = Self(rawValue: "voice-video.refresh-devices")
    static let voiceMicrophoneTest = Self(rawValue: "voice-video.microphone-test")
    static let voiceSpeakerTest = Self(rawValue: "voice-video.speaker-test")
    static let voiceJoinMuted = Self(rawValue: "voice-video.join-muted")
    static let voiceJoinDeafened = Self(rawValue: "voice-video.join-deafened")
    static let voiceFeedbackSounds = Self(rawValue: "voice-video.feedback-sounds")
    static let voiceCameraPreview = Self(rawValue: "voice-video.camera-preview")
    static let voiceMirrorPreview = Self(rawValue: "voice-video.mirror-preview")
    static let voiceRememberCamera = Self(rawValue: "voice-video.remember-camera")
    static let voiceJoinCameraOff = Self(rawValue: "voice-video.join-camera-off")
    static let voiceScreenShareQuality = Self(rawValue: "voice-video.share-quality")
    static let voiceScreenShareFrameRate = Self(rawValue: "voice-video.share-frame-rate")
    static let voiceScreenShareAudio = Self(rawValue: "voice-video.share-audio")
    static let voiceScreenSharePointer = Self(rawValue: "voice-video.share-pointer")
    static let voiceMicrophonePermission = Self(rawValue: "voice-video.microphone-permission")
    static let voiceCameraPermission = Self(rawValue: "voice-video.camera-permission")
    static let voiceScreenPermission = Self(rawValue: "voice-video.screen-permission")
    static let voiceExport = Self(rawValue: "voice-video.export")
    static let voiceReset = Self(rawValue: "voice-video.reset")
    static let accessibilityMotionOverride = Self(rawValue: "accessibility.motion-override")
    static let accessibilityReduceAnimatedContent = Self(rawValue: "accessibility.reduce-animated-content")
    static let accessibilityReduceAnimatedEmoji = Self(rawValue: "accessibility.reduce-animated-emoji")
    static let accessibilityReduceAnimatedStickers = Self(rawValue: "accessibility.reduce-animated-stickers")
    static let accessibilityReduceGIFs = Self(rawValue: "accessibility.reduce-gifs")
    static let accessibilityReduceAnimatedAvatars = Self(rawValue: "accessibility.reduce-animated-avatars")
    static let accessibilityReduceDecorations = Self(rawValue: "accessibility.reduce-decorations")
    static let accessibilityReduceTransitions = Self(rawValue: "accessibility.reduce-transitions")
    static let accessibilityIncreaseContrast = Self(rawValue: "accessibility.increase-contrast")
    static let accessibilityLargerTargets = Self(rawValue: "accessibility.larger-targets")
    static let accessibilityUnderlineLinks = Self(rawValue: "accessibility.underline-links")
    static let accessibilityMessageActions = Self(rawValue: "accessibility.message-actions")
    static let accessibilityAnnounceTimestamp = Self(rawValue: "accessibility.announce-timestamp")
    static let accessibilityAnnounceEdited = Self(rawValue: "accessibility.announce-edited")
    static let accessibilityAnnounceReactions = Self(rawValue: "accessibility.announce-reactions")
    static let accessibilityAnnounceAttachmentTypes = Self(rawValue: "accessibility.announce-attachment-types")
    static let accessibilityAnnounceNewMessages = Self(rawValue: "accessibility.announce-new-messages")
    static let accessibilityExport = Self(rawValue: "accessibility.export")
    static let accessibilityReset = Self(rawValue: "accessibility.reset")
    static let shortcutExport = Self(rawValue: "keyboard-shortcuts.export")
    static let shortcutReset = Self(rawValue: "keyboard-shortcuts.reset")
    static let privacyTypingIndicators = Self(rawValue: "privacy.typing-indicators")
    static let privacyReadAcknowledgements = Self(rawValue: "privacy.read-acknowledgements")
    static let externalLinkProtection = Self(rawValue: "privacy.external-link-protection")
    static let trustedDomains = Self(rawValue: "privacy.trusted-domains")
    static let clearLocalActivity = Self(rawValue: "privacy.clear-local-activity")
    static let diagnosticDetailedPayloads = Self(rawValue: "diagnostics.detailed-payloads")
    static let diagnosticPanicSave = Self(rawValue: "diagnostics.panic-save")
    static let diagnosticDiskCapture = Self(rawValue: "diagnostics.disk-capture")
    static let diagnosticRetainedEntries = Self(rawValue: "diagnostics.retained-entries")
    static let diagnosticExport = Self(rawValue: "diagnostics.export-api-logs")
    static let diagnosticClear = Self(rawValue: "diagnostics.clear-api-logs")
}

nonisolated extension SettingsCatalog {
    static let extensionsPage = page(
        .extensions, group: .sakuraCord, title: "Extensions", image: "puzzlepiece.extension",
        help: "Learn about SakuraCord's future sandboxed extension system.",
        keywords: ["plugins", "permissions", "sandbox", "sandboxing", "SDK", "host"]
    )

    static let foundationPages: [SettingsPageMetadata] = [
        profilesPage,
        myAccountPage,
        generalPage,
        interfacePage,
        appearancePage,
        chatPage,
        notificationsPage,
        voiceVideoPage,
        accessibilityPage,
        keyboardShortcutsPage,
        privacySafetyPage,
        storageDownloadsPage,
        diagnosticsPage,
        softwareUpdatesPage,
        extensionsPage,
        aboutPage,
    ]

    static let foundationControls: [SettingsControlMetadata] =
        myAccountControls
        + generalControls
        + appearanceControls
        + interfaceControls
        + chatControls
        + softwareUpdatesControls
        + storageDownloadsControls
        + notificationsControls
        + voiceVideoControls
        + accessibilityControls
        + diagnosticsControls
        + aboutControls
        + keyboardShortcutsControls
        + privacySafetyControls

    static func page(
        _ id: SettingsPageID,
        group: SettingsSidebarGroupID,
        title: String.LocalizationValue,
        image: String,
        help: String.LocalizationValue,
        keywords: [String.LocalizationValue]
    ) -> SettingsPageMetadata {
        SettingsPageMetadata(
            id: id,
            group: group,
            title: LocalizedStringResource(title, bundle: #bundle),
            systemImage: image,
            help: LocalizedStringResource(help, bundle: #bundle),
            keywords: keywords.map { LocalizedStringResource($0, bundle: #bundle) },
            overviewControlID: .overview(id)
        )
    }

    static func control(
        _ id: SettingsControlID,
        page: SettingsPageID,
        section: SettingsSectionID,
        label: String.LocalizationValue,
        help: String.LocalizationValue,
        keywords: [String.LocalizationValue],
        owner: SettingsValueOwner = .applicationPreferences,
        scope: SettingsValueScope,
        persistence: SettingsPersistence = .appPreferences,
        reset: SettingsResetCapability = .registeredLocalValue,
        availability: SettingsAvailability = .available
    ) -> SettingsControlMetadata {
        SettingsControlMetadata(
            id: id,
            destination: SettingsDestination(page: page, section: section),
            label: LocalizedStringResource(label, bundle: #bundle),
            help: LocalizedStringResource(help, bundle: #bundle),
            keywords: keywords.map { LocalizedStringResource($0, bundle: #bundle) },
            owner: owner,
            scope: scope,
            persistence: persistence,
            resetCapability: reset,
            availability: availability
        )
    }
}
