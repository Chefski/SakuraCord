import SakuraCordModels

struct MessageUpdateDTO: Decodable {
    var id: String
    var channelID: String
    var guildID: String?
    var content: String?
    var editedTimestamp: String?
    var attachments: LossyList<AttachmentDTO>?
    var embeds: LossyList<MessageEmbedDTO>?
    var components: LossyList<MessageComponentDTO>?
    var stickerItems: LossyList<MessageStickerDTO>?
    var stickers: LossyList<MessageStickerDTO>?
    var thread: MessageThreadDTO?
    var mentions: LossyList<MessageMentionDTO>?
    var mentionRoles: [String]?
    var mentionEveryone: Bool?
    var flags: UInt64?
    var pinned: Bool?
    var type: Int?
    var application: MessageDTO.ApplicationDTO?
    var interaction: MessageDTO.InteractionDTO?
    var interactionMetadata: MessageDTO.InteractionMetadataDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel_id"
        case guildID = "guild_id"
        case content
        case editedTimestamp = "edited_timestamp"
        case attachments
        case embeds, components, stickers, thread, flags, pinned, type, mentions, application, interaction
        case mentionRoles = "mention_roles"
        case mentionEveryone = "mention_everyone"
        case interactionMetadata = "interaction_metadata"
        case stickerItems = "sticker_items"
    }

    func apply(to message: inout Message) {
        domain(guildID: message.guildID)?.apply(to: &message)
    }

    func domain(guildID: GuildID?) -> MessageUpdate? {
        guard let messageID = MessageID(id), let channelID = ChannelID(channelID) else { return nil }
        let resolvedGuildID = self.guildID.flatMap(GuildID.init) ?? guildID
        var value = MessageUpdate(messageID: messageID, channelID: channelID)
        value.content = content
        value.editedTimestamp = editedTimestamp.map { DiscordDate.parse($0) }
        value.attachments = attachments.map { $0.elements.compactMap { try? $0.domain() } }
        value.embeds = embeds.map { $0.elements.enumerated().map { $0.element.domain(index: $0.offset) } }
        value.components = components.map { $0.elements.enumerated().map { $0.element.domain(path: "\($0.offset)") } }
        value.stickers = (stickerItems ?? stickers).map { $0.elements.map(\.domain) }
        value.thread = thread?.domain
        value.flags = flags.map(MessageFlags.init(rawValue:))
        value.isPinned = pinned
        value.type = type.map(DiscordMessageType.init(rawValue:))
        value.application = application?.domain
        if interaction != nil || interactionMetadata != nil {
            value.interactionMetadata = MessageInteractionMetadata(
                id: interactionMetadata?.id ?? interaction?.id,
                type: interactionMetadata?.type ?? interaction?.type ?? 2,
                name: interactionMetadata?.name ?? interaction?.name,
                localizedName: interactionMetadata?.localizedName ?? interaction?.localizedName,
                user: (interactionMetadata?.user ?? interaction?.user).flatMap { try? $0.domain() },
                applicationID: interactionMetadata?.applicationID,
                originalResponseMessageID: interactionMetadata?.originalResponseMessageID.flatMap(MessageID.init)
            )
        }
        value.mentionedUsers = mentions.map { $0.elements.compactMap { try? $0.domain(guildID: resolvedGuildID) } }
        value.mentionedRoleIDs = mentionRoles.map { $0.compactMap(RoleID.init) }
        value.mentionsEveryone = mentionEveryone
        return value
    }
}
