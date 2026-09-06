import AppKit
import SakuraCordModels
import SwiftUI

struct ProfileWidgetsBoard: View {
    let model: AppModel
    let editor: ProfileEditorState
    @State private var showsAddPicker = false
    @State private var removingWidget: ProfileWidget?
    @State private var reorderingID: String?
    @State private var originalOrder: [ProfileWidget]?
    @FocusState private var focusedWidgetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your Widgets", bundle: #bundle).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button { showsAddPicker = true } label: { Label("Add Widget", systemImage: "plus") }
                            .disabled(!editor.canEditWidgets)
                    }
                    .padding(.bottom, 4)
                    ForEach(editor.widgets) { widget in
                        ProfileWidgetCard(widget: widget, resources: editor.widgetResources, editor: editor, displayName: editor.name)
                            .overlay(alignment: .topLeading) {
                                ProfileWidgetManageHandle(
                                    id: widget.id, title: title(widget), isEnabled: editor.canEditWidgets,
                                    focused: $focusedWidgetID,
                                    remove: {
                                        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { editor.removeWidget(id: widget.id) } else { removingWidget = widget }
                                    },
                                    beginReordering: { originalOrder = editor.widgets; reorderingID = widget.id; focusedWidgetID = widget.id }
                                )
                            }
                            .overlay { if reorderingID == widget.id { ConcentricRectangle(cornerRadius: 16).stroke(.tint, lineWidth: 2) } }
                            .dropDestination(for: ProfileWidgetDragPayload.self, isEnabled: editor.canEditWidgets) { values, _ in
                                guard editor.canEditWidgets, let id = values.first?.id, editor.widgets.contains(where: { $0.id == id }),
                                      let target = editor.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
                                editor.moveWidget(id: id, to: target)
                            }
                    }
        }
        .padding(.leading, 24)
        .frame(maxWidth: .infinity)
        .task(id: editor.scope) { await editor.loadWidgetSuggestionsIfNeeded() }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) {
            guard reorderingID != nil else { return .ignored }
            reorderingID = nil; originalOrder = nil; return .handled
        }
        .onKeyPress(.escape) {
            guard reorderingID != nil else { return .ignored }
            if let originalOrder { editor.setWidgets(originalOrder) }
            reorderingID = nil; originalOrder = nil; return .handled
        }
        .profileEditorOverlay(isPresented: $showsAddPicker) {
            ProfileAddWidgetPicker(editor: editor) { configuration in
                editor.addWidget(ProfileWidget(content: .application(id: configuration.applicationID)))
                let connection = editor.widgetResources?.connections?[configuration.connectionApplicationID ?? configuration.applicationID]
                if connection == .unlinked, let url = configuration.connectionURL { _ = MessageLinkActivator.activate(url, model: model, displayedText: url.absoluteString) }
            }
        }
        .profileEditorOverlay(item: $removingWidget) { widget in
            ProfileRemoveWidgetConfirmation(widget: widget, resources: editor.widgetResources) {
                editor.removeWidget(id: widget.id); removingWidget = nil
            }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard let id = reorderingID, let index = editor.widgets.firstIndex(where: { $0.id == id }) else { return .ignored }
        editor.moveWidget(id: id, to: index + offset)
        focusedWidgetID = id
        return .handled
    }

    private func title(_ widget: ProfileWidget) -> String {
        switch widget.content {
        case let .personal(personal): personal.header
        case let .games(kind, _): kind.title
        case let .application(id): editor.widgetResources?.applications.first { $0.applicationID == id }?.applicationName ?? "Widget"
        case .unrecognized: "Widget"
        }
    }
}

private struct ProfileWidgetManageHandle: View {
    let id: String
    let title: String
    let isEnabled: Bool
    let focused: FocusState<String?>.Binding
    let remove: () -> Void
    let beginReordering: () -> Void

    var body: some View {
        ProfileWidgetDragMenuButton(id: id, title: title, isEnabled: isEnabled, remove: remove)
        .frame(width: 20, height: 28).offset(x: -25, y: 8)
        .accessibilityLabel("Manage widget: \(title)")
        .help("Click to manage; press Command-D to start reordering")
        .focusable(interactions: .edit)
        .focused(focused, equals: id)
        .onKeyPress("d", phases: .down) { event in
            guard event.modifiers.contains(.command) || event.modifiers.contains(.control) else { return .ignored }
            beginReordering(); return .handled
        }
        .disabled(!isEnabled)
    }
}

private struct ProfileRemoveWidgetConfirmation: View {
    let widget: ProfileWidget
    let resources: ProfileWidgetResources?
    let remove: () -> Void
    @Environment(\.profileEditorModal) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Remove Widget", bundle: #bundle).font(.title2.bold())
                Spacer()
                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
            }
            Text("Are you sure you want to remove this Widget? All data from this Widget will be permanently deleted.", bundle: #bundle)
            ProfileWidgetCard(widget: widget, resources: resources, animates: false).frame(maxHeight: 160).clipped()
            Text("Pro tip: You can hold down shift when clicking Remove to bypass this confirmation entirely.", bundle: #bundle)
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss?() }
                Button("Remove Widget", role: .destructive, action: remove).buttonStyle(.borderedProminent)
            }
        }
        .padding(24).profileEditorModalSize(width: 440)
    }
}
