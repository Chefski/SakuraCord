import SakuraCordModels
import SwiftUI

struct ProfileWidgetGameSuggestionsView: View {
    let editor: ProfileEditorState
    let kind: ProfileGameWidgetKind
    let dismiss: () -> Void
    let select: (String) -> Void

    private var ids: [String] { editor.gameSuggestions.visibleIDs[kind, default: []] }
    private var requestIDs: [String] { ids + editor.gameSuggestions.peekIDs(for: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 8)
            HStack(spacing: 6) {
                Text("Suggested for you", bundle: #bundle)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss suggestions")
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                    let game = editor.widgetResources?.games.first { $0.id == id }
                    ProfileSuggestedGameButton(game: game) { select(id) }
                        .disabled(game?.coverURL == nil || !editor.canEditWidgets)
                }
            }
            if editor.gameSuggestions.isLoading { ProgressView().controlSize(.small) }
            if let message = editor.gameSuggestions.errorMessage {
                HStack {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            if editor.gameSuggestions.isLoaded { await editor.resolveWidgetSuggestions(for: kind) } else {
                                editor.gameSuggestions.hasAttemptedLoad = false
                                await editor.loadWidgetSuggestionsIfNeeded()
                            }
                        }
                    }
                }
            }
        }
        .task(id: requestIDs) { await editor.resolveWidgetSuggestions(for: kind) }
    }
}

private struct ProfileSuggestedGameButton: View {
    let game: ProfileGame?
    let select: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: select) {
            ProfileWidgetGameCover(game: game, animates: false)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if isHovered || isFocused {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).shadow(radius: 3)
                    }
                }
        }
        .buttonStyle(.plain).focused($isFocused).onHover { isHovered = $0 }
        .accessibilityLabel("Add \(game?.name ?? "game")")
        .help("Add \(game?.name ?? "game")")
    }
}
