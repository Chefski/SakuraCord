import AppKit
import SakuraCordModels
import SwiftUI

struct ProfileWidgetsBoard: View {
    let model: AppModel
    let editor: ProfileEditorState
    @State private var showsAddPicker = false
    @State private var removingWidget: ProfileWidget?

    var body: some View {
        ProfileWidgetBoardViewport {
            VStack(spacing: 12) {
                ForEach(editor.widgets) { widget in
                    // Keep a stable outer identity around the card's conditional
                    // content and menus for SwiftUI's reorder container.
                    VStack(spacing: 0) {
                        ProfileWidgetCard(widget: widget, resources: editor.widgetResources, editor: editor, displayName: editor.name)
                            .overlay(alignment: .topTrailing) {
                                Menu { managementActions(widget) } label: {
                                    Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle())
                                }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .accessibilityLabel("Manage widget: \(title(widget))")
                                .disabled(!editor.canEditWidgets)
                                .padding(8)
                            }
                            .contextMenu { managementActions(widget) }
                    }
                    .contentShape(.interaction, .rect(cornerRadius: 16))
                    .contentShape(.dragPreview, .rect(cornerRadius: 16))
                }
                .reorderable()
            }
            .reorderContainer(for: ProfileWidget.self, isEnabled: editor.canEditWidgets) { difference in
                let before: String?
                switch difference.destination.position {
                case let .before(id): before = id
                case .end: before = nil
                }
                editor.moveWidgets(difference.sources, before: before)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showsAddPicker = true } label: { Label("Add Widget", systemImage: "plus") }
                .disabled(!editor.canEditWidgets)
                .padding(10)
        }
        .task(id: editor.scope) { await editor.loadWidgetSuggestionsIfNeeded() }
        .windowModal(isPresented: $showsAddPicker) {
            ProfileAddWidgetPicker(editor: editor) { configuration in
                editor.addWidget(ProfileWidget(content: .application(id: configuration.applicationID)))
                let connection = editor.widgetResources?.connections?[configuration.connectionApplicationID ?? configuration.applicationID]
                if connection == .unlinked, let url = configuration.connectionURL {
                    _ = MessageLinkActivator.activate(url, model: model, displayedText: url.absoluteString)
                }
            }
        }
        .windowModal(item: $removingWidget) { widget in
            ProfileRemoveWidgetConfirmation(widget: widget, resources: editor.widgetResources) {
                editor.removeWidget(id: widget.id); removingWidget = nil
            }
        }
    }

    @ViewBuilder private func managementActions(_ widget: ProfileWidget) -> some View {
        Button("Remove Widget", role: .destructive) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                editor.removeWidget(id: widget.id)
            } else { removingWidget = widget }
        }
        .disabled(!editor.canEditWidgets)
        if let index = editor.widgets.firstIndex(where: { $0.id == widget.id }) {
            Button("Move Up") { editor.moveWidget(id: widget.id, to: index - 1) }
                .disabled(!editor.canEditWidgets || index == 0)
            Button("Move Down") { editor.moveWidget(id: widget.id, to: index + 1) }
                .disabled(!editor.canEditWidgets || index == editor.widgets.count - 1)
        }
    }

    private func title(_ widget: ProfileWidget) -> String {
        switch widget.content {
        case let .personal(personal): personal.header.isEmpty ? String(localized: "Personal", bundle: #bundle) : personal.header
        case let .games(kind, _): kind.title
        case let .application(id): editor.widgetResources?.applications.first { $0.applicationID == id }?.applicationName ?? "Widget"
        case .unrecognized: "Widget"
        }
    }
}

private struct ProfileRemoveWidgetConfirmation: View {
    let widget: ProfileWidget
    let resources: ProfileWidgetResources?
    let remove: () -> Void
    @Environment(\.windowModalContext) private var dismiss

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
        .padding(24).windowModalSize(width: 440)
    }
}
