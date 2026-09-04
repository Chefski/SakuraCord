import Foundation

public struct Guild: Identifiable, Codable, Hashable, Sendable {
    public let id: GuildID
    public var name: String
    public var iconURL: URL?
    public var accentHex: UInt32
    public var unreadCount: Int
    public var mentionCount: Int
    public var isOwnedByCurrentUser: Bool?
    public var currentUserPermissions: UInt64?
    public var rulesChannelID: ChannelID?
    public var features: Set<String>
    public var defaultMessageNotifications: MessageNotificationLevel
    public var isUnavailable: Bool

    public init(
        id: GuildID, name: String, iconURL: URL? = nil, accentHex: UInt32 = 0x5865F2,
        unreadCount: Int = 0, mentionCount: Int = 0, isOwnedByCurrentUser: Bool? = nil,
        currentUserPermissions: UInt64? = nil, rulesChannelID: ChannelID? = nil,
        features: Set<String> = [],
        defaultMessageNotifications: MessageNotificationLevel = .onlyMentions,
        isUnavailable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.accentHex = accentHex
        self.unreadCount = unreadCount
        self.mentionCount = mentionCount
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
        self.currentUserPermissions = currentUserPermissions
        self.rulesChannelID = rulesChannelID
        self.features = features
        self.defaultMessageNotifications = defaultMessageNotifications
        self.isUnavailable = isUnavailable
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, iconURL, accentHex, unreadCount, mentionCount, isOwnedByCurrentUser
        case currentUserPermissions, rulesChannelID, features, defaultMessageNotifications
        case isUnavailable
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(GuildID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        iconURL = try values.decodeIfPresent(URL.self, forKey: .iconURL)
        accentHex = try values.decodeIfPresent(UInt32.self, forKey: .accentHex) ?? 0x5865F2
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        mentionCount = try values.decodeIfPresent(Int.self, forKey: .mentionCount) ?? 0
        isOwnedByCurrentUser = try values.decodeIfPresent(Bool.self, forKey: .isOwnedByCurrentUser)
        currentUserPermissions = try values.decodeIfPresent(UInt64.self, forKey: .currentUserPermissions)
        rulesChannelID = try values.decodeIfPresent(ChannelID.self, forKey: .rulesChannelID)
        features = try values.decodeIfPresent(Set<String>.self, forKey: .features) ?? []
        defaultMessageNotifications =
            try values.decodeIfPresent(MessageNotificationLevel.self, forKey: .defaultMessageNotifications)
                ?? .onlyMentions
        isUnavailable = try values.decodeIfPresent(Bool.self, forKey: .isUnavailable) ?? false
    }
}
