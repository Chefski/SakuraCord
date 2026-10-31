import Foundation
import SakuraCordModels

nonisolated enum PRBuildProfile {
    static var savedAccountMetadataSource: UserDefaults? {
        SakuraCordStorageProfile.current.previewIdentifier == nil ? nil : .standard
    }

    static var defaults: UserDefaults {
        defaults(for: .current)
    }

    static func defaults(for profile: SakuraCordStorageProfile) -> UserDefaults {
        guard let suite = profile.preferencesSuiteName else {
            return .standard
        }
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Unable to open isolated preview preferences")
        }
        return defaults
    }
}
