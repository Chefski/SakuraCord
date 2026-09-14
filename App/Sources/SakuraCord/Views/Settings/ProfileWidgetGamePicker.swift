import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileWidgetGamePicker: View {
    let editor: ProfileEditorState
    let selectedIDs: Set<String>
    let dismiss: () -> Void
    let select: (ProfileGame) -> Void
    @State private var query = ""
    @State private var defaults: [ProfileGame] = []
    @State private var matches: [ProfileGame] = []
    @State private var isLoadingDefaults = true
    @State private var isSearching = false
    @State private var pendingGameID: String?
    @State private var errorMessage: String?
    @State private var lastActivatedQuery: String?
    @State private var lastActivation: ContinuousClock.Instant?
    @FocusState private var searchFocused: Bool
    private var normalizedQuery: String { DiscordProfileWidgetGameSearch.normalizedQuery(query) }
    private var games: [ProfileGame] { normalizedQuery.isEmpty ? defaults : matches }
    private var isLoading: Bool { normalizedQuery.isEmpty ? isLoadingDefaults : isSearching }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Search games", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($searchFocused)
                if !query.isEmpty {
                    ComposerActionButton(icon: Image(systemName: "xmark"), help: String(localized: "Clear search", bundle: #bundle), iconSize: 12, size: 28) {
                        query = ""
                        searchFocused = true
                    }
                }
            }
            .frame(minHeight: 34)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider().padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(games) { game in gameRow(game) }
                    if isLoading {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(12)
                    } else if games.isEmpty, errorMessage == nil {
                        Text(normalizedQuery.isEmpty ? "Search for a game to add." : "No games found.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(12)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(.secondary).padding(12)
                    }
                }
                .padding(4)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 320, height: 320)
        .disabled(!editor.canEditWidgets)
        .task {
            searchFocused = true
            do {
                let games = try await editor.defaultWidgetGames()
                try Task.checkCancellation()
                defaults = games
            } catch is CancellationError { return } catch {
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                errorMessage = error.localizedDescription
            }
            isLoadingDefaults = false
        }
        .task(id: normalizedQuery) { await search() }
        .task(id: pendingGameID) {
            guard let id = pendingGameID else { return }
            defer { pendingGameID = nil }
            do {
                let details = try await editor.loadWidgetGames(ids: [id])
                try Task.checkCancellation()
                guard editor.canEditWidgets else { return }
                guard let selected = details.first else { errorMessage = "This game is no longer available."; return }
                select(selected)
                dismiss()
            } catch is CancellationError { return } catch {
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func gameRow(_ game: ProfileGame) -> some View {
        let isSelected = selectedIDs.contains(game.id)
        return Button {
            guard !isSelected, pendingGameID == nil else { return }
            errorMessage = nil
            pendingGameID = game.id
        } label: {
            HStack(spacing: 7) {
                Text(game.name).lineLimit(1)
                Spacer(minLength: 4)
                if isSelected { Image(systemName: "checkmark").font(.body.bold()) }
                if pendingGameID == game.id { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(game.name)
    }

    private func search() async {
        let input = normalizedQuery
        matches = []
        errorMessage = nil
        guard !input.isEmpty else {
            isSearching = false; lastActivatedQuery = nil; lastActivation = .now; return
        }
        isSearching = true
        do {
            if lastActivatedQuery != nil, let lastActivation {
                let remaining = Duration.milliseconds(500) - lastActivation.duration(to: .now)
                if remaining > .zero { try await Task.sleep(for: min(.milliseconds(200), remaining)) }
            }
            lastActivatedQuery = input; lastActivation = .now
            let value = try await editor.searchWidgetGames(query: input)
            try Task.checkCancellation()
            matches = value
        } catch is CancellationError { return } catch {
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}
