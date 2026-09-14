import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileAddWidgetPicker: View {
    let editor: ProfileEditorState
    let dismiss: () -> Void

    private var canAddPersonalWidget: Bool { editor.canEditPersonalWidget && !hasPersonalWidget }
    private var availableGameKinds: [ProfileGameWidgetKind] {
        DiscordProfileWidgetTemplates.gameKinds.filter { !hasGameWidget($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if canAddPersonalWidget {
                option("Create your own", systemImage: "square.and.pencil") {
                    add(ProfileWidget(content: .personal(ProfilePersonalWidget(sections: [
                        .cover(ProfileWidgetCover()),
                        .fields((0 ..< 4).map { _ in ProfileWidgetField() })
                    ]))))
                }
            }
            ForEach(availableGameKinds, id: \.self) { kind in
                option(kind.title, systemImage: icon(for: kind)) {
                    add(ProfileWidget(content: .games(kind, [])))
                }
            }
            if !canAddPersonalWidget, availableGameKinds.isEmpty {
                Text("No more widgets to add", bundle: #bundle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .padding(4)
        .frame(width: 264)
        .disabled(!editor.canEditWidgets)
    }

    private func option(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage).frame(width: 20)
                Text(title)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowButtonStyle())
        .help("Add \(title)")
    }

    private func add(_ widget: ProfileWidget) {
        editor.addWidget(widget)
        dismiss()
    }

    private var hasPersonalWidget: Bool { editor.widgets.contains { if case .personal = $0.content { true } else { false } } }
    private func hasGameWidget(_ kind: ProfileGameWidgetKind) -> Bool {
        editor.widgets.contains { if case let .games(value, _) = $0.content { value == kind } else { false } }
    }

    private func icon(for kind: ProfileGameWidgetKind) -> String {
        switch kind {
        case .favorite: "star"
        case .liked: "heart"
        case .rotation: "arrow.trianglehead.2.clockwise.rotate.90"
        case .wanted: "bookmark"
        }
    }
}
