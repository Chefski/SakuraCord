import MessageRendering
import SakuraCordModels
import SwiftUI

struct ProfilePersonalWidgetCard: View {
    let id: String
    let widget: ProfilePersonalWidget
    let animates: Bool
    var editor: ProfileEditorState?
    @State private var expanded = false
    @State private var hasClippedText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 12))
                ProfileWidgetText(value: widget.header, placeholder: "Add Widget Name", limit: 50, lines: 1, size: 14, weight: .medium, markdown: false,
                                  edit: editor?.canEditWidgets == true ? { value in editor?.updatePersonalWidget(id: id) { $0.header = value } } : nil)
            }
            ForEach(Array(widget.sections.enumerated()), id: \.offset) { index, section in
                switch section {
                case let .cover(cover):
                    if !cover.isEmpty || editor?.canEditWidgets == true {
                        ProfilePersonalWidgetCover(id: id, section: index, cover: cover, animates: animates, editor: editor)
                    }
                case let .fields(fields):
                    ProfilePersonalWidgetFields(id: id, section: index, fields: fields, animates: animates, editor: editor)
                }
            }
            if let editor, editor.canEditWidgets, !widget.sections.contains(where: { if case .cover = $0 { true } else { false } }) {
                Button { editor.updatePersonalWidget(id: id) { $0.sections.insert(.cover(ProfileWidgetCover()), at: 0) } } label: {
                    Label("Add Cover", systemImage: "plus").frame(maxWidth: .infinity).padding(8)
                }.buttonStyle(.plain)
            }
            if expanded || hasClippedText {
                Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .medium))
            }
        }
        .environment(\.profileWidgetTextExpanded, expanded)
        .onPreferenceChange(ProfileWidgetClippedTextKey.self) { hasClippedText = $0.values.contains(true) }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: ConcentricRectangle(cornerRadius: 16))
    }
}

private struct ProfilePersonalWidgetCover: View {
    let id: String
    let section: Int
    let cover: ProfileWidgetCover
    let animates: Bool
    let editor: ProfileEditorState?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProfileWidgetText(value: cover.title, placeholder: "Add Title", limit: 50, lines: 2, size: 24, weight: .semibold,
                              edit: editor?.canEditWidgets == true ? { value in editor?.updateWidgetCover(id: id, section: section) { $0.title = value } } : nil)
            ProfileWidgetText(value: cover.subtitle, placeholder: "Add description", limit: 150, lines: 3, size: 14, weight: .medium,
                              edit: editor?.canEditWidgets == true ? { value in editor?.updateWidgetCover(id: id, section: section) { $0.subtitle = value } } : nil)
        }
        .frame(maxWidth: .infinity, minHeight: cover.image != nil || editor != nil ? 54 : nil, alignment: .bottomLeading)
        .padding(cover.image != nil || editor != nil ? 16 : 0)
        .padding(.top, cover.image != nil || editor != nil ? 56 : 0)
        .foregroundStyle(cover.image == nil ? Color.primary : .white)
        .background {
            if cover.image != nil || editor?.canEditWidgets == true {
                GeometryReader { geometry in
                    ProfileWidgetEditableImage(image: cover.image, purpose: .widgetCover, animates: animates, editor: editor,
                                               aspectRatio: geometry.size.width / max(geometry.size.height, 1)) { image in
                        editor?.updateWidgetCover(id: id, section: section) { $0.image = image }
                    }
                    .overlay {
                        if cover.image != nil {
                            LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if let editor, editor.canEditWidgets, cover.image == nil {
                Button {
                    editor.updatePersonalWidget(id: id) { value in
                        guard value.sections.indices.contains(section), case .cover = value.sections[section] else { return }
                        value.sections.remove(at: section)
                    }
                } label: { Image(systemName: "trash").padding(6) }
                .buttonStyle(.plain).background(.regularMaterial, in: .circle).padding(8).accessibilityLabel("Remove Block")
            }
        }
    }
}

private struct ProfilePersonalWidgetFields: View {
    let id: String
    let section: Int
    let fields: [ProfileWidgetField]
    let animates: Bool
    let editor: ProfileEditorState?

    var body: some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 16), .init(.flexible(), spacing: 16)], alignment: .leading, spacing: 16) {
            ForEach(fields.filter { !$0.isEmpty || editor?.canEditWidgets == true }) { field in
                ProfilePersonalWidgetField(id: id, section: section, field: field, animates: animates, editor: editor)
            }
            if let editor, editor.canEditWidgets, fields.count % 2 == 1, fields.count < 4 {
                Button { editor.addWidgetFields(id: id, section: section, count: 1) } label: { Label("Add field", systemImage: "plus") }
                    .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        if let editor, editor.canEditWidgets, fields.count % 2 == 0, fields.count < 4 {
            Button { editor.addWidgetFields(id: id, section: section, count: 2) } label: {
                Label("Add Blocks", systemImage: "plus").frame(maxWidth: .infinity).padding(8)
            }.buttonStyle(.plain)
        }
    }
}

private struct ProfilePersonalWidgetField: View {
    let id: String
    let section: Int
    let field: ProfileWidgetField
    let animates: Bool
    let editor: ProfileEditorState?
    @State private var hidesImage = false

    init(id: String, section: Int, field: ProfileWidgetField, animates: Bool, editor: ProfileEditorState?) {
        self.id = id; self.section = section; self.field = field; self.animates = animates; self.editor = editor
        let original = editor?.snapshot?.presentation.widgets?.first { $0.id == id }
        let savedField: Bool
        if case let .personal(personal) = original?.content {
            savedField = personal.sections.contains { value in
                if case let .fields(fields) = value { return fields.contains { $0.id == field.id } }
                return false
            }
        } else { savedField = false }
        _hidesImage = State(initialValue: field.image == nil && savedField)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if field.image != nil || (editor?.canEditWidgets == true && !hidesImage) {
                ProfileWidgetEditableImage(image: field.image, purpose: .widgetField, animates: animates, editor: editor, aspectRatio: 1) { image in
                    editor?.updateWidgetField(id: id, section: section, fieldID: field.id) { $0.image = image }
                }
                .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
                .contextMenu {
                    if editor?.canEditWidgets == true, field.image == nil { Button("Remove Image") { hidesImage = true } }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ProfileWidgetText(value: field.title, placeholder: "Add title", limit: 40, lines: 2, size: 14, weight: .medium,
                                  edit: editor?.canEditWidgets == true ? { value in editor?.updateWidgetField(id: id, section: section, fieldID: field.id) { $0.title = value } } : nil)
                ProfileWidgetText(value: field.description, placeholder: "Add description", limit: 90, lines: 4, size: 12,
                                  edit: editor?.canEditWidgets == true ? { value in editor?.updateWidgetField(id: id, section: section, fieldID: field.id) { $0.description = value } } : nil)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if let editor, editor.canEditWidgets {
                if hidesImage { Button("Add Image") { hidesImage = false } }
                Button("Remove Block", role: .destructive) { editor.removeWidgetField(id: id, section: section, fieldID: field.id) }
            }
        }
    }
}

struct ProfileWidgetText: View {
    let value: String
    let placeholder: LocalizedStringKey
    let limit: Int
    let lines: Int
    let size: CGFloat
    var weight: Font.Weight = .regular
    var markdown = true
    var edit: ((String) -> Void)?
    @Environment(\.profileWidgetTextExpanded) private var expanded
    @State private var measurementID = UUID()
    @State private var fullHeight: CGFloat = 0
    @State private var displayedHeight: CGFloat = 0
    @State private var draft = ""
    @State private var originalValue = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(placeholder, text: Binding(get: { draft }, set: updateDraft), axis: lines > 1 ? .vertical : .horizontal)
                    .textFieldStyle(.plain).lineLimit(1 ... lines).focused($focused)
                    .onKeyPress(.return, phases: .down) { event in
                        guard lines == 1 || !event.modifiers.contains(.shift) else { return .ignored }
                        commit(); return .handled
                    }
                    .onKeyPress(.escape, phases: .down) { _ in cancel(); return .handled }
                    .onExitCommand(perform: cancel)
                    .onChange(of: focused) { _, value in if !value { commit() } }
            } else if edit != nil {
                Button { originalValue = value; draft = value; isEditing = true; focused = true } label: {
                    if value.isEmpty { Text(placeholder).italic().foregroundStyle(.secondary) } else { renderedText }
                }.buttonStyle(.plain).accessibilityLabel(placeholder).accessibilityValue(value)
            } else if !value.isEmpty { renderedText }
        }
        .font(.system(size: size, weight: weight))
        .preference(key: ProfileWidgetClippedTextKey.self, value: [measurementID: !isEditing && fullHeight - displayedHeight > 1])
        .onChange(of: edit != nil) { _, available in
            if !available { isEditing = false; focused = false }
        }
        .onChange(of: value) { _, value in
            guard isEditing, value != draft.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            draft = value
            isEditing = false; focused = false
        }
    }

    private var renderedText: some View {
        let content = markdown
            ? DiscordMarkdown.profileWidgetAttributed(value, font: .system(size: size, weight: weight), links: edit == nil)
            : AttributedString(value)
        return Text(content)
            .lineLimit(expanded ? nil : lines)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { displayedHeight = $0 }
            .background(alignment: .topLeading) {
                Text(content).fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    .hidden().accessibilityHidden(true).allowsHitTesting(false)
            }
            .environment(\.openURL, OpenURLAction { url in
                _ = MessageLinkActivator.activate(url, model: nil, displayedText: nil)
                return .handled
            })
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false; focused = false
    }

    private func updateDraft(_ value: String) {
        guard isEditing else { return }
        var length = 0
        draft = String(value.prefix { length += $0.utf16.count; return length <= limit })
        edit?(draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func cancel() {
        guard isEditing else { return }
        draft = originalValue
        isEditing = false; focused = false
        edit?(originalValue)
    }
}

private extension EnvironmentValues {
    @Entry var profileWidgetTextExpanded = false
}

private struct ProfileWidgetClippedTextKey: PreferenceKey {
    static let defaultValue: [UUID: Bool] = [:]
    static func reduce(value: inout [UUID: Bool], nextValue: () -> [UUID: Bool]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
