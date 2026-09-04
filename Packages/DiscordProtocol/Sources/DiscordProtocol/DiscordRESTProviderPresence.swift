import Foundation
import SakuraCordModels

public extension DiscordRESTProvider {
    func currentStatus() async -> PresenceStatus {
        presenceStatus
    }

    func updateStatus(_ status: PresenceStatus) async throws {
        try await sendGateway([
            "op": 3,
            "d": ["since": 0, "activities": [], "status": status.rawValue, "afk": false]
                as [String: Any],
        ])
        presenceStatus = status
        if let statusDefaultsKey {
            UserDefaults.standard.set(status.rawValue, forKey: statusDefaultsKey)
        }
    }

    internal var statusDefaultsKey: String? {
        accountID.map { "dev.sakuracord.presence.\($0)" }
    }
}
