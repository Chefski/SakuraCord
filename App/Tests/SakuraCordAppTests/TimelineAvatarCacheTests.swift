import AppKit
@testable import SakuraCord
import SakuraCordModels
import Testing

@MainActor
@Test(arguments: [false, true])
func `timeline replaces cached avatar placeholders without hover`(
    detachesConversation: Bool
) async throws {
    let url = URL(fileURLWithPath: "/tmp/avatar-cache-\(UUID()).png")
    let key = NativeTimelineMediaKey.avatar(url)
    let message = Message(
        id: MessageID(rawValue: 8_900),
        channelID: ChannelID(rawValue: 8_901),
        author: User(
            id: UserID(rawValue: 8_902),
            username: "avatar.fixture",
            displayName: "Avatar Fixture",
            avatarURL: url
        ),
        content: "Avatar cache regression"
    )
    let item = NativeMessageTimelineItem.message(
        MessageRowPresentation(
            message: message,
            startsGroup: true,
            startsDay: false,
            replyPreview: nil,
            isReplyAvailable: false
        ),
        isUnreadBoundary: false,
        isHighlighted: false
    )
    let layout = NativeTimelineRowLayout.make(item: item, width: 560)
    let canvas = NativeTimelineCanvasView(
        frame: CGRect(x: 0, y: 0, width: 560, height: layout.height)
    )
    canvas.storage.items = [item]
    canvas.storage.layouts = [layout]
    canvas.storage.rowOrigins = [0]
    canvas.storage.contentHeight = layout.height
    let scrollView = NSScrollView(frame: canvas.frame)
    scrollView.documentView = canvas
    #expect(canvas.rowFrame(at: 0).intersects(scrollView.documentVisibleRect))
    let store = NativeTimelineMediaStore.shared
    defer {
        scrollView.documentView = nil
        canvas.clearBitmapCache(keepingCapacity: false)
        store.releaseVisibleImages(owner: canvas.visibleMediaPinOwner)
        store.evictVolatileImageForTesting(for: key)
    }

    _ = canvas.bitmap(
        for: item, at: 0, layout: layout, width: 560,
        preparedMediaKeys: [key]
    )
    #expect(canvas.cachedBitmap(for: item, width: 560) != nil)
    canvas.enqueueVisibleMediaRequests(identifier: item.identifier, keys: [key])
    if detachesConversation {
        canvas.invalidateConversationTransientCaches()
    }

    // Finish another row's shared load before the deferred request subscribes.
    store.retainVisibleImages(for: [key], owner: canvas.visibleMediaPinOwner)
    store.cacheImageForTesting(NSImage(size: NSSize(width: 32, height: 32)), for: key)
    if !detachesConversation {
        let request = try #require(canvas.visibleMediaRequestTask)
        await request.value
        await canvas.mediaInvalidationTask?.value
        #expect(canvas.bitmapCache[item.identifier] == nil)
    }
    #expect(canvas.cachedBitmap(for: item, width: 560) == nil)
    _ = canvas.bitmap(
        for: item, at: 0, layout: layout, width: 560,
        preparedMediaKeys: [key]
    )
    #expect(canvas.rowRasterCount == 2)
    #expect(canvas.bitmapCache[item.identifier]?.missingMediaKeys.isEmpty == true)
    #expect(canvas.cachedBitmap(for: item, width: 560) != nil)

    // A complete row must stay warm instead of entering a redraw loop.
    canvas.enqueueVisibleMediaRequests(identifier: item.identifier, keys: [key])
    #expect(canvas.visibleMediaRequestTask == nil)
    #expect(canvas.pendingVisibleMediaRequests.isEmpty)
}
