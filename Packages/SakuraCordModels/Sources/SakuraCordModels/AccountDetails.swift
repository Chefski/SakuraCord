import Foundation

/// Private, session-only information for the signed-in account.
public struct AccountDetails: Equatable, Sendable {
    public var userID: UserID
    public var username: String
    public var email: String?
    public var phoneNumber: String?
    public var isMFAEnabled: Bool

    public init(userID: UserID, username: String, email: String?, phoneNumber: String?, isMFAEnabled: Bool) {
        self.userID = userID
        self.username = username
        self.email = email
        self.phoneNumber = phoneNumber
        self.isMFAEnabled = isMFAEnabled
    }
}

public struct AccountDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let operatingSystem: String?
    public let platform: String?
    public let location: String?
    public let lastUsedAt: Date?
    public let isCurrentSession: Bool

    public init(id: String, operatingSystem: String?, platform: String?, location: String?, lastUsedAt: Date?, isCurrentSession: Bool) {
        self.id = id
        self.operatingSystem = operatingSystem
        self.platform = platform
        self.location = location
        self.lastUsedAt = lastUsedAt
        self.isCurrentSession = isCurrentSession
    }
}
