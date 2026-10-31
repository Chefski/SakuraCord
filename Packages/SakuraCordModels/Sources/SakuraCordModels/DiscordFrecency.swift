import Foundation

/// One entry in Discord's ordered frecency maps (emoji, reactions or commands).
public struct DiscordFrecencyEntry: Codable, Hashable, Sendable {
    public var key: String
    public var totalUses: Int
    /// Millisecond timestamps, oldest first, at most ten.
    public var recentUses: [UInt64]
    /// Discord stores -1 when the value must be recomputed.
    public var frecency: Int32
    public var score: Int32

    public init(key: String, totalUses: Int, recentUses: [UInt64], frecency: Int32 = -1, score: Int32 = 0) {
        self.key = key
        self.totalUses = totalUses
        self.recentUses = recentUses
        self.frecency = frecency
        self.score = score
    }
}

/// The synced map in stored order. Order matters: Discord breaks frecency
/// ties by insertion order.
public struct DiscordFrecencyHistory: Codable, Hashable, Sendable {
    public var entries: [DiscordFrecencyEntry]

    public init(entries: [DiscordFrecencyEntry] = []) {
        self.entries = entries
    }
}
