import Foundation
import SakuraCordModels

struct ProfileWidgetDTO: Decodable {
    let id: String?
    let updatedAt: String?
    let data: ProfileWidgetDataDTO
    enum CodingKeys: String, CodingKey { case id, data; case updatedAt = "updated_at" }

    func domain(userID: UserID) throws -> ProfileWidget {
        try ProfileWidget(serverID: id, updatedAt: updatedAt, content: data.domain(userID: userID))
    }
}

struct ProfileWidgetDataDTO: Decodable {
    let type: String
    let applicationID: String?
    let header: String?
    let sections: [ProfileWidgetSectionDTO]?
    let games: [ProfileWidgetGameDTO]?
    let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey { case type, header, sections, games; case applicationID = "application_id" }
    init(from decoder: any Decoder) throws {
        raw = try [String: JSONValue](from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        applicationID = try values.decodeIfPresent(String.self, forKey: .applicationID)
        header = try values.decodeIfPresent(String.self, forKey: .header)
        sections = try values.decodeIfPresent([ProfileWidgetSectionDTO].self, forKey: .sections)
        games = try values.decodeIfPresent([ProfileWidgetGameDTO].self, forKey: .games)
    }

    func domain(userID: UserID) throws -> ProfileWidget.Content {
        if type == "application", let applicationID { return .application(id: applicationID) }
        if type == "personal" {
            var normalized = try (sections ?? []).filter { ["cover", "fields"].contains($0.type) }.map { try $0.domain(userID: userID) }
            if !normalized.contains(where: { if case .fields = $0 { true } else { false } }) { normalized.append(.fields([])) }
            return .personal(ProfilePersonalWidget(header: header ?? "", sections: normalized))
        }
        if let kind = ProfileGameWidgetKind(rawValue: type), let games {
            var seen = Set<String>()
            return .games(kind, games.filter { seen.insert($0.gameID).inserted }.map(\.domain))
        }
        return .unrecognized(type: type)
    }
}

struct ProfileWidgetGameDTO: Decodable {
    let gameID: String
    let comment: String?
    let includesComment: Bool
    let tags: [String]?
    let includesTags: Bool

    enum CodingKeys: String, CodingKey { case comment, tags; case gameID = "game_id" }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try values.decode(String.self, forKey: .gameID)
        comment = try values.decodeIfPresent(String.self, forKey: .comment)
        includesComment = values.contains(.comment)
        tags = try values.decodeIfPresent([String].self, forKey: .tags)
        includesTags = values.contains(.tags)
    }
    var domain: ProfileWidgetGame { ProfileWidgetGame(id: gameID, comment: comment, includesComment: includesComment, tags: tags, includesTags: includesTags) }
}

struct ProfileWidgetSectionDTO: Decodable {
    let type: String
    let title: String?
    let subtitle: String?
    let image: ProfileWidgetImageDTO?
    let includesImage: Bool
    let fields: [ProfileWidgetFieldDTO]?

    enum CodingKeys: String, CodingKey { case type, title, subtitle, image, fields }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        subtitle = try values.decodeIfPresent(String.self, forKey: .subtitle)
        image = try values.decodeIfPresent(ProfileWidgetImageDTO.self, forKey: .image)
        includesImage = values.contains(.image)
        fields = try values.decodeIfPresent([ProfileWidgetFieldDTO].self, forKey: .fields)
    }

    func domain(userID: UserID) throws -> ProfilePersonalWidgetSection {
        if type == "cover" {
            return try .cover(ProfileWidgetCover(title: title ?? "", subtitle: subtitle ?? "", image: image?.domain(userID: userID), includesImage: includesImage))
        }
        guard type == "fields", let fields else { throw ChatProviderError.invalidRequest("Discord returned an invalid widget section.") }
        return try .fields(fields.map { try $0.domain(userID: userID) })
    }
}

struct ProfileWidgetFieldDTO: Decodable {
    let title: String?
    let description: String?
    let image: ProfileWidgetImageDTO?
    let includesImage: Bool

    enum CodingKeys: String, CodingKey { case title, description, image }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        image = try values.decodeIfPresent(ProfileWidgetImageDTO.self, forKey: .image)
        includesImage = values.contains(.image)
    }
    func domain(userID: UserID) throws -> ProfileWidgetField {
        try ProfileWidgetField(title: title ?? "", description: description ?? "", image: image?.domain(userID: userID), includesImage: includesImage)
    }
}

struct ProfileWidgetImageDTO: Decodable {
    let filename: String?
    let fileID: String?
    let width: Int?
    let height: Int?
    let isAnimated: Bool?
    enum CodingKeys: String, CodingKey {
        case filename, width, height
        case fileID = "file_id", isAnimated = "is_animated"
    }
    func domain(userID: UserID) throws -> ProfileWidgetImage {
        if let filename { return ProfileWidgetImage(reference: .pendingUpload(filename: filename)) }
        let isAnimated = isAnimated ?? false
        guard let fileID, UInt64(fileID) != nil, let width, width > 0, let height, height > 0,
              let url = URL(string: "https://cdn.discordapp.com/widget-assets/\(userID)/\(fileID)?format=webp&animated=\(isAnimated)")
        else { throw ChatProviderError.invalidRequest("Discord returned an invalid widget image.") }
        return ProfileWidgetImage(reference: .saved(fileID: fileID, width: width, height: height, isAnimated: isAnimated), url: url)
    }
}
