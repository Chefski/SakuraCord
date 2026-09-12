import Foundation
import SakuraCordModels

/// Status shares the profile editor's draft lifetime. Relative expiry starts when Save Changes is submitted.
nonisolated struct ProfileStatusDraft: Hashable, Sendable {
    var status: ProfileCustomStatus
    var expiresAfter: TimeInterval?

    static var empty: Self { Self(status: ProfileCustomStatus(text: ""), expiresAfter: 86400) }

    func submission(at date: Date) -> ProfileCustomStatus {
        var result = status
        if let expiresAfter { result.expiresAt = date.addingTimeInterval(expiresAfter) }
        return result
    }
}
