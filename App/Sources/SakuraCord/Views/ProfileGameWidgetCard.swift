import SakuraCordModels
import SwiftUI

struct ProfileGameWidgetCard: View {
    let widgetID: String
    let kind: ProfileGameWidgetKind
    let games: [ProfileWidgetGame]
    let records: [ProfileGame]
    let animates: Bool
    var editor: ProfileEditorState?
    var displayName = ""
    var openGame: ((ProfileGame) -> Void)?
    @State private var selectedGame: ProfileGame?
    @State private var expanded = false
    @State private var showsPicker = false
    @State private var dismissedSuggestions = false
    @State private var reorderingID: String?
    @State private var originalGameOrder: [String] = []
    @FocusState private var focusedGameID: String?

    private var isGrid: Bool { kind == .liked || kind == .wanted }

    private var showsSuggestions: Bool {
        guard let editor, editor.canEditWidgets, !dismissedSuggestions, games.count < kind.capacity else { return false }
        return editor.snapshot?.presentation.widgets?.contains { widget in
            if case let .games(savedKind, _) = widget.content { return savedKind == kind }
            return false
        } != true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.system(size: 14, weight: .medium))
                    if editor != nil, !games.isEmpty {
                        Text(kind == .favorite ? "Choose 1 game" : "Add up to \(kind.capacity) games").font(.system(size: 12))
                    }
                }
                Spacer()
                if editor != nil, kind != .favorite {
                    Button { showsPicker = true } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                        .disabled(editor?.canEditWidgets != true || games.count >= kind.capacity)
                        .accessibilityLabel("Add Game")
                }
            }
            .padding(.trailing, editor == nil ? 0 : 24)
            if isGrid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(Array(games.prefix(expanded ? 20 : 8))) { game in
                        ProfileWidgetGameLink(game: records.first { $0.id == game.id }, animates: animates, open: gameAction)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .modifier(ProfileWidgetGameRemoval(isEnabled: editor?.canEditWidgets == true) { editor?.removeWidgetGame(widgetID: widgetID, gameID: game.id) })
                            .overlay(alignment: .bottomLeading) {
                                if editor?.canEditWidgets == true {
                                    ProfileWidgetGameReorderHandle(game: game, name: records.first { $0.id == game.id }?.name,
                                                                  focused: $focusedGameID, begin: { beginReordering(game.id) })
                                        .padding(4)
                                }
                            }
                            .overlay { if reorderingID == game.id { RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2) } }
                            .dropDestination(for: String.self, isEnabled: editor?.canEditWidgets == true) { values, _ in drop(values, at: game.id) }
                    }
                }
                if games.count > 8 {
                    Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                }
            } else {
                ForEach(Array(games.prefix(expanded ? kind.capacity : 2))) { game in
                    ProfileWidgetGameRow(
                        game: game, record: records.first { $0.id == game.id }, kind: kind,
                        animates: animates, displayName: displayName,
                        editable: editor?.canEditWidgets == true,
                        reordering: reorderingID == game.id, focused: $focusedGameID,
                        update: { editor?.updateWidgetGame(widgetID: widgetID, game: $0) },
                        remove: { editor?.removeWidgetGame(widgetID: widgetID, gameID: game.id) },
                        beginReordering: { beginReordering(game.id) }, openGame: gameAction
                    )
                    .dropDestination(for: String.self, isEnabled: editor?.canEditWidgets == true) { values, _ in drop(values, at: game.id) }
                }
                if kind == .rotation, games.count > 2 {
                    Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
                        .buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                }
            }
            if let editor, editor.canEditWidgets, games.isEmpty {
                if kind == .favorite {
                    HStack(spacing: 16) {
                        Button { showsPicker = true } label: {
                            Image(systemName: "plus").font(.system(size: 24)).frame(width: 84, height: 112)
                                .background(.primary.opacity(0.05), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Add Game")
                        Text("Add one game. This Widget won't show up on your profile until you add a game.", bundle: #bundle)
                            .font(.system(size: 12))
                    }
                } else {
                    Text("Add up to \(kind.capacity) games. This Widget won't show up on your profile until you add at least 1 game.")
                        .font(.system(size: 12)).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
            }
            if showsSuggestions, let editor {
                ProfileWidgetGameSuggestionsView(editor: editor, kind: kind, dismiss: { dismissedSuggestions = true }, select: { id in
                    editor.addWidgetGame(widgetID: widgetID, gameID: id)
                    editor.gameSuggestions.consume(id, for: kind)
                    expanded = true
                })
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: ConcentricRectangle(cornerRadius: 16))
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { event in
            guard editor?.canEditWidgets == true, let id = reorderingID,
                  let index = games.firstIndex(where: { $0.id == id }) else { return .ignored }
            let offset: Int
            switch event.key {
            case .upArrow: offset = isGrid ? -4 : -1
            case .downArrow: offset = isGrid ? 4 : 1
            case .leftArrow: guard isGrid else { return .ignored }; offset = -1
            case .rightArrow: guard isGrid else { return .ignored }; offset = 1
            default: return .ignored
            }
            editor?.moveWidgetGame(widgetID: widgetID, gameID: id, to: index + offset)
            focusedGameID = id
            return .handled
        }
        .onKeyPress(.return) {
            guard reorderingID != nil else { return .ignored }
            reorderingID = nil; originalGameOrder = []; return .handled
        }
        .onKeyPress(.escape) {
            guard reorderingID != nil else { return .ignored }
            editor?.restoreWidgetGameOrder(widgetID: widgetID, ids: originalGameOrder)
            reorderingID = nil; originalGameOrder = []; return .handled
        }
        .windowModal(item: $selectedGame) { game in
            if let editor { ProfileGameView(model: editor.model, game: game, editor: editor) }
        }
        .windowModal(isPresented: $showsPicker, title: "Add Game") {
            if let editor {
                ProfileWidgetGamePicker(editor: editor, selectedIDs: Set(games.map(\.id))) {
                    editor.addWidgetGame(widgetID: widgetID, gameID: $0.id); expanded = true
                }
            }
        }
    }

    private var gameAction: ((ProfileGame) -> Void)? {
        if let editor { return { game in guard !editor.isSaving else { return }; selectedGame = game } }
        return openGame
    }

    private func beginReordering(_ id: String) {
        guard editor?.canEditWidgets == true else { return }
        originalGameOrder = games.map(\.id)
        reorderingID = id
        focusedGameID = id
    }

    private func drop(_ values: [String], at targetID: String) {
        guard editor?.canEditWidgets == true, let id = values.first,
              games.contains(where: { $0.id == id }), let target = games.firstIndex(where: { $0.id == targetID }) else { return }
        editor?.moveWidgetGame(widgetID: widgetID, gameID: id, to: target)
        focusedGameID = id
    }
}

private struct ProfileWidgetGameRow: View {
    let game: ProfileWidgetGame
    let record: ProfileGame?
    let kind: ProfileGameWidgetKind
    let animates: Bool
    let displayName: String
    let editable: Bool
    let reordering: Bool
    let focused: FocusState<String?>.Binding
    let update: (ProfileWidgetGame) -> Void
    let remove: () -> Void
    let beginReordering: () -> Void
    var openGame: ((ProfileGame) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ProfileWidgetGameLink(game: record, animates: animates, open: openGame)
                .frame(width: 88, height: 116)
                .modifier(ProfileWidgetGameRemoval(isEnabled: editable, action: remove))
                .overlay(alignment: .bottomLeading) {
                    if editable, kind == .rotation {
                        ProfileWidgetGameReorderHandle(game: game, name: record?.name, focused: focused, begin: beginReordering).padding(4)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    if let record, let openGame, record.metadata?.isProfileAvailable != false {
                        Button(record.name) { openGame(record) }.buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                    } else { Text(record?.name ?? "Game").font(.system(size: 14, weight: .medium)) }
                    Spacer(minLength: 0)
                }
                ProfileWidgetGameComment(comment: game.comment, displayName: displayName, editable: editable && kind == .favorite) { value in
                    var updated = game
                    updated.comment = value
                    updated.includesComment = value != nil
                    update(updated)
                }
                ProfileWidgetGameTags(tags: game.tags ?? [], update: editable ? { tags in
                    var updated = game
                    updated.tags = tags; updated.includesTags = true
                    update(updated)
                } : nil)
            }
        }
        .overlay { if reordering { RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2) } }
    }
}

private struct ProfileWidgetGameReorderHandle: View {
    let game: ProfileWidgetGame
    let name: String?
    let focused: FocusState<String?>.Binding
    let begin: () -> Void

    var body: some View {
        Button(action: begin) { Image(systemName: "line.3.horizontal").padding(5) }
            .buttonStyle(.plain).background(.regularMaterial, in: .rect(cornerRadius: 4))
            .focusable(interactions: .edit)
            .focused(focused, equals: game.id).draggable(game.id)
            .accessibilityLabel("Reorder \(name ?? "game")")
            .help("Drag to reorder, or press Command-D and use the arrow keys. Enter confirms; Escape cancels.")
            .onKeyPress("d", phases: .down) { event in
                guard event.modifiers.contains(.command) || event.modifiers.contains(.control) else { return .ignored }
                begin(); return .handled
            }
    }
}

private struct ProfileWidgetGameComment: View {
    let comment: String?
    let displayName: String
    let editable: Bool
    let update: (String?) -> Void
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editable || !(comment ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label {
                        Text("\(displayName) says:")
                    } icon: { Image(systemName: "quote.opening") }
                    .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    if editable {
                        Button(action: beginEditing) { Image(systemName: "pencil") }
                            .buttonStyle(.plain).accessibilityLabel("Edit game comment")
                    }
                }
                if isEditing {
                    TextField("Add a comment", text: Binding(get: { draft }, set: updateDraft), axis: .vertical)
                        .lineLimit(3 ... 3).textFieldStyle(.plain).focused($focused)
                        .onSubmit(commit)
                        .onKeyPress(.return, phases: .down) { event in
                            guard !event.modifiers.contains(.shift) else { return .ignored }
                            commit(); return .handled
                        }
                        .onChange(of: focused) { _, value in if !value { commit() } }
                        .onDisappear { commit() }
                } else if editable {
                    Button(action: beginEditing) { Text((comment ?? "").isEmpty ? "Add a comment" : comment ?? "") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .profileEditorTextHover()
                } else if let comment { Text(comment).foregroundStyle(.secondary) }
            }
            .font(.system(size: 12))
            .onChange(of: editable) { _, available in
                if !available { isEditing = false; focused = false }
            }
            .onChange(of: comment) { _, value in
                guard isEditing, value ?? "" != draft.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                draft = value ?? ""
                isEditing = false; focused = false
            }
        }
    }

    private func beginEditing() {
        draft = comment ?? ""; isEditing = true; focused = true
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false; focused = false
    }

    private func updateDraft(_ value: String) {
        guard isEditing else { return }
        var length = 0
        draft = String(value.prefix { length += $0.utf16.count; return length <= 200 })
        let comment = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        update(comment.isEmpty ? nil : comment)
    }
}

private struct ProfileWidgetGameRemoval: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isEnabled, isHovered {
                    HoverActionPill {
                        HoverActionButton(systemImage: "trash", help: String(localized: "Remove Game", bundle: #bundle), role: .destructive, action: action)
                    }.padding(4)
                }
            }
            .onModalHover { isHovered = $0 }
    }
}

struct ProfileWidgetGameCover: View {
    let game: ProfileGame?
    let animates: Bool

    var body: some View {
        ProfileWidgetImageView(url: game?.coverURL, animates: animates, contentMode: .fill)
            .clipShape(.rect(cornerRadius: 8)).accessibilityLabel(game?.name ?? String(localized: "Game", bundle: #bundle))
            .help(game?.name ?? "")
    }
}

private struct ProfileWidgetGameLink: View {
    let game: ProfileGame?
    let animates: Bool
    let open: ((ProfileGame) -> Void)?
    var body: some View {
        if let game, let open, game.metadata?.isProfileAvailable != false {
            Button { open(game) } label: { ProfileWidgetGameCover(game: game, animates: animates) }.buttonStyle(.plain)
        } else { ProfileWidgetGameCover(game: game, animates: animates) }
    }
}
