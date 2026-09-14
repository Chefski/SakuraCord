import AppKit
import SakuraCordModels
import SwiftUI

struct ProfileWidgetsBoard: View {
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
                            .overlay { widgetMenu(widget) }
                            .overlay(alignment: .topTrailing) {
                                widgetMenu(widget, isButton: true)
                                    .frame(width: 24, height: 24)
                                    .disabled(!editor.canEditWidgets)
                                    .padding(12)
                            }
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
                .escapeDismissiblePopover(isPresented: $showsAddPicker) {
                    ProfileAddWidgetPicker(editor: editor) { showsAddPicker = false }
                }
                .padding(10)
        }
        .onChange(of: editor.draftGeneration) { _, _ in showsAddPicker = false }
        .onChange(of: editor.isResolvingScope) { _, resolving in if resolving { showsAddPicker = false } }
        .windowModal(item: $removingWidget) { widget in
            ProfileRemoveWidgetConfirmation(widget: widget, resources: editor.widgetResources) {
                editor.removeWidget(id: widget.id); removingWidget = nil
            }
        }
    }

    private func widgetMenu(_ widget: ProfileWidget, isButton: Bool = false) -> some View {
        ProfileWidgetMenu(editor: editor, widgetID: widget.id, title: title(widget), isButton: isButton) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                editor.removeWidget(id: widget.id)
            } else { removingWidget = widget }
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
