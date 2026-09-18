import Foundation
import SakuraCordModels

struct DiscordAccountDetailsDTO: Decodable {
    let id: String
    let username: String?
    let email: String?
    let phone: String?
    let mfaEnabled: Bool?
    let hasEmail: Bool
    let hasPhone: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, email, phone
        case mfaEnabled = "mfa_enabled"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        username = try values.decodeIfPresent(String.self, forKey: .username)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        phone = try values.decodeIfPresent(String.self, forKey: .phone)
        mfaEnabled = try values.decodeIfPresent(Bool.self, forKey: .mfaEnabled)
        hasEmail = values.contains(.email)
        hasPhone = values.contains(.phone)
    }

    func domain(merging previous: AccountDetails? = nil) -> AccountDetails? {
        guard let userID = UserID(id) else { return nil }
        let previous = previous?.userID == userID ? previous : nil
        guard let username = username ?? previous?.username,
              let mfaEnabled = mfaEnabled ?? previous?.isMFAEnabled,
              hasEmail || previous != nil,
              hasPhone || previous != nil else { return nil }
        return AccountDetails(
            userID: userID, username: username,
            email: hasEmail ? email : previous?.email,
            phoneNumber: hasPhone ? phone : previous?.phoneNumber,
            isMFAEnabled: mfaEnabled
        )
    }
}

struct DiscordAccountReadyDTO: Decodable {
    let user: DiscordAccountDetailsDTO?
    let authSessionIDHash: String?

    enum CodingKeys: String, CodingKey {
        case user
        case authSessionIDHash = "auth_session_id_hash"
    }
}

struct DiscordAccountSessionsDTO: Decodable {
    let userSessions: [Session]

    enum CodingKeys: String, CodingKey {
        case userSessions = "user_sessions"
    }

    struct Session: Decodable {
        let idHash: String
        let approxLastUsedTime: String?
        let clientInfo: ClientInfo?

        enum CodingKeys: String, CodingKey {
            case idHash = "id_hash"
            case approxLastUsedTime = "approx_last_used_time"
            case clientInfo = "client_info"
        }

        struct ClientInfo: Decodable {
            let os: String?
            let platform: String?
            let location: String?
            let ip: String?
        }

        func domain(currentSessionIDHash: String?) -> AccountDevice {
            AccountDevice(
                id: idHash, operatingSystem: clientInfo?.os,
                platform: clientInfo?.platform,
                location: clientInfo?.location ?? clientInfo?.ip,
                lastUsedAt: approxLastUsedTime.flatMap(DiscordDate.parse),
                isCurrentSession: idHash == currentSessionIDHash
            )
        }
    }
}
