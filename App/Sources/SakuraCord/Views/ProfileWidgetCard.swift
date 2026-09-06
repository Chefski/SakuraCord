import SakuraCordModels
import SwiftUI

struct ProfileWidgetImageView: View {
    let url: URL?
    var animates = true
    var contentMode: ContentMode = .fit

    var body: some View {
        if let url { AnimatedRemoteImage(url: url, animates: animates, contentMode: contentMode) } else { Rectangle().fill(.primary.opacity(0.06)).accessibilityHidden(true) }
    }
}

struct ProfileWidgetCard: View {
    let widget: ProfileWidget
    let resources: ProfileWidgetResources?
    var animates = true
    var compact = false
    var editor: ProfileEditorState?
    var displayName = ""
    var openGame: ((ProfileGame) -> Void)?
    var connectApplication: ((ProfileApplicationWidget) -> Void)?

    var body: some View {
        switch widget.content {
        case let .application(id):
            if let configuration = resources?.applications.first(where: { $0.applicationID == id && $0.isPublished }) {
                ProfileApplicationWidgetCard(configuration: configuration, identity: resources?.identities.first { $0.id == id }, animates: animates, compact: compact,
                                             connection: resources?.connections?[configuration.connectionApplicationID ?? id],
                                             connect: connectionAction(configuration))
            } else if let error = resources?.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding(16)
            }
        case let .personal(personal):
            ProfilePersonalWidgetCard(id: widget.id, widget: personal, animates: animates, editor: editor)
        case let .games(kind, games):
            ProfileGameWidgetCard(widgetID: widget.id, kind: kind, games: games, records: resources?.games ?? [], animates: animates, editor: editor, displayName: displayName, openGame: openGame)
        case .unrecognized: EmptyView()
        }
    }

    private func connectionAction(_ configuration: ProfileApplicationWidget) -> (() -> Void)? {
        if let connectApplication { return { connectApplication(configuration) } }
        guard let editor else { return nil }
        return {
            guard editor.canEditWidgets, let url = configuration.connectionURL else { return }
            _ = MessageLinkActivator.activate(url, model: editor.model, displayedText: url.absoluteString)
        }
    }
}

struct ProfileWidgetsSection: View {
    var displayName = ""
    let widgets: [ProfileWidget]
    let resources: ProfileWidgetResources?
    var animates = true
    var openGame: ((ProfileGame) -> Void)?
    var connectApplication: ((ProfileApplicationWidget) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(widgets) { widget in
                ProfileWidgetCard(widget: widget, resources: resources, animates: animates, compact: true, displayName: displayName, openGame: openGame, connectApplication: connectApplication)
            }
        }
    }
}

extension ProfileGameWidgetKind {
    var title: String {
        switch self {
        case .favorite: String(localized: "Favourite Game", bundle: #bundle)
        case .rotation: String(localized: "Games in Rotation", bundle: #bundle)
        case .liked: String(localized: "Games I Like", bundle: #bundle)
        case .wanted: String(localized: "Want to Play", bundle: #bundle)
        }
    }
}
