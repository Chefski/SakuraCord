import Foundation

nonisolated extension SettingsCatalog {
    static let notificationsPage = page(
        .notifications, group: .preferences, title: "Notifications", image: "bell",
        help: "Narrow local macOS notification delivery while preserving Discord server and channel settings.",
        keywords: ["alerts", "sound", "badge", "quiet hours", "permission", "preview"]
    )

    static let notificationsControls: [SettingsControlMetadata] = [
        control(
            .notificationPermission,
            page: .notifications,
            section: .notificationDelivery,
            label: "System permission",
            help: "Show or request the current macOS notification authorization.",
            keywords: ["allow", "denied", "System Settings"],
            owner: .macOS,
            scope: .appWideLocal,
            persistence: .systemManaged,
            reset: .notApplicable
        ),
        control(
            .notificationEnabled,
            page: .notifications,
            section: .notificationDelivery,
            label: "Enable native notifications",
            help: "Allow eligible Discord events to appear as local macOS notifications.",
            keywords: ["alerts", "master"],
            scope: .appWideLocal
        ),
        control(
            .notificationPreview,
            page: .notifications,
            section: .notificationDelivery,
            label: "Notification previews",
            help: "Choose how much message information appears in notifications.",
            keywords: ["sender", "hidden", "privacy"],
            scope: .appWideLocal
        ),
        control(
            .notificationSound,
            page: .notifications,
            section: .notificationDelivery,
            label: "Play sound",
            help: "Use Notification Center's standard sound so macOS sound and Focus policy remain authoritative.",
            keywords: ["audio", "alert", "Focus"],
            scope: .appWideLocal
        ),
        control(
            .notificationDockBadge,
            page: .notifications,
            section: .notificationDelivery,
            label: "Dock badge",
            help: "Show unread mentions, reliably projected unread conversations, or no Dock badge.",
            keywords: ["badge", "mentions", "unread conversations", "off"],
            scope: .appWideLocal
        ),
        control(
            .notificationFocus, page: .notifications, section: .notificationDelivery,
            label: "macOS Focus",
            help: "SakuraCord uses standard active notifications and never elevates messages or calls above the user's Focus policy.",
            keywords: ["Do Not Disturb", "DND", "interruption level", "system"],
            owner: .macOS, scope: .appWideLocal,
            persistence: .systemManaged, reset: .notApplicable
        ),
        control(
            .notificationDirectMessages, page: .notifications, section: .notificationEvents,
            label: "Direct messages", help: "Allow eligible one-to-one direct messages.",
            keywords: ["DM", "private message"], scope: .appWideLocal
        ),
        control(
            .notificationGroupDirectMessages, page: .notifications,
            section: .notificationEvents, label: "Group direct messages",
            help: "Allow eligible group-DM messages.",
            keywords: ["group DM", "private group"], scope: .appWideLocal
        ),
        control(
            .notificationMentions, page: .notifications, section: .notificationEvents,
            label: "Mentions", help: "Allow eligible direct, role, and everyone mentions.",
            keywords: ["@mention", "role", "everyone"], scope: .appWideLocal
        ),
        control(
            .notificationReplies, page: .notifications, section: .notificationEvents,
            label: "Replies", help: "Allow eligible replies to one of your messages.",
            keywords: ["reply", "response"], scope: .appWideLocal
        ),
        control(
            .notificationIncomingCalls, page: .notifications, section: .notificationEvents,
            label: "Incoming calls", help: "Allow native alerts for newly ringing private calls.",
            keywords: ["call", "ring", "voice"], scope: .appWideLocal
        ),
        control(
            .notificationServerActivity, page: .notifications, section: .notificationEvents,
            label: "Server activity", help: "Allow ordinary server messages already eligible under Discord's notification settings.",
            keywords: ["guild", "all messages", "server"], scope: .appWideLocal
        ),
        control(
            .notificationOnlyInBackground, page: .notifications,
            section: .notificationEvents, label: "Notify only in the background",
            help: "Suppress ordinary alerts while SakuraCord is active.",
            keywords: ["foreground", "active app", "background"], scope: .appWideLocal
        ),
        control(
            .notificationSuppressCurrent, page: .notifications,
            section: .notificationEvents, label: "Suppress the current conversation",
            help: "Do not alert for a conversation already presented at its newest message.",
            keywords: ["open channel", "visible", "current chat"], scope: .appWideLocal
        ),
        control(
            .notificationGroupBursts, page: .notifications,
            section: .notificationEvents, label: "Group bursts by conversation",
            help: "Assign a native Notification Center thread to each account and conversation.",
            keywords: ["thread", "stack", "deduplicate", "group"], scope: .appWideLocal
        ),
        control(
            .notificationClearWhenRead, page: .notifications,
            section: .notificationEvents, label: "Clear notifications when read",
            help: "Remove delivered and pending message notifications when their conversation is acknowledged.",
            keywords: ["dismiss", "mark read", "remove delivered"], scope: .appWideLocal
        ),
        control(
            .notificationCallsBypassSuppression, page: .notifications,
            section: .notificationEvents, label: "Let calls bypass message suppression",
            help: "Allow enabled calls through background-only and current-conversation suppression. Quiet hours and macOS Focus still apply.",
            keywords: ["call exception", "urgent", "foreground"], scope: .appWideLocal
        ),
        control(
            .notificationQuietHours,
            page: .notifications,
            section: .notificationQuietHours,
            label: "Quiet hours",
            help: "Suppress ordinary local notifications during a configured time range.",
            keywords: ["schedule", "do not disturb"],
            scope: .appWideLocal
        ),
        control(
            .notificationQuietDays, page: .notifications,
            section: .notificationQuietHours, label: "Enabled days",
            help: "Choose the local calendar days on which quiet hours begin.",
            keywords: ["Monday", "weekdays", "weekend", "calendar"], scope: .appWideLocal
        ),
        control(
            .notificationQuietStart,
            page: .notifications,
            section: .notificationQuietHours,
            label: "Weekday quiet start",
            help: "Choose when Monday-through-Friday quiet hours begin.",
            keywords: ["schedule", "start time", "weekday"], scope: .appWideLocal
        ),
        control(
            .notificationQuietEnd,
            page: .notifications,
            section: .notificationQuietHours,
            label: "Weekday quiet end",
            help: "Choose when Monday-through-Friday quiet hours end.",
            keywords: ["schedule", "end time", "weekday"], scope: .appWideLocal
        ),
        control(
            .notificationWeekendQuietStart, page: .notifications,
            section: .notificationQuietHours, label: "Weekend quiet start",
            help: "Choose when Saturday-and-Sunday quiet hours begin.",
            keywords: ["schedule", "start time", "weekend"], scope: .appWideLocal
        ),
        control(
            .notificationWeekendQuietEnd, page: .notifications,
            section: .notificationQuietHours, label: "Weekend quiet end",
            help: "Choose when Saturday-and-Sunday quiet hours end.",
            keywords: ["schedule", "end time", "weekend"], scope: .appWideLocal
        ),
        control(
            .notificationAllowDirectMessages, page: .notifications,
            section: .notificationQuietHours, label: "Allow direct messages",
            help: "Let enabled direct-message and group-DM events through quiet hours.",
            keywords: ["quiet exception", "DM"], scope: .appWideLocal
        ),
        control(
            .notificationAllowCalls, page: .notifications,
            section: .notificationQuietHours, label: "Allow incoming calls",
            help: "Let enabled incoming-call alerts through quiet hours.",
            keywords: ["quiet exception", "ring"], scope: .appWideLocal
        ),
        control(
            .notificationDiscordOwnership, page: .notifications,
            section: .notificationEvents, label: "Discord notification controls",
            help: "Server, category, channel, mention-suppression, and mute-duration controls remain in their existing context menus and synchronize through Discord.",
            keywords: ["server mute", "channel mute", "notification level", "right click"],
            owner: .discord, scope: .discordSynchronized,
            persistence: .discordManaged, reset: .notApplicable
        ),
        control(
            .notificationExport, page: .notifications,
            section: .notificationLocalData, label: "Export Notification Settings",
            help: "Export registered app-wide Notification preferences as versioned JSON.",
            keywords: ["backup", "JSON", "save preferences"], scope: .appWideLocal,
            persistence: .notApplicable, reset: .notApplicable
        ),
        control(
            .notificationReset, page: .notifications,
            section: .notificationLocalData, label: "Reset Notification Settings",
            help: "Restore SakuraCord's local Notification preferences without changing macOS authorization or Discord settings.",
            keywords: ["defaults", "restore", "clear preferences"], scope: .appWideLocal,
            persistence: .appPreferences, reset: .categoryAction
        ),
    ]
}
