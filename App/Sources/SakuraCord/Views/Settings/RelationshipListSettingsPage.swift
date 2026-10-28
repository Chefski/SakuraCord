import SakuraCordModels
import SwiftUI

/// The relationship lists Privacy settings manages, as in Discord's
/// Ignore & Block settings.
enum ManagedRelationshipList: Hashable {
    case blocked
    case ignored

    var title: LocalizedStringResource {
        switch self {
        case .blocked: LocalizedStringResource("Blocked Accounts", bundle: #bundle)
        case .ignored: LocalizedStringResource("Ignored Accounts", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .blocked: "nosign"
        case .ignored: "eye.slash.circle"
        }
    }

    /// Block takes precedence, so a blocked account is never listed as ignored.
    func contains(_ relationship: Relationship) -> Bool {
        switch self {
        case .blocked: relationship.type == .blocked
        case .ignored: relationship.isIgnored
        }
    }
}

struct RelationshipListSettingsPage: View {
    let model: AppModel
    let list: ManagedRelationshipList

    @State private var searchText = ""

    private var relationships: [Relationship] {
        model.relationships.filter(list.contains).sorted {
            name(for: $0).localizedStandardCompare(name(for: $1)) == .orderedAscending
        }
    }

    var body: some View {
        let relationships = relationships
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = query.isEmpty ? relationships : relationships.filter { matches($0, query: query) }
        SettingsForm {
            Section {
                if relationships.isEmpty {
                    emptyState(ContentUnavailableView(
                        list == .blocked ? "No Blocked Accounts" : "No Ignored Accounts",
                        systemImage: list.systemImage
                    ))
                } else if visible.isEmpty {
                    emptyState(ContentUnavailableView.search(text: query))
                } else {
                    ForEach(visible) { relationship in
                        row(relationship)
                    }
                }
            } footer: {
                if let error = model.friends.actionError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text(list.title))
        .searchable(text: $searchText, prompt: Text("Search \(Text(list.title))", bundle: #bundle))
    }

    private func row(_ relationship: Relationship) -> some View {
        HStack(spacing: InterfaceScale.metric(10)) {
            AvatarView(name: name(for: relationship), url: relationship.user?.avatarURL, size: InterfaceScale.metric(32))
            VStack(alignment: .leading) {
                Text(name(for: relationship))
                if let user = relationship.user {
                    Text(user.tag).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(list == .blocked ? "Unblock" : "Unignore") {
                switch list {
                case .blocked: model.removeRelationship(with: relationship.id, as: .unblock)
                case .ignored: model.setUserIgnored(relationship.id, ignored: false, location: .settings)
                }
            }
            .disabled(model.friends.pendingUserIDs.contains(relationship.id))
        }
    }

    private func emptyState(_ view: some View) -> some View {
        view
            .frame(maxWidth: .infinity, minHeight: InterfaceScale.metric(260))
            .listRowInsets(EdgeInsets())
    }

    private func name(for relationship: Relationship) -> String {
        relationship.user.map(model.friendDisplayName) ?? relationship.id.description
    }

    private func matches(_ relationship: Relationship, query: String) -> Bool {
        name(for: relationship).localizedStandardContains(query)
            || relationship.user?.tag.localizedStandardContains(query) == true
    }
}
