import Foundation

struct DiscordProfileWidgetGamePolicy: Decodable, Sendable {
    let defaultGameIDs: [String]
    let excludedGameIDs: Set<String>

    static let bundled: Self? = {
        guard let url = Bundle.module.url(forResource: "ProfileWidgetGamePolicy", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()

    static func isAdult(_ value: JSONValue?) -> Bool {
        guard case let .object(classification) = value else { return false }
        let flags: UInt64
        switch classification["discord_classifications"] {
        case let .string(value): flags = UInt64(value) ?? 0
        case let .number(value): flags = UInt64(exactly: value) ?? 0
        default: flags = 0
        }
        // Official minimal classification: emergency restriction or either
        // explicit-content bit; PEGI alone never marks a game adult-only.
        if flags & 0b11001 != 0 { return true }
        guard case let .object(ratings) = classification["agency_ratings"] else { return false }
        if case let .object(esrb) = ratings["esrb"], esrb["rating"] == .number(5) { return true }
        if case let .object(gop) = ratings["gop"], gop["classification"] == .number(1) { return true }
        if case let .object(igdb) = ratings["igdb"], case let .array(themes) = igdb["themes"], themes.contains(.number(21)) { return true }
        return false
    }
}
