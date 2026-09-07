import DiscordProtocol
import Foundation
import SakuraCordModels

/// Local sample data for the production timeline. Interactions use an in-memory
/// provider without restoring credentials or connecting to a Discord account.
enum MessageAppearancePreviewContent {
    static let channelID = ChannelID(rawValue: 18_000_000_000_000_000_000)

    static func makeModel() -> AppModel {
        let you = user(1, name: "You", avatar: "preview-avatar-you")
        let maya = user(2, name: "Maya", avatar: "preview-avatar-maya")
        let theo = user(3, name: "Theo", avatar: "preview-avatar-theo")
        let channel = Channel(id: channelID, guildID: nil, name: "weekend-plans", kind: .groupDirectMessage)
        let snapshot = BootstrapSnapshot(
            currentUser: you,
            knownUsers: [you, maya, theo],
            guilds: [],
            channels: [channel],
            members: []
        )
        let messages = messages(you: you, maya: maya, theo: theo)
        let model = AppModel(
            launchMode: .offlineTesting,
            provider: MockChatProvider(snapshot: snapshot, messages: messages),
            restoresStoredSession: false,
            runsChatPerformanceBenchmarkOverride: false
        )
        model.snapshot = snapshot
        model.storeCachedMessages(messages, for: channelID)
        model.hasMoreCache[channelID] = false
        model.selectedChannelID = channelID
        return model
    }

    private static func messages(you: User, maya: User, theo: User) -> [Message] {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 16, minute: 42))!
        func message(_ number: UInt64, _ author: User, _ content: String) -> Message {
            Message(
                id: MessageID(rawValue: channelID.rawValue + number),
                channelID: channelID,
                author: author,
                content: content,
                timestamp: start.addingTimeInterval(Double(number * 24))
            )
        }
        var lake = message(3, maya, "I was thinking a trail like this 🌿")
        lake.attachments = [Attachment(
            id: "preview-lake", filename: "a-quiet-morning.jpg",
            url: asset("preview-lake", extension: "jpg"), mediaType: "image/jpeg",
            width: 1100, height: 680,
            description: "An alpine lake reflecting green slopes and rocky mountain peaks."
        )]
        lake.reactions = [Reaction(emoji: "🌿", count: 3, didCurrentUserReact: true)]
        let coffee = message(4, maya, "Imagine this with a thermos of coffee.")
        var city = message(7, theo, "And if it rains, we can always do a city walk instead.")
        city.embeds = [MessageEmbed(
            id: "preview-blue-hour", title: "Los Angeles at blue hour", type: "rich",
            description: "A little inspiration for the backup plan. That light is unreal.",
            url: URL(string: "https://unsplash.com/photos/city-skyline-during-night-time-9EwAsDDVnog"),
            color: 0x6B91AC,
            footer: MessageEmbedFooter(text: "Photo by Jesus Curiel · Unsplash"),
            image: MessageEmbedMedia(
                url: asset("preview-city", extension: "jpg"), width: 1100, height: 680,
                description: "The moon above the Los Angeles skyline at blue hour.", contentType: "image/jpeg"
            ),
            provider: MessageEmbedProvider(name: "Unsplash", url: URL(string: "https://unsplash.com"))
        )]
        var reply = message(8, you, "Coffee + mountains. Hard to improve on that.")
        reply.replyTo = coffee.id
        reply.replyPreview = MessageReplyPreview(message: coffee)
        return [
            message(1, maya, "Anyone up for a photo walk this weekend?"),
            message(2, you, "Very in. Somewhere with fewer cars this time?"),
            lake,
            coffee,
            message(5, theo, "Sold. I’ll bring the questionable homemade cookies."),
            message(6, you, "At least let us try them before calling them questionable 😂"),
            city,
            reply,
            message(9, you, "Let’s leave the laptops at home for once."),
        ]
    }

    private static func user(_ id: UInt64, name: String, avatar: String) -> User {
        User(
            id: UserID(rawValue: 250_000_000_000_000_000 + id), username: name.lowercased(),
            displayName: name, avatarURL: asset(avatar, extension: "jpg")
        )
    }

    private static func asset(_ name: String, extension fileExtension: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            preconditionFailure("Missing Appearance preview asset: \(name).\(fileExtension)")
        }
        return url
    }
}
