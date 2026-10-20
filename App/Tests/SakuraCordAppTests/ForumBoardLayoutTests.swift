import AppKit
import SakuraCordModels
import Testing
@testable import SakuraCord

/// The forum board's central promise: data that arrives after a post first
/// appears (starter message, thumbnail, reactions) never moves or resizes a card.
@MainActor
@Test(arguments: [ForumLayout.list, .gallery])
func `forum board geometry ignores late post data`(mode: ForumLayout) {
    let channelID = ChannelID(rawValue: 900)
    let author = User(id: UserID(rawValue: 1), displayName: "Ada")
    func post(_ index: UInt64, hydrated: Bool) -> ForumPost {
        let id = ChannelID(rawValue: 1_000 + index)
        let thread = MessageThreadSummary(
            id: id,
            parentID: channelID,
            name: index.isMultiple(of: 2)
                ? "A long forum post title that wraps onto a second line at narrow widths"
                : "Short title",
            messageCount: 3,
            appliedTagIDs: index.isMultiple(of: 3) ? [ForumTagID(rawValue: 7)] : []
        )
        guard hydrated else { return ForumPost(thread: thread) }
        let starter = Message(
            id: MessageID(rawValue: id.rawValue),
            channelID: id,
            author: author,
            content: String(repeating: "Starter text that fills the excerpt. ", count: 8),
            attachments: [Attachment(
                id: "a\(index)",
                filename: "shot.png",
                url: URL(string: "https://cdn.example.com/\(index).png")!,
                mediaType: "image/png"
            )],
            reactions: [Reaction(emoji: "👍", count: 4)]
        )
        return ForumPost(thread: thread, owner: author, firstMessage: starter, mostRecentMessage: starter)
    }
    let metrics = ForumBoardMetrics.current()
    let counter = ForumTitleLineCounter(font: metrics.titleFont, maximumLines: metrics.maximumTitleLines)
    func layout(hydrated: Bool, width: CGFloat) -> [CGRect] {
        let items = (0 ..< 12).map { ForumBoardItem.post(ForumCardGeometryInput(post: post($0, hydrated: hydrated))) }
        return ForumBoardLayout.make(
            items: items,
            mode: mode,
            width: width,
            metrics: metrics,
            titleLines: { counter.lines($0, width: $1) }
        ).entries.map(\.frame)
    }
    for width: CGFloat in [360, 720, 1_280] {
        #expect(layout(hydrated: false, width: width) == layout(hydrated: true, width: width))
    }
}
