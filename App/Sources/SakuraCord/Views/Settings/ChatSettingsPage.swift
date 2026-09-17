import SwiftUI

struct ChatSettingsPage: View {
    let model: AppModel
    let state: SettingsViewState

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var value = ChatSettingsSnapshot.defaults
    @State private var showsResetConfirmation = false
    @State private var operationMessage: String?

    var body: some View {
        SettingsPageForm(page: .chat, state: state) {
            composerSection
            textInputSection
            messagesSection
            mediaSection
            emojiSection
            resetSection
        }
        .task {
            value = model.chatSettings
        }
        .onChange(of: value) { _, newValue in
            model.applyChatSettings(newValue)
        }
        .settingsResetConfirmation(
            "Reset Chat Settings?",
            isPresented: $showsResetConfirmation,
            resetTitle: "Reset Chat Settings",
            message: "Restore Chat settings to their defaults? Your drafts and emoji history will be kept.",
            reset: resetPreferences
        )
    }

    private var composerSection: some View {
        Section {
            Toggle("Press Return to send messages", isOn: $value.sendsWithReturn)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.sendWithReturn, state: state)

            Toggle("Send typing indicators", isOn: $value.sendsTypingIndicators)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.chatTypingIndicators, state: state)
            Toggle(
                "Focus the message field when typing",
                isOn: $value.focusesComposerOnTyping
            )
            .tint(SakuraCordAccentColor.color)
            .settingsControlAnchor(.chatFocusComposerOnTyping, state: state)
        } header: {
            Text("Composer", bundle: #bundle)
        } footer: {
            Text(value.sendsWithReturn ? "Return sends a message. Shift-Return adds a new line." : "Return adds a new line. Command-Return sends a message.")
        }
    }

    private var textInputSection: some View {
        Section {
            Toggle("Check spelling while typing", isOn: $value.checksSpelling)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.chatSpellCheck, state: state)
            Toggle(
                "Correct spelling automatically",
                isOn: $value.correctsSpellingAutomatically
            )
            .tint(SakuraCordAccentColor.color)
            .settingsControlAnchor(.chatAutomaticCorrection, state: state)
            Toggle("Smart quotes", isOn: $value.usesSmartQuotes)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.chatSmartQuotes, state: state)
            Toggle("Smart dashes", isOn: $value.usesSmartDashes)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.chatSmartDashes, state: state)
        } header: {
            Text("Text Input", bundle: #bundle)
        }
    }

    private var messagesSection: some View {
        Section {
            Picker("Mark messages read", selection: $value.readAcknowledgementMode) {
                ForEach(ChatReadAcknowledgementMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .settingsControlAnchor(.chatReadAcknowledgement, state: state)

            Toggle("Show edited markers", isOn: $value.showsEditedMarkers)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.chatEditedMarkers, state: state)
            Toggle("Expand embeds by default", isOn: $value.expandsEmbedsByDefault)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.chatExpandEmbeds, state: state)
            Picker("Reveal spoilers", selection: $value.spoilerRevealMode) {
                ForEach(ChatSpoilerRevealMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .settingsControlAnchor(.chatSpoilerReveal, state: state)
            Toggle(
                "Open Discord channel links in SakuraCord",
                isOn: $value.opensDiscordLinksInternally
            )
            .tint(SakuraCordAccentColor.color)
            .settingsControlAnchor(.chatInternalDiscordLinks, state: state)
        } header: {
            Text("Messages", bundle: #bundle)
        } footer: {
            Text(value.readAcknowledgementMode == .automatic ? "Messages are marked read when viewed. Read status syncs with Discord." : "Messages stay unread until you choose Mark Read.")
        }
    }

    private var mediaSection: some View {
        Section {
            Toggle("Autoplay GIFs", isOn: $value.autoplaysGIFs)
                .tint(SakuraCordAccentColor.color)
                .disabled(value.reducesAnimatedMedia || systemReduceMotion)
                .settingsControlAnchor(.chatAutoplayGIFs, state: state)
            Toggle(
                "Autoplay animated stickers",
                isOn: $value.autoplaysAnimatedStickers
            )
            .tint(SakuraCordAccentColor.color)
            .disabled(value.reducesAnimatedMedia || systemReduceMotion)
            .settingsControlAnchor(.chatAutoplayStickers, state: state)
            Toggle("Autoplay inline videos", isOn: $value.autoplaysInlineVideos)
                .tint(SakuraCordAccentColor.color)
                .disabled(value.reducesAnimatedMedia || systemReduceMotion)
                .settingsControlAnchor(.chatAutoplayVideos, state: state)
            Toggle(
                "Show automatic link previews",
                isOn: $value.showsAutomaticLinkPreviews
            )
            .tint(SakuraCordAccentColor.color)
            .settingsControlAnchor(.chatLinkPreviews, state: state)
            Picker("Inline media size", selection: $value.inlineMediaSize) {
                ForEach(ChatInlineMediaSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .settingsControlAnchor(.chatInlineMediaSize, state: state)
            Toggle("Reduce animated media", isOn: $value.reducesAnimatedMedia)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.reduceAnimatedMedia, state: state)
        } header: {
            Text("Media", bundle: #bundle)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reduce animated media pauses autoplay. macOS Reduce Motion also applies.")
                if systemReduceMotion
                {
                    Text("Some autoplay options are controlled by macOS Reduce Motion.")
                }
            }
        }
    }

    private var emojiSection: some View {
        Section {
            Picker("Default emoji skin tone", selection: $value.emojiSkinTone) {
                ForEach(NativeEmojiSkinTone.allCases) { tone in
                    Text("\(tone.symbol)  \(tone.title)").tag(tone)
                }
            }
            .settingsControlAnchor(.chatEmojiSkinTone, state: state)
        } header: {
            Text("Emoji", bundle: #bundle)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Chat Settings…", role: .destructive) {
                showsResetConfirmation = true
            }
            .settingsControlAnchor(.chatReset, state: state)
            if let operationMessage {
                Text(operationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Reset", bundle: #bundle)
        }
    }

    private func resetPreferences() {
        SettingsPreferenceStore.shared.reset(scope: .appWide, page: .chat)
        value = ChatSettingsStore.shared.load()
        model.applyChatSettings(value, persists: false)
        operationMessage = "Restored Chat settings to their defaults."
    }
}
