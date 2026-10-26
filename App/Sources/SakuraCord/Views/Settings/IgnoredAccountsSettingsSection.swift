import SakuraCordModels
import SwiftUI

struct IgnoredAccountsSettingsSection: View {
    let model: AppModel

    private var relationships: [Relationship] {
        model.relationships.filter(\.isIgnored).sorted {
            ($0.user?.displayName ?? $0.id.description).localizedStandardCompare($1.user?.displayName ?? $1.id.description) == .orderedAscending
        }
    }

    var body: some View {
        Section("Ignored Accounts") {
            if relationships.isEmpty {
                Text("No ignored accounts").foregroundStyle(.secondary)
            }
            ForEach(relationships) { relationship in
                HStack {
                    VStack(alignment: .leading) {
                        Text(relationship.user.map(model.friendDisplayName) ?? relationship.id.description)
                        if let user = relationship.user { Text(user.tag).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Unignore") {
                        model.setUserIgnored(relationship.id, ignored: false, location: .settings)
                    }
                    .disabled(model.friends.pendingUserIDs.contains(relationship.id))
                }
            }
            if let error = model.friends.actionError { Text(error).foregroundStyle(.red) }
        }
        .task { model.loadRelationshipsIfNeeded(for: .all) }
    }
}
