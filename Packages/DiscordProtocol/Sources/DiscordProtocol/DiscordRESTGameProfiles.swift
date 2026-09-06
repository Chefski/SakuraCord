import Foundation
import SakuraCordModels

public extension DiscordRESTProvider {
    func similarProfileGames(to gameID: String) async throws -> [ProfileGame] {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        guard UInt64(gameID) != nil else { throw ChatProviderError.invalidRequest("Invalid game identifier.") }
        guard !Self.excludedSimilarGameIDs.contains(gameID) else { return [] }
        let generation = profileEditingGeneration
        let ids: [String]
        if let cached = profileSimilarGameIDs[gameID] { ids = cached } else {
            let response: SimilarProfileGamesDTO = try await request("/content-inventory/users/@me/similar-games/\(gameID)")
            try validateProfileWidgetSession(userID: userID, generation: generation)
            ids = (response.similarGames ?? []).filter { $0 != gameID && !Self.excludedSimilarGameIDs.contains($0) }
            profileSimilarGameIDs[gameID] = ids
        }
        let games = try await profileWidgetGames(ids: ids)
        try validateProfileWidgetSession(userID: userID, generation: generation)
        return games.filter { $0.metadata?.isProfileAvailable == true && (currentUser?.allowsAdultContent != false || $0.isAllowedInDefaultWidgetPicker) }
    }

    func profileGameAnnouncements(gameID: String) async throws -> ProfileGameAnnouncements {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        guard UInt64(gameID) != nil else { throw ChatProviderError.invalidRequest("Invalid game identifier.") }
        if let cached = profileGameAnnouncementCache[gameID] { return cached }
        let generation = profileEditingGeneration
        let response: ProfileGameAnnouncementsDTO = try await request(
            "/games/\(gameID)/announcements", query: [URLQueryItem(name: "limit", value: "8")]
        )
        try validateProfileWidgetSession(userID: userID, generation: generation)
        let announcements = ProfileGameAnnouncements(
            messages: try response.messages.map { ProfileGameAnnouncement(message: try $0.message.domain(), poll: $0.poll?.domain) },
            channelID: response.channelID.flatMap(ChannelID.init), guildID: response.guildID.flatMap(GuildID.init)
        )
        profileGameAnnouncementCache[gameID] = announcements
        return announcements
    }

    // The game-profile feed has its own exclusions, independent of the widget picker.
    private static let excludedSimilarGameIDs: Set<String> = [
        "700136079562375258", "1402418693958275202", "1402418696126992445", "1417993715611467826"
    ]
}

private struct SimilarProfileGamesDTO: Decodable {
    let similarGames: [String]?
    enum CodingKeys: String, CodingKey { case similarGames = "similar_games" }
}

private struct ProfileGameAnnouncementsDTO: Decodable {
    struct Announcement: Decodable {
        let message: MessageDTO
        let poll: ProfileGameAnnouncementPollDTO?
        enum CodingKeys: String, CodingKey { case poll }
        init(from decoder: Decoder) throws {
            message = try MessageDTO(from: decoder)
            poll = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(ProfileGameAnnouncementPollDTO.self, forKey: .poll)
        }
    }
    let messages: [Announcement]
    let channelID: String?
    let guildID: String?
    enum CodingKeys: String, CodingKey { case messages, channelID = "channel_id", guildID = "guild_id" }
}

private struct ProfileGameAnnouncementPollDTO: Decodable {
    struct Text: Decodable { let text: String? }
    struct Answer: Decodable {
        let id: Int
        let media: Text
        enum CodingKeys: String, CodingKey { case id = "answer_id", media = "poll_media" }
    }
    let question: Text
    let answers: [Answer]
    let expiry: String?
    var domain: ProfileGameAnnouncementPoll {
        ProfileGameAnnouncementPoll(question: question.text ?? "", answers: answers.map { .init(id: $0.id, text: $0.media.text ?? "") },
                                    expiry: expiry.flatMap(DiscordDate.parse))
    }
}
