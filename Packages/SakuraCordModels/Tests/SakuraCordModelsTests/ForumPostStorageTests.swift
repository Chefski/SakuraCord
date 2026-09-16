import Foundation
import SakuraCordModels
import Testing

@Test func `forum message storage preserves independent mutations and its Codable contract`() throws {
    let thread = MessageThreadSummary(id: ChannelID(rawValue: 20), name: "Thread")
    let message = Message(
        id: MessageID(rawValue: 30), channelID: thread.id,
        author: User(id: UserID(rawValue: 10), username: "author", displayName: "Author"),
        content: "Original", timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        reactions: [Reaction(emoji: "✅", count: 1)]
    )
    let original = ForumPost(thread: thread, firstMessage: message, mostRecentMessage: message)
    var changed = original
    changed.firstMessage?.content = "Updated"
    changed.firstMessage?.reactions[0].count = 2
    changed.mostRecentMessage = nil
    #expect(original.firstMessage?.content == "Original")
    #expect(original.firstMessage?.reactions[0].count == 1)
    #expect(original.mostRecentMessage == message)
    #expect(changed.firstMessage?.content == "Updated")
    #expect(changed.firstMessage?.reactions[0].count == 2)
    #expect(changed.mostRecentMessage == nil)

    let encoded = try JSONEncoder().encode(original)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect((json["firstMessage"] as? [String: Any])?["content"] as? String == "Original")
    #expect((json["mostRecentMessage"] as? [String: Any])?["content"] as? String == "Original")
    #expect(json["storedFirstMessage"] == nil)
    let restored = try JSONDecoder().decode(ForumPost.self, from: encoded)
    #expect(restored == original)
    #expect(Set([restored, original, changed]).count == 2)

    let empty = ForumPost(thread: thread)
    #expect(try JSONDecoder().decode(ForumPost.self, from: JSONEncoder().encode(empty)) == empty)
}
