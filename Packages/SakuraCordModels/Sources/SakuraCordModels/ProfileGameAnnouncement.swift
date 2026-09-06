import Foundation

public struct ProfileGameAnnouncementPoll: Hashable, Sendable {
    public struct Answer: Hashable, Sendable, Identifiable {
        public let id: Int
        public let text: String
        public init(id: Int, text: String) { self.id = id; self.text = text }
    }
    public let question: String
    public let answers: [Answer]
    public let expiry: Date?
    public init(question: String, answers: [Answer], expiry: Date?) {
        self.question = question; self.answers = answers; self.expiry = expiry
    }
}

/// The game feed projects messages differently from the conversation timeline.
public struct ProfileGameAnnouncement: Identifiable, Sendable {
    public let id: MessageID
    public let timestamp: Date
    public let content: String
    public let title: String?
    public let body: String
    public let media: MessageEmbedMedia?
    public let embedSource: MessageEmbed?
    public let reactionCount: Int
    public let poll: ProfileGameAnnouncementPoll?

    public init(message: Message, poll: ProfileGameAnnouncementPoll? = nil) {
        id = message.id
        timestamp = message.timestamp
        self.poll = poll
        reactionCount = message.reactions.reduce(0) { $0 + $1.count }
        let components = message.flags.contains(.isComponentsV2)
        var text = message.content
        if components {
            text = message.components.compactMap { component in
                if case let .textDisplay(_, content) = component { return content }
                return nil
            }.joined(separator: "\n")
        } else if text.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^https?://\S+$"#, options: .regularExpression) != nil,
                  let embed = message.embeds.first {
            let parts = [embed.title.map { "# \($0)" }, embed.description].compactMap { $0 }
            if !parts.isEmpty { text = parts.joined(separator: "\n") }
        }
        content = text
        let firstLine = String(text.prefix { $0 != "\n" })
        if let heading = firstLine.range(of: #"^#{1,3}\s+.+$"#, options: .regularExpression) {
            title = firstLine[heading].drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
            body = text.dropFirst(firstLine.count).drop(while: { $0.isWhitespace }).description
        } else {
            title = nil
            body = text
        }
        if !components, text != message.content, let embed = message.embeds.first,
           embed.author != nil || embed.footer != nil || embed.provider?.name != nil || embed.url != nil {
            embedSource = embed
        } else { embedSource = nil }
        media = Self.selectMedia(message)
    }

    private static func selectMedia(_ message: Message) -> MessageEmbedMedia? {
        if message.flags.contains(.isComponentsV2),
           let gallery = message.components.first(where: { if case .mediaGallery = $0 { return true }; return false }),
           case let .mediaGallery(_, items) = gallery, let media = items.first?.media,
           media.contentType?.hasPrefix("image/") == true || media.contentType?.hasPrefix("video/") == true {
            return MessageEmbedMedia(url: media.url, proxyURL: media.proxyURL, width: media.width, height: media.height,
                                     description: media.description, contentType: media.contentType,
                                     placeholder: media.placeholder, placeholderVersion: media.placeholderVersion)
        }
        let attachment = message.attachments.first { $0.mediaType?.hasPrefix("image/") == true }
            ?? message.attachments.first { $0.mediaType?.hasPrefix("video/") == true }
        if let attachment {
            return MessageEmbedMedia(url: attachment.url, proxyURL: attachment.proxyURL, width: attachment.width, height: attachment.height,
                                     description: attachment.description, contentType: attachment.mediaType,
                                     placeholder: attachment.placeholder, placeholderVersion: attachment.placeholderVersion)
        }
        return message.embeds.first { $0.video != nil && $0.thumbnail != nil }?.thumbnail
            ?? message.embeds.first { $0.image != nil }?.image
            ?? message.embeds.first { $0.thumbnail != nil }?.thumbnail
    }
}
