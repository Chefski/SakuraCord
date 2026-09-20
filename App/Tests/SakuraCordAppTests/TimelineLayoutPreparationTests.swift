import AppKit
@testable import SakuraCord
import SakuraCordModels
import Testing

@MainActor
@Test(arguments: [false, true], [false, true])
func `timeline layout preparation commits a complete update or discards superseded work`(
    replacesDuringPreparation: Bool,
    changesPresentation: Bool
) async throws {
    let model = AppModel(launchMode: .offlineTesting)
    let channelID = ChannelID(rawValue: 99_400)
    let author = User(id: UserID(rawValue: 99_401), username: "history", displayName: "History")
    let messages = (0 ..< 84).map {
        Message(
            id: MessageID(rawValue: UInt64(100_000 + $0)),
            channelID: channelID, author: author,
            content: "History message \($0)"
        )
    }
    let original = changesPresentation ? messages : Array(messages.suffix(20))
    model.replaceSelectedMessages(with: original)
    let timeline = NativeMessageTimelineView(
        model: model, conversation: .channel(channelID), beginning: nil,
        firstMessageStartsDayOverride: nil, hasMoreMessages: false,
        isLoadingEarlier: false, bottomContentInset: 0,
        unreadMessageID: nil, highlightedMessageID: nil,
        initialScrollTarget: .bottom, scrollRequest: nil,
        runsPerformanceAutoScroll: false, loadEarlier: {}, openReply: { _ in },
        onScrollActivityChange: { _ in }, onScrollStateChange: { _ in },
        onUserScrollBegan: {}, onUserScrollEnded: { _ in }
    )
    let coordinator = timeline.makeCoordinator()
    let scrollView = coordinator.makeScrollView()
    defer { coordinator.stopObserving() }
    scrollView.frame = CGRect(x: 0, y: 0, width: 820, height: 300)
    scrollView.tile()
    scrollView.layoutSubtreeIfNeeded()
    coordinator.update(parent: timeline, scrollView: scrollView)
    coordinator.reconcileViewportGeometryForTesting()
    let canvas = try #require(coordinator.canvas)
    canvas.suppressesHoverPresentation = true

    if changesPresentation {
        model.invalidateTimelinePresentation()
    } else {
        model.replaceSelectedMessages(with: messages)
    }
    coordinator.update(parent: timeline, scrollView: scrollView)
    let preparation = try #require(coordinator.layoutPreparationTask)
    #expect(coordinator.messageIDs == original.map(\.id))

    if replacesDuringPreparation {
        let replacement = Array(original.suffix(5))
        model.replaceSelectedMessages(with: replacement)
        coordinator.update(parent: timeline, scrollView: scrollView)
        await preparation.value
        #expect(coordinator.layoutPreparationTask == nil)
        #expect(coordinator.messageIDs == replacement.map(\.id))
    } else {
        canvas.suppressesHoverPresentation = false
        await preparation.value
        #expect(coordinator.layoutPreparationTask == nil)
        #expect(coordinator.messageIDs == messages.map(\.id))
        #expect(coordinator.recentLayoutCacheHits == (changesPresentation ? coordinator.items.count : 64))
        #expect(coordinator.items.count == coordinator.layouts.count)
        #expect(coordinator.layouts.count == coordinator.rowHeights.count)
    }
}
