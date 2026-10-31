import Foundation
import Observation
import SakuraCordModels

nonisolated struct SettingsNavigationRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let destination: SettingsDestination
    let controlID: SettingsControlID
    /// The profile to show when the request opens Profiles.
    var profileScope: ProfileEditingScope?
}

@Observable
final class SettingsNavigationRouter {
    static let shared = SettingsNavigationRouter()

    private(set) var request: SettingsNavigationRequest?

    private init() {}

    func open(
        page: SettingsPageID,
        section: SettingsSectionID? = nil,
        controlID: SettingsControlID? = nil,
        profileScope: ProfileEditingScope? = nil
    ) {
        request = SettingsNavigationRequest(
            id: UUID(),
            destination: SettingsDestination(page: page, section: section),
            controlID: controlID ?? .overview(page),
            profileScope: profileScope
        )
    }

    func consume(_ id: UUID) {
        guard request?.id == id else { return }
        request = nil
    }
}
