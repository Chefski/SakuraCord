import Foundation

nonisolated extension SettingsCatalog {
    static let accessibilityPage = page(
        .accessibility, group: .preferences, title: "Accessibility", image: "accessibility",
        help: "Tune motion, animated content, readability, interaction, and VoiceOver output.",
        keywords: ["reduce motion", "contrast", "animation", "VoiceOver", "keyboard", "larger targets"]
    )

    static let accessibilityControls: [SettingsControlMetadata] = [
        control(
            .accessibilityMotionOverride, page: .accessibility,
            section: .accessibilityMotion, label: "Motion preference",
            help: "Follow macOS Reduce Motion or always reduce optional motion in SakuraCord.",
            keywords: ["system setting", "override", "reduce motion", "animation"],
            scope: .appWideLocal
        ),
        control(
            .accessibilityReduceAnimatedContent, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce animated content",
            help: "Pause all optional animated content while preserving static previews and controls.",
            keywords: ["master", "animation", "pause media", "motion"],
            scope: .appWideLocal
        ),
        control(
            .accessibilityReduceAnimatedEmoji, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce animated emoji",
            help: "Pause animated custom emoji in messages, reactions, pickers, and member activity.",
            keywords: ["custom emoji", "reaction", "activity"], scope: .appWideLocal
        ),
        control(
            .accessibilityReduceAnimatedStickers, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce animated stickers",
            help: "Pause animated image and Lottie stickers while retaining their first frame.",
            keywords: ["Lottie", "APNG", "sticker animation"], scope: .appWideLocal
        ),
        control(
            .accessibilityReduceGIFs, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce GIFs and animated images",
            help: "Pause GIF, APNG, and animated-image playback in content and pickers.",
            keywords: ["GIF", "APNG", "animated image"], scope: .appWideLocal
        ),
        control(
            .accessibilityReduceAnimatedAvatars, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce animated avatars",
            help: "Pause animated user and application avatars.",
            keywords: ["profile picture", "user icon"], scope: .appWideLocal
        ),
        control(
            .accessibilityReduceDecorations, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce profile decorations",
            help: "Pause animated avatar decorations, banners, and nameplates.",
            keywords: ["avatar decoration", "banner", "nameplate"], scope: .appWideLocal
        ),
        control(
            .accessibilityReduceTransitions, page: .accessibility,
            section: .accessibilityMotion, label: "Reduce nonessential transitions",
            help: "Present SakuraCord overlays and ornamental state changes without animated transitions.",
            keywords: ["overlay", "fade", "window animation"], scope: .appWideLocal
        ),
        control(
            .accessibilityIncreaseContrast, page: .accessibility,
            section: .accessibilityReadability, label: "Increase contrast",
            help: "Increase separation between colors in SakuraCord's rendered native interface when macOS is using standard contrast.",
            keywords: ["readability", "high contrast", "semantic colors"], scope: .appWideLocal
        ),
        control(
            .accessibilityLargerTargets, page: .accessibility,
            section: .accessibilityReadability, label: "Use larger message action targets",
            help: "Increase the hit area of compact message action controls without duplicating their commands.",
            keywords: ["button size", "motor", "click target", "toolbar"], scope: .appWideLocal
        ),
        control(
            .underlineLinks, page: .accessibility, section: .accessibilityReadability,
            label: "Underline links", help: "Always use the hover underline for message links.",
            keywords: ["links", "URL", "readability"], scope: .appWideLocal
        ),
        control(
            .roleColorDisplay, page: .accessibility, section: .accessibilityReadability,
            label: "Role colours", help: "Show role colours in names, next to names, or hide them.",
            keywords: ["roles", "color", "colour", "names"], scope: .appWideLocal
        ),
        control(
            .accessibilityAnnounceTimestamp, page: .accessibility,
            section: .accessibilityVoiceOver, label: "Include timestamps",
            help: "Include each message timestamp in its VoiceOver row summary.",
            keywords: ["VoiceOver", "time", "message metadata"], scope: .appWideLocal
        ),
        control(
            .accessibilityAnnounceEdited, page: .accessibility,
            section: .accessibilityVoiceOver, label: "Include edited status",
            help: "Announce when a message has been edited.",
            keywords: ["VoiceOver", "modified", "message metadata"], scope: .appWideLocal
        ),
        control(
            .accessibilityAnnounceReactions, page: .accessibility,
            section: .accessibilityVoiceOver, label: "Include reaction counts",
            help: "Include the total reaction count in a message's VoiceOver row summary.",
            keywords: ["VoiceOver", "emoji", "reaction metadata"], scope: .appWideLocal
        ),
        control(
            .accessibilityAnnounceAttachmentTypes, page: .accessibility,
            section: .accessibilityVoiceOver, label: "Include attachment types",
            help: "Summarize image, video, audio, and file attachment types for VoiceOver.",
            keywords: ["VoiceOver", "media", "file type"], scope: .appWideLocal
        ),
        control(
            .accessibilityAnnounceNewMessages, page: .accessibility,
            section: .accessibilityVoiceOver, label: "Announce new messages",
            help: "While VoiceOver is running, announce grouped incoming-message counts without speaking message content or sender identity.",
            keywords: ["VoiceOver", "live messages", "privacy", "throttle"], scope: .appWideLocal
        ),
        control(
            .accessibilityExport, page: .accessibility,
            section: .accessibilityLocalData, label: "Export Accessibility Settings",
            help: "Export registered app-wide Accessibility preferences as versioned JSON.",
            keywords: ["backup", "JSON", "save preferences"], scope: .appWideLocal,
            persistence: .notApplicable, reset: .notApplicable
        ),
        control(
            .accessibilityReset, page: .accessibility,
            section: .accessibilityLocalData, label: "Reset Accessibility Settings",
            help: "Restore SakuraCord accessibility preferences without changing macOS accessibility settings.",
            keywords: ["defaults", "restore", "system settings"], scope: .appWideLocal,
            persistence: .appPreferences, reset: .categoryAction
        ),
    ]
}
