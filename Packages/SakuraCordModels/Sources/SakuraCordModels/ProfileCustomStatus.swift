import Foundation

public struct ProfileCustomStatus: Hashable, Sendable {
    public var text: String
    public var emojiID: String?
    public var emojiName: String?
    public var expiresAt: Date?
    public var createdAt: Date?

    public init(text: String, emojiID: String? = nil, emojiName: String? = nil, expiresAt: Date? = nil, createdAt: Date? = nil) {
        self.text = text
        self.emojiID = emojiID
        self.emojiName = emojiName
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }

    public var displayText: String {
        let emoji = if let emojiID { "<:\(emojiName ?? "emoji"):\(emojiID)>" } else { emojiName ?? "" }
        return [emoji, text].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
