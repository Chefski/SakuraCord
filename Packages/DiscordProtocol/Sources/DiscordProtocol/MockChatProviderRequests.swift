import Foundation
import SakuraCordModels

public extension MockChatProvider {
    struct PinMutationRequest: Equatable, Sendable {
        public var channelID: ChannelID
        public var messageID: MessageID
        public var isPinned: Bool
    }

    struct VoiceJoinRequest: Equatable, Sendable {
        public var channelID: ChannelID
        public var guildID: GuildID?
        public var selfMute: Bool
        public var selfDeaf: Bool

        public init(
            channelID: ChannelID,
            guildID: GuildID?,
            selfMute: Bool,
            selfDeaf: Bool
        ) {
            self.channelID = channelID
            self.guildID = guildID
            self.selfMute = selfMute
            self.selfDeaf = selfDeaf
        }
    }

    struct SoundboardSendRequest: Equatable, Sendable {
        public var sound: SoundboardSound
        public var channelID: ChannelID
    }

    struct AcknowledgementRequest: Equatable, Sendable {
        public var channelID: ChannelID
        public var messageID: MessageID
        public var token: String?
        public var manual: Bool
        public var mentionCount: Int?
        public var flags: UInt64?
        public var lastViewed: Int?
    }

    struct GuildNotificationRequest: Equatable, Sendable {
        public var guildID: GuildID
        public var level: MessageNotificationLevel?
        public var isMuted: Bool?
        public var muteEndTime: Date?
        public var toggle: GuildNotificationToggle?
        public var isEnabled: Bool?
    }

    struct ChannelNotificationRequest: Equatable, Sendable {
        public var guildID: GuildID?
        public var channelID: ChannelID
        public var level: MessageNotificationLevel?
        public var isMuted: Bool?
        public var muteEndTime: Date?
    }

    struct CategoryNotificationRequest: Equatable, Sendable {
        public var guildID: GuildID
        public var categoryID: ChannelID
        public var level: MessageNotificationLevel?
        public var isMuted: Bool?
        public var muteEndTime: Date?
        public var isCollapsed: Bool?
    }

    struct ThreadNotificationRequest: Equatable, Sendable {
        public var threadID: ChannelID
        public var level: MessageNotificationLevel?
        public var isMuted: Bool?
        public var muteEndTime: Date?
    }
}
