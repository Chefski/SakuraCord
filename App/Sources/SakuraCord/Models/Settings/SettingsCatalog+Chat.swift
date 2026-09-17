import Foundation

nonisolated extension SettingsCatalog {
    static let chatPage = page(
        .chat, group: .preferences, title: "Chat", image: "bubble.left.and.bubble.right",
        help: "Control composer, message, media, link, and emoji behavior.",
        keywords: ["message", "composer", "send", "typing", "draft", "emoji", "autoplay"]
    )

    static let chatControls: [SettingsControlMetadata] = [
        control(
            .sendWithReturn,
            page: .chat,
            section: .chatComposer,
            label: "Press Return to send messages",
            help: "Choose whether Return sends and Shift-Return inserts a newline, or Return inserts a newline and Command-Return sends.",
            keywords: ["enter", "newline", "composer", "command return", "shift return"],
            scope: .appWideLocal
        ),
        control(
            .chatSpellCheck, page: .chat, section: .chatComposer,
            label: "Check spelling while typing",
            help: "Use AppKit's continuous spell checker in the real message composer.",
            keywords: ["spellcheck", "spelling", "typo"], scope: .appWideLocal
        ),
        control(
            .chatAutomaticCorrection, page: .chat, section: .chatComposer,
            label: "Correct spelling automatically",
            help: "Allow the native text system to apply spelling corrections in the composer.",
            keywords: ["autocorrect", "correction", "typing"], scope: .appWideLocal
        ),
        control(
            .chatSmartQuotes, page: .chat, section: .chatComposer,
            label: "Smart quotes",
            help: "Allow the native text system to substitute typographic quotation marks.",
            keywords: ["curly quotes", "quotation", "substitution"], scope: .appWideLocal
        ),
        control(
            .chatSmartDashes, page: .chat, section: .chatComposer,
            label: "Smart dashes",
            help: "Allow the native text system to substitute typographic dashes.",
            keywords: ["em dash", "hyphen", "substitution"], scope: .appWideLocal
        ),
        control(
            .chatTypingIndicators, page: .chat, section: .chatComposer,
            label: "Send typing indicators",
            help: "Tell Discord when you are composing a normal message. Disabling this cancels pending local typing signals.",
            keywords: ["typing status", "privacy", "indicator"], scope: .appWideLocal
        ),
        control(
            .chatFocusComposerOnTyping, page: .chat, section: .chatComposer,
            label: "Focus composer when typing begins",
            help: "Move printable typing to the composer only when another editable field, menu, overlay, or assisted interaction does not own input.",
            keywords: ["type to focus", "keyboard", "first responder"], scope: .appWideLocal
        ),

        control(
            .chatReadAcknowledgement, page: .chat, section: .chatMessages,
            label: "Mark messages read",
            help: "Automatically acknowledge meaningfully visible content or wait for an explicit Mark Read action. Discord synchronizes the unread result to other clients.",
            keywords: ["read receipt", "ack", "unread", "manual", "read state"],
            scope: .appWideLocal
        ),
        control(
            .chatEditedMarkers, page: .chat, section: .chatMessages,
            label: "Show edited markers",
            help: "Show Discord's edited state beside message timestamps.",
            keywords: ["modified", "timestamp", "edited"], scope: .appWideLocal
        ),
        control(
            .chatExpandEmbeds, page: .chat, section: .chatMessages,
            label: "Expand embeds by default",
            help: "Show rich Discord embeds in the timeline by default.",
            keywords: ["collapse", "rich embed", "card"], scope: .appWideLocal
        ),
        control(
            .chatSpoilerReveal, page: .chat, section: .chatMessages,
            label: "Reveal spoilers",
            help: "Reveal spoilers with a click, only with Option-click, or without concealment.",
            keywords: ["hidden content", "option click", "always reveal"], scope: .appWideLocal
        ),
        control(
            .chatInternalDiscordLinks, page: .chat, section: .chatMessages,
            label: "Open Discord links in SakuraCord",
            help: "Navigate resolvable Discord channel links internally; other links continue to use the system browser.",
            keywords: ["discord.com/channels", "internal link", "browser"], scope: .appWideLocal
        ),
        control(
            .chatAutoplayGIFs, page: .chat, section: .chatMedia,
            label: "Autoplay GIFs",
            help: "Animate inline GIF and animated-image media when motion is permitted.",
            keywords: ["animated images", "GIF", "playback"], scope: .appWideLocal
        ),
        control(
            .chatAutoplayStickers, page: .chat, section: .chatMedia,
            label: "Autoplay animated stickers",
            help: "Animate APNG, GIF, and Lottie stickers when motion is permitted.",
            keywords: ["sticker animation", "Lottie", "APNG"], scope: .appWideLocal
        ),
        control(
            .chatAutoplayVideos, page: .chat, section: .chatMedia,
            label: "Autoplay inline videos",
            help: "Play Discord GIFV and other explicitly inline-autoplay video previews when motion is permitted.",
            keywords: ["video playback", "GIFV", "loop"], scope: .appWideLocal
        ),
        control(
            .chatLinkPreviews, page: .chat, section: .chatMedia,
            label: "Show automatic link previews",
            help: "Show Discord-generated preview embeds for links in message content.",
            keywords: ["unfurl", "URL preview", "rich link"], scope: .appWideLocal
        ),
        control(
            .chatInlineMediaSize, page: .chat, section: .chatMedia,
            label: "Inline media size",
            help: "Bound inline media to a compact, medium, or large Mac-appropriate width.",
            keywords: ["image size", "attachment width", "preview size"], scope: .appWideLocal
        ),
        control(
            .reduceAnimatedMedia,
            page: .chat,
            section: .chatMedia,
            label: "Reduce animated media",
            help: "Pause optional animated media. macOS Reduce Motion and the broader Accessibility preference take precedence.",
            keywords: ["GIF", "animation", "motion", "reduce motion", "Accessibility"],
            scope: .appWideLocal
        ),
        control(
            .chatEmojiSkinTone, page: .chat, section: .chatEmoji,
            label: "Default emoji skin tone",
            help: "Choose the app-wide skin-tone modifier used by the native emoji picker.",
            keywords: ["modifier", "hand", "tone", "emoji"], scope: .appWideLocal
        ),

        control(
            .chatReset, page: .chat, section: .chatLocalData,
            label: "Reset Chat Settings",
            help: "Restore registered Chat preferences without changing drafts, credentials, or Discord state.",
            keywords: ["defaults", "restore", "clear chat preferences"],
            scope: .appWideLocal, persistence: .appPreferences, reset: .categoryAction
        ),
    ]
}
