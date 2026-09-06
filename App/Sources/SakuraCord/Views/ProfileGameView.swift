import AppKit
import SakuraCordModels
import SwiftUI

struct ProfileGameView: View {
    let model: AppModel
    @State private var game: ProfileGame
    @State private var editor: ProfileEditorState
    @State private var similar: [ProfileGame] = []
    @State private var announcements = ProfileGameAnnouncements()
    @State private var errors: [String: String] = [:]
    @State private var isLoading = true
    @State private var navigation: [ProfileGame] = []
    @Environment(\.profileEditorModal) private var dismiss

    init(model: AppModel, game: ProfileGame, editor: ProfileEditorState? = nil) {
        self.model = model
        _game = State(initialValue: game)
        if let editor, editor.scope == .main { _editor = State(initialValue: editor) } else { _editor = State(initialValue: ProfileEditorState(model: model)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if game.metadata?.isProfileAvailable == false {
                    ContentUnavailableView("Game Profile Unavailable", systemImage: "gamecontroller")
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 28) {
                            if let metadata = game.metadata {
                                ProfileGameGallery(game: game)
                                if let description = metadata.description, !description.isEmpty {
                                    ProfileGameDescription(text: description).id(game.id)
                                }
                            }
                            announcementSection
                            similarSection
                        }
                        .frame(maxWidth: .infinity)
                        if let metadata = game.metadata {
                            ProfileGameDetails(metadata: metadata, open: openLink).frame(width: 360)
                        }
                    }
                }
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(errors.keys.sorted(), id: \.self) { key in
                    HStack {
                        Label(errors[key] ?? "", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Retry") { Task { await load() } }.disabled(isLoading)
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
                if let error = editor.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
            }
            .padding(24)
        }
        .profileEditorModalSize(width: 1180, height: 760)
        .background(alignment: .top) {
            if let artwork = game.metadata?.artwork.first {
                ProfileWidgetImageView(url: artwork, contentMode: .fill)
                    .frame(height: 220).clipped().opacity(0.15)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .background(.regularMaterial)
        .task(id: game.id) { await load() }
        .profileEditorDismissDisabled(editor.isSaving)
        .onChange(of: model.installedAccountSessionRevision) { _, _ in dismiss?() }
        .onChange(of: model.isSwitchingAccounts) { _, switching in if switching { dismiss?() } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ProfileWidgetGameCover(game: game, animates: true).frame(width: 86, height: 114)
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 24)
                Text(game.name).font(.system(size: 32, weight: .bold))
                Text(ProfileGameLabels.genres(game.metadata?.genres ?? [])).font(.system(size: 16)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !navigation.isEmpty {
                Button { if let previous = navigation.popLast() { game = previous } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back").disabled(editor.isSaving)
            }
            if editor.snapshot?.widgetEligibility.canEditPersonalWidget == true {
                Menu {
                    ForEach(ProfileGameWidgetKind.allCases, id: \.self) { kind in
                        let entries = widgetGames(kind)
                        let contains = entries.contains { $0.id == game.id }
                        Button(contains ? "Remove from \(kind.title)" : kind.title) {
                            Task { await editor.saveGameWidgetShortcut(gameID: game.id, kind: kind) }
                        }
                        .disabled(!editor.canEditWidgets || !contains && entries.count >= kind.capacity)
                    }
                } label: { Label("Add to Profile", systemImage: "plus") }
                .disabled(editor.isSaving)
            }
            Button { MediaViewerActionService.copyText("https://discord.com/games/\(game.id)") } label: { Image(systemName: "link") }
                .accessibilityLabel("Copy Link").help("Copy Link")
            if editor.snapshot?.widgetEligibility.showsDeveloperWidgets == true {
                Menu {
                    Button("Copy Game ID") { MediaViewerActionService.copyText(game.id) }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("More")
            }
            HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
                .disabled(editor.isSaving)
        }
        .frame(height: 114)
    }

    @ViewBuilder private var announcementSection: some View {
        if let channelID = announcements.channelID, let guildID = announcements.guildID, !announcements.messages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Announcements", bundle: #bundle).font(.headline)
                    Spacer()
                    Button("View All") { openAnnouncement(guildID: guildID, channelID: channelID, messageID: nil) }.buttonStyle(.plain)
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(announcements.messages) { message in
                            ProfileGameAnnouncementCard(message: message)
                                .contentShape(.rect)
                                .onTapGesture { openAnnouncement(guildID: guildID, channelID: channelID, messageID: message.id) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { openAnnouncement(guildID: guildID, channelID: channelID, messageID: message.id) }
                                .environment(\.openURL, OpenURLAction { url in openLink(url); return .handled })
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var similarSection: some View {
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Similar Games", bundle: #bundle).font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(similar) { suggestion in
                            Button { navigation.append(game); game = suggestion } label: {
                                ProfileWidgetGameCover(game: suggestion, animates: true).frame(width: 78, height: 104)
                            }.buttonStyle(.plain).disabled(editor.isSaving)
                        }
                    }
                }
            }
        }
    }

    private func widgetGames(_ kind: ProfileGameWidgetKind) -> [ProfileWidgetGame] {
        for widget in editor.widgets {
            if case let .games(value, games) = widget.content, value == kind { return games }
        }
        return []
    }

    private func openLink(_ url: URL) {
        _ = MessageLinkActivator.activate(url, model: model, displayedText: url.absoluteString)
    }

    private func openAnnouncement(guildID: GuildID, channelID: ChannelID, messageID: MessageID?) {
        guard let url = URL(string: "https://discord.com/channels/\(guildID)/\(channelID)\(messageID.map { "/\($0)" } ?? "")") else { return }
        dismiss?()
        openLink(url)
    }

    private func load() async {
        let session = model.accountSession()
        let id = game.id
        isLoading = true; errors = [:]; similar = []; announcements = ProfileGameAnnouncements()
        async let profile: Void = editor.loadIfNeeded(preferCached: true)
        async let details: Void = loadDetails(id: id, session: session)
        async let news: Void = loadAnnouncements(id: id, session: session)
        async let suggestions: Void = loadSimilar(id: id, session: session)
        _ = await (profile, details, news, suggestions)
        guard game.id == id, model.isCurrentAccountSession(session), !Task.isCancelled else { return }
        isLoading = false
    }

    private func loadDetails(id: String, session: AppModelAccountSession) async {
        do {
            let records = try await session.provider.profileWidgetGames(ids: [id])
            guard game.id == id, model.isCurrentAccountSession(session), !Task.isCancelled else { return }
            if let loaded = records.first(where: { $0.id == id }) { game = loaded } else { errors["details"] = String(localized: "This game profile is unavailable.", bundle: #bundle) }
        } catch { record(error, section: "details", id: id, session: session) }
    }

    private func loadAnnouncements(id: String, session: AppModelAccountSession) async {
        do {
            let value = try await session.provider.profileGameAnnouncements(gameID: id)
            guard game.id == id, model.isCurrentAccountSession(session), !Task.isCancelled else { return }
            announcements = value
        } catch { record(error, section: "announcements", id: id, session: session) }
    }

    private func loadSimilar(id: String, session: AppModelAccountSession) async {
        do {
            let value = try await session.provider.similarProfileGames(to: id)
            guard game.id == id, model.isCurrentAccountSession(session), !Task.isCancelled else { return }
            similar = value
        } catch { record(error, section: "similar", id: id, session: session) }
    }

    private func record(_ error: Error, section: String, id: String, session: AppModelAccountSession) {
        guard game.id == id, model.isCurrentAccountSession(session), !Task.isCancelled, !(error is CancellationError) else { return }
        errors[section] = error.localizedDescription
    }
}

struct ProfileGamePresentationModifier: ViewModifier {
    @Bindable var model: AppModel
    func body(content: Content) -> some View {
        content.profileEditorOverlay(item: $model.presentedProfileGame) { game in
            ProfileGameView(model: model, game: game)
        }
    }
}
