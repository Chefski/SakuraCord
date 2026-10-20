import AppKit
import SakuraCordModels

/// Everything a forum card draws, resolved once from the model. Cards repaint
/// only when their presentation changes; geometry never depends on it beyond
/// `ForumCardGeometryInput`.
struct ForumCardPresentation: Equatable {
    struct Tag: Equatable {
        let id: ForumTagID
        let name: String
        let emoji: ForumTagEmojiPresentation?
    }

    struct Author: Equatable {
        let name: String
        let fontID: Int?
        let color: NSColor?
        let roleDotColor: NSColor?
    }

    enum Excerpt: Equatable {
        /// The starter message has not loaded yet.
        case pending
        /// The post has no displayable starter text.
        case empty
        case message(Message, author: Author)
    }

    enum Media: Equatable {
        case image(NativeTimelineMediaKey)
        case video(poster: NativeTimelineMediaKey?, filename: String)
        case audio(filename: String)
        case file(filename: String)
        case spoiler
    }

    enum Hero: Equatable {
        case pending
        case media(Media)
        case text(Message)
        case empty
    }

    struct ReactionSummary: Equatable {
        let reaction: Reaction
        let message: Message
        let isDisabled: Bool
    }

    let id: ChannelID
    let geometry: ForumCardGeometryInput
    let title: String
    let isEmphasized: Bool
    let isNew: Bool
    let isSelected: Bool
    let isPinned: Bool
    let isLocked: Bool
    let tags: [Tag]
    let excerpt: Excerpt
    let thumbnail: Media?
    let hero: Hero
    let galleryAuthor: Author?
    let reaction: ReactionSummary?
    let messageCount: Int
    let unreadCount: Int
    let createdAt: Date
    let lastActivityAt: Date
    let underlinesLinks: Bool
    let roleColorDisplay: RoleColorDisplay

    var accessibilityLabel: String {
        var parts = [title]
        if isPinned { parts.append("Pinned") }
        if isLocked { parts.append("Locked") }
        if isNew { parts.append("New post") }
        if !tags.isEmpty { parts.append("Tags: " + tags.map(\.name).joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }

    var messageCountAccessibilityText: String {
        let messages = messageCount == 1 ? "message" : "messages"
        guard unreadCount > 0 else { return "\(messageCount) \(messages)" }
        let newMessages = unreadCount == 1 ? "new message" : "new messages"
        return "\(messageCount) \(messages), \(unreadCount) \(newMessages)"
    }
}

enum ForumTagEmojiPresentation: Equatable {
    case unicode(String)
    case custom(URL)

    init?(tag: ForumTag, customEmojiURLsByID: CustomEmojiImageURLs) {
        if let id = tag.emojiID {
            let url = customEmojiURLsByID[id]
                ?? EmojiReference(id: id, name: tag.emojiName ?? "emoji").imageURL(size: 64)
            guard let url else { return nil }
            self = .custom(url)
        } else if let name = tag.emojiName, !name.isEmpty {
            self = .unicode(name)
        } else {
            return nil
        }
    }

    var mediaKey: NativeTimelineMediaKey? {
        guard case let .custom(url) = self else { return nil }
        return .media(url, maximumPixelDimension: 64)
    }
}

extension ForumCardPresentation.Media {
    init(attachment: Attachment) {
        if attachment.isSpoiler {
            self = .spoiler
            return
        }
        switch attachment.mediaKind {
        case .image, .animatedImage:
            let url = attachment.proxyURL ?? attachment.url
            self = .image(.media(url, fallbackURL: url == attachment.url ? nil : attachment.url, maximumPixelDimension: 640))
        case .video:
            self = .video(
                poster: attachment.videoPosterURL(maximumPixelDimension: 640).map { .media($0, maximumPixelDimension: 640) },
                filename: attachment.filename
            )
        case .audio:
            self = .audio(filename: attachment.filename)
        case .file:
            self = .file(filename: attachment.filename)
        }
    }

    var mediaKey: NativeTimelineMediaKey? {
        switch self {
        case let .image(key): key
        case let .video(poster, _): poster
        case .audio, .file, .spoiler: nil
        }
    }
}

extension AppModel {
    func forumCardPresentation(for post: ForumPost, in channel: Channel) -> ForumCardPresentation {
        let tagsByID = Dictionary(channel.availableTags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tags = post.thread.appliedTagIDs.compactMap { tagsByID[$0] }.map {
            ForumCardPresentation.Tag(
                id: $0.id,
                name: $0.name,
                emoji: ForumTagEmojiPresentation(tag: $0, customEmojiURLsByID: customEmojiURLsByID)
            )
        }
        let starter = post.firstMessage
        let excerpt: ForumCardPresentation.Excerpt
        if let starter {
            excerpt = starter.content.isEmpty ? .empty : .message(starter, author: forumCardAuthor(for: starter))
        } else {
            excerpt = .pending
        }
        let thumbnail = starter?.attachments.first.map(ForumCardPresentation.Media.init(attachment:))
        let hero: ForumCardPresentation.Hero =
            if let thumbnail {
                .media(thumbnail)
            } else if let preview = post.mostRecentMessage ?? starter, !preview.content.isEmpty {
                .text(preview)
            } else if starter == nil {
                .pending
            } else {
                .empty
            }
        let galleryAuthor: ForumCardPresentation.Author? =
            if let starter {
                forumCardAuthor(for: starter)
            } else if let owner = post.owner {
                ForumCardPresentation.Author(
                    name: owner.displayName,
                    fontID: owner.displayNameStyle?.fontID,
                    color: owner.isBot ? .sakuraCordAccentColor : nil,
                    roleDotColor: nil
                )
            } else {
                nil
            }
        let reaction = ForumPostReactionPresentation.displayedReaction(
            reactions: starter?.reactions ?? [],
            defaultReaction: channel.defaultReaction
        ).flatMap { reaction in
            starter.map {
                ForumCardPresentation.ReactionSummary(
                    reaction: reaction,
                    message: $0,
                    isDisabled: guildTimeoutUntil(in: post.id, guildID: post.thread.guildID) != nil
                )
            }
        }
        return ForumCardPresentation(
            id: post.id,
            geometry: ForumCardGeometryInput(post: post),
            title: post.thread.name,
            isEmphasized: shouldEmphasizeForumPost(post),
            isNew: isForumPostNew(post),
            isSelected: openThread?.id == post.id,
            isPinned: post.thread.isPinned,
            isLocked: post.thread.isLocked,
            tags: tags,
            excerpt: excerpt,
            thumbnail: thumbnail,
            hero: hero,
            galleryAuthor: galleryAuthor,
            reaction: reaction,
            messageCount: ForumPostMessageCountPresentation.count(threadMessageCount: post.thread.messageCount),
            unreadCount: forumUnreadMessageCount(post),
            createdAt: post.createdAt,
            lastActivityAt: post.lastActivityAt,
            underlinesLinks: accessibilitySettings.underlinesLinks,
            roleColorDisplay: accessibilitySettings.roleColorDisplay
        )
    }

    private func forumCardAuthor(for message: Message) -> ForumCardPresentation.Author {
        let presentation = authorPresentation(for: message)
        let roleColor = NativeTimelineRowPainter.roleColor(presentation.roleColorHex)
        let display = accessibilitySettings.roleColorDisplay
        let color: NSColor? =
            if presentation.user.isBot {
                .sakuraCordAccentColor
            } else if display == .inNames {
                roleColor
            } else {
                nil
            }
        return ForumCardPresentation.Author(
            name: presentation.user.displayName,
            fontID: presentation.user.displayNameStyle?.fontID,
            color: color,
            roleDotColor: display == .nextToNames ? roleColor : nil
        )
    }
}
