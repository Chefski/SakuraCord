import Observation
import SakuraCordModels

@Observable
@MainActor
final class ProfileEditorGameSuggestions {
    var hasAttemptedLoad = false
    var isLoading = false
    var errorMessage: String?
    private(set) var isLoaded = false
    private(set) var visibleIDs: [ProfileGameWidgetKind: [String]] = [:]
    private var gameStack: [String] = []
    private var wantedStack: [String] = []

    func load(_ feeds: ProfileWidgetGameSuggestions, existing: [ProfileWidget]) {
        let selected = Set(existing.flatMap { widget -> [String] in
            if case let .games(_, games) = widget.content { return games.map(\.id) }
            return []
        })
        let fallback = feeds.fallbackGameIDs.shuffled()
        gameStack = feeds.gameIDs.filter { !selected.contains($0) } + fallback
        wantedStack = feeds.wantedGameIDs.filter { !selected.contains($0) } + fallback
        // Keep the official widget-type allocation order; each consumes six.
        for kind in [ProfileGameWidgetKind.rotation, .wanted, .liked, .favorite] {
            visibleIDs[kind] = take(6, for: kind)
        }
        // The official store also allocates slots for its three non-game types.
        gameStack.removeFirst(min(18, gameStack.count))
        isLoaded = true
        errorMessage = nil
    }

    func peekIDs(for kind: ProfileGameWidgetKind) -> [String] {
        Array((kind == .wanted ? wantedStack : gameStack).prefix(7))
    }

    func consume(_ id: String, for kind: ProfileGameWidgetKind) {
        guard var visible = visibleIDs[kind], let index = visible.firstIndex(of: id) else { return }
        visible.remove(at: index)
        visible += take(1, for: kind)
        visibleIDs[kind] = visible
    }

    func removeUnavailable(ids: Set<String>, for kind: ProfileGameWidgetKind) {
        guard !ids.isEmpty else { return }
        if kind == .wanted { wantedStack.removeAll { ids.contains($0) } } else { gameStack.removeAll { ids.contains($0) } }
        var visible = visibleIDs[kind, default: []].filter { !ids.contains($0) }
        visible += take(6 - visible.count, for: kind)
        visibleIDs[kind] = visible
    }

    private func take(_ count: Int, for kind: ProfileGameWidgetKind) -> [String] {
        if kind == .wanted {
            let result = Array(wantedStack.prefix(count))
            wantedStack.removeFirst(result.count)
            return result
        }
        let result = Array(gameStack.prefix(count))
        gameStack.removeFirst(result.count)
        return result
    }
}
