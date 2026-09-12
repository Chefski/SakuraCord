import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileAddWidgetPicker: View {
    let editor: ProfileEditorState
    let selectApplication: (ProfileApplicationWidget) -> Void
    @Environment(\.windowModalContext) private var dismiss
    @State private var category = "Interests"
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Profile Widget", bundle: #bundle).font(.system(size: 20, weight: .semibold))
                Spacer()
                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { dismiss?() }
            }
            .padding(24)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(["Interests", "Game Stats"], id: \.self) { value in
                        Button { category = value } label: {
                            Text(value).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }
                        .buttonStyle(.plain)
                        .background(category == value ? Color.primary.opacity(0.1) : Color.clear, in: .rect(cornerRadius: 8))
                    }
                    Spacer(minLength: 0)
                }
                .padding(16).frame(width: 212)
                Divider()
                ScrollView {
                    VStack(spacing: 12) {
                        if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").font(.callout) }
                        if category == "Interests" {
                            ProfileInterestWidgetTemplates(editor: editor) { widget in editor.addWidget(widget); dismiss?() }
                        } else {
                            ForEach(availableApplications) { configuration in
                                ProfileApplicationWidgetTemplate(
                                    configuration: configuration,
                                    identity: editor.widgetResources?.identities.first { $0.id == configuration.applicationID },
                                    connection: editor.widgetResources?.connections?[configuration.connectionApplicationID ?? configuration.applicationID],
                                    connect: {
                                        if let url = configuration.connectionURL { _ = MessageLinkActivator.activate(
                                            url,
                                            model: editor.model,
                                            displayedText: url.absoluteString
                                        ) }
                                    },
                                    select: {
                                        selectApplication(configuration)
                                        dismiss?()
                                    }
                                )
                                .disabled(isLoading || !editor.canEditWidgets)
                            }
                        }
                        if isLoading { ProgressView().padding() }
                    }
                    .padding(24)
                }
            }
        }
        .windowModalSize(width: 680, height: 604)
        .task {
            do {
                try await editor.loadWidgetCatalogue()
                let ids = DiscordProfileWidgetTemplates.gameKinds.flatMap { DiscordProfileWidgetTemplates.artworkGameIDs(for: $0) }
                try await editor.loadWidgetGames(ids: ids)
            } catch is CancellationError { return } catch {
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var availableApplications: [ProfileApplicationWidget] {
        let existing = Set(editor.widgets.compactMap { widget -> String? in if case let .application(id) = widget.content { id } else { nil } })
        var seen = Set<String>()
        return editor.widgetCatalogue.filter { $0.isAddable && !existing.contains($0.applicationID) && seen.insert($0.applicationID).inserted }
    }
}

private struct ProfileInterestWidgetTemplates: View {
    let editor: ProfileEditorState
    let select: (ProfileWidget) -> Void

    var body: some View {
        if editor.canEditPersonalWidget, !hasPersonalWidget {
            Button {
                select(ProfileWidget(content: .personal(ProfilePersonalWidget(sections: [
                    .cover(ProfileWidgetCover()),
                    .fields((0 ..< 4).map { _ in ProfileWidgetField() })
                ]))))
            } label: {
                ProfilePersonalWidgetTemplate()
            }
            .buttonStyle(.plain).disabled(!editor.canEditWidgets)
        }
        ForEach(DiscordProfileWidgetTemplates.gameKinds, id: \.self) { kind in
            if !hasGameWidget(kind) {
                Button { select(ProfileWidget(content: .games(kind, []))) } label: {
                    ProfileGameWidgetTemplate(kind: kind, records: editor.widgetResources?.games ?? [])
                }
                .buttonStyle(.plain).disabled(!editor.canEditWidgets)
            }
        }
    }

    private var hasPersonalWidget: Bool { editor.widgets.contains { if case .personal = $0.content { true } else { false } } }
    private func hasGameWidget(_ kind: ProfileGameWidgetKind) -> Bool {
        editor.widgets.contains { if case let .games(value, _) = $0.content { value == kind } else { false } }
    }
}

private struct ProfilePersonalWidgetTemplate: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.08)).frame(height: 80)
                    .overlay { ProfileWidgetTemplateLabel(title: "Create your own", showsNitro: true) }
                HStack(spacing: 20) {
                    ProfileWidgetTemplateField()
                    ProfileWidgetTemplateField()
                }
            }
            .padding(16)
            HStack(spacing: 5) {
                Text("BETA", bundle: #bundle).font(.system(size: 10, weight: .bold))
                Text("Create your own custom widget with Nitro", bundle: #bundle).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient(colors: [.pink.opacity(0.25), .indigo.opacity(0.25)], startPoint: .leading, endPoint: .trailing))
        }
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 8)).clipShape(.rect(cornerRadius: 8))
    }
}

private struct ProfileWidgetTemplateField: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.08)).frame(width: 36, height: 36)
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)).frame(height: 14)
            }
        }
    }
}

private struct ProfileGameWidgetTemplate: View {
    let kind: ProfileGameWidgetKind
    let records: [ProfileGame]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(DiscordProfileWidgetTemplates.artworkGameIDs(for: kind), id: \.self) { id in
                ProfileWidgetImageView(url: records.first { $0.id == id }?.coverURL, animates: false, contentMode: .fill)
                    .frame(width: 84, height: 112).clipShape(.rect(cornerRadius: 8)).opacity(0.35)
            }
            if kind == .favorite || kind == .rotation {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)).frame(height: 20)
                    RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.08)).frame(height: 20)
                }
                .padding(.trailing, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 8))
        .overlay { ProfileWidgetTemplateLabel(title: kind.title) }
    }
}

private struct ProfileWidgetTemplateLabel: View {
    let title: String
    var showsNitro = false
    var showsLink = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: showsLink ? "link" : "plus.circle.fill").font(.system(size: 22))
            HStack(spacing: 4) {
                if showsNitro { Image(systemName: "sparkles").font(.system(size: 12)) }
                Text(title).font(.system(size: 14, weight: .medium))
            }
        }
    }
}

private struct ProfileApplicationWidgetTemplate: View {
    let configuration: ProfileApplicationWidget
    let identity: ProfileWidgetApplicationIdentity?
    let connection: ProfileWidgetConnection?
    let connect: () -> Void
    let select: () -> Void

    private var canLink: Bool { connection == .unlinked && configuration.connectionURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                ProfileApplicationWidgetTemplateArtwork(configuration: configuration, identity: identity)
                    .frame(height: 180).clipped().opacity(0.35)
                    .overlay { ProfileWidgetTemplateLabel(title: configuration.applicationName, showsLink: canLink) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(canLink ? "Link your \(configuration.applicationName) account to add widget" : "Add \(configuration.applicationName) Widget")
            HStack(spacing: 4) {
                Image(systemName: "gamecontroller")
                if canLink {
                    Button("Link your account", action: connect).buttonStyle(.link)
                    Text("to show off your game stats", bundle: #bundle)
                } else if case .linked = connection {
                    Text("Show off your \(configuration.applicationName) stats")
                } else {
                    Text("Link your account to show off your game stats", bundle: #bundle)
                }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}
