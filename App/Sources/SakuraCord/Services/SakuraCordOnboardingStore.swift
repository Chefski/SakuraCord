import Foundation
import SakuraCordModels

enum SakuraCordOnboardingStore {
    private static let completionKey = "dev.sakuracord.onboarding-completed"

    /// Run before startup services write preferences so an existing installation
    /// is grandfathered in, while an unfinished new installation stays pending.
    static func registerInstallation() {
        let defaults = PRBuildProfile.defaults
        guard defaults.object(forKey: completionKey) == nil,
              let bundleID = Bundle.main.bundleIdentifier
        else { return }
        let existingPreferences = defaults.persistentDomain(forName: SakuraCordStorageProfile.current.preferencesSuiteName ?? bundleID) ?? [:]
        // AppKit can record system preferences even before the app delegate is
        // initialized. Those alone do not establish a previous SakuraCord run.
        let hasExistingInstallation = existingPreferences.keys.contains { key in
            !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple.")
        }
        defaults.set(hasExistingInstallation, forKey: completionKey)
    }

    static var needsThemeSetup: Bool {
        !PRBuildProfile.defaults.bool(forKey: completionKey)
    }

    static func complete() {
        PRBuildProfile.defaults.set(true, forKey: completionKey)
    }
}
