import Foundation

public struct VoiceConnectionInfo: Equatable, Sendable {
    public var serverID: String
    public var channelID: ChannelID
    public var guildID: GuildID?
    public var userID: UserID
    public var sessionID: String
    public var token: String
    public var endpoint: String

    public init(
        serverID: String,
        channelID: ChannelID,
        guildID: GuildID?,
        userID: UserID,
        sessionID: String,
        token: String,
        endpoint: String
    ) {
        self.serverID = serverID
        self.channelID = channelID
        self.guildID = guildID
        self.userID = userID
        self.sessionID = sessionID
        self.token = token
        self.endpoint = endpoint
    }
}
