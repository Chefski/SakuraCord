import Foundation

public struct GuildProfileCosmetics: Codable, Hashable, Sendable {
    public var avatarDecorationURL: URL?
    public var nameplate: Nameplate?
    public var displayNameStyle: DisplayNameStyle?

    public init(avatarDecorationURL: URL? = nil, nameplate: Nameplate? = nil, displayNameStyle: DisplayNameStyle? = nil) {
        self.avatarDecorationURL = avatarDecorationURL
        self.nameplate = nameplate
        self.displayNameStyle = displayNameStyle
    }

    public func applying(to user: User) -> User {
        var result = user
        result.avatarDecorationURL = avatarDecorationURL ?? user.avatarDecorationURL
        result.nameplate = nameplate ?? user.nameplate
        result.displayNameStyle = displayNameStyle ?? user.displayNameStyle
        return result
    }
}
