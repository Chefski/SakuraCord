import Foundation
import SakuraCordModels

/// Provider-owned pending settings follow the installed build's storage profile.
enum DiscordLocalPreferences {
    static var defaults: UserDefaults {
        guard let suite = SakuraCordStorageProfile.current.preferencesSuiteName else {
            return .standard
        }
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Unable to open isolated preview preferences")
        }
        return defaults
    }
}
