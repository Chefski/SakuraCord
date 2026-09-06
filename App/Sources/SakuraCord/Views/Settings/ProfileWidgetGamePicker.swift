import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileWidgetGamePicker: View {
    let editor: ProfileEditorState
    let selectedIDs: Set<String>
    let select: (ProfileGame) -> Void
    @Environment(\.profileEditorModal) private var dismiss
    @State private var query = ""
    @State private var defaults: [ProfileGame] = []
    @State private var matches: [ProfileGame] = []
    @State private var isLoadingDefaults = true
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var lastActivatedQuery: String?
    @State private var lastActivation: ContinuousClock.Instant?
    @FocusState private var searchFocused: Bool
    private var normalizedQuery: String { DiscordProfileWidgetGameSearch.normalizedQuery(query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused).padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaults : matches) { game in
                        Button {
                            Task {
                                do {
                                    let details = try await editor.loadWidgetGames(ids: [game.id])
                                    guard let selected = details.first else { errorMessage = "This game is no longer available."; return }
                                    select(selected); dismiss?()
                                } catch { errorMessage = error.localizedDescription }
                            }
                        } label: {
                            Text(game.name).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                        }
                        .buttonStyle(.plain).disabled(selectedIDs.contains(game.id))
                    }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? isLoadingDefaults : isSearching { ProgressView().frame(maxWidth: .infinity).padding() }
                    if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red).padding(12) }
                }
            }
        }
        .profileEditorModalSize(width: 400, height: 360)
        .task {
            searchFocused = true
            do { defaults = try await editor.defaultWidgetGames() } catch is CancellationError { return } catch { errorMessage = error.localizedDescription }
            isLoadingDefaults = false
        }
        .task(id: normalizedQuery) {
            let input = normalizedQuery
            guard !input.isEmpty else {
                isSearching = false; lastActivatedQuery = nil; lastActivation = .now; matches = []; return
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
                matches = value; errorMessage = nil
            } catch is CancellationError { return } catch { errorMessage = error.localizedDescription }
            isSearching = false
        }
    }
}
