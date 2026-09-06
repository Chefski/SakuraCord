import Foundation

public struct ProfileGameWebsite: Codable, Hashable, Sendable, Identifiable {
    public var category: Int
    public var url: URL
    public var id: String { "\(category):\(url.absoluteString)" }
    public init(category: Int, url: URL) { self.category = category; self.url = url }
}

public struct ProfileGameTrailer: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var applicationID: String
    public var width: Int
    public var height: Int
    public init(id: String, applicationID: String, width: Int, height: Int) {
        self.id = id; self.applicationID = applicationID; self.width = width; self.height = height
    }
}

public struct ProfileGameSteamReviews: Codable, Hashable, Sendable {
    public var rating: Double?
    public var count: Int?
    public var recentRating: Double?
    public var recentCount: Int?
    public var localizedRating: Double?
    public var localizedCount: Int?

    public init(rating: Double? = nil, count: Int? = nil, recentRating: Double? = nil, recentCount: Int? = nil,
                localizedRating: Double? = nil, localizedCount: Int? = nil) {
        self.rating = rating; self.count = count; self.recentRating = recentRating; self.recentCount = recentCount
        self.localizedRating = localizedRating; self.localizedCount = localizedCount
    }
}

public struct ProfileGameCriticReviews: Codable, Hashable, Sendable {
    public var rating: Double
    public var tier: Int
    public var count: Int?
    public var url: URL
    public init(rating: Double, tier: Int, url: URL, count: Int? = nil) { self.rating = rating; self.tier = tier; self.url = url; self.count = count }
}

public struct ProfileGameMetadata: Codable, Hashable, Sendable {
    public var description: String?
    public var genres: [Int] = []
    public var platforms: [Int] = []
    public var publishers: [String] = []
    public var developers: [String] = []
    public var releaseDate: Date?
    public var websites: [ProfileGameWebsite] = []
    public var screenshots: [URL] = []
    public var trailers: [ProfileGameTrailer] = []
    public var artwork: [URL] = []
    public var steamReviews: ProfileGameSteamReviews?
    public var criticReviews: ProfileGameCriticReviews?
    public var steamURL: URL?
    public var isRetiredFromSteam = false
    public var isProfileAvailable = true
    public var officialApplicationID: String?
    public var rank: Int?

    public init() {}
}

public struct ProfileGameAnnouncements: Sendable {
    public var messages: [ProfileGameAnnouncement]
    public var channelID: ChannelID?
    public var guildID: GuildID?
    public init(messages: [ProfileGameAnnouncement] = [], channelID: ChannelID? = nil, guildID: GuildID? = nil) {
        self.messages = messages; self.channelID = channelID; self.guildID = guildID
    }
}
