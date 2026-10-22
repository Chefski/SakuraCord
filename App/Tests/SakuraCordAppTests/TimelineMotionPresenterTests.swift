@testable import SakuraCord
import AppKit
import SakuraCordModels
import Testing

/// While a width changes, the motion presenter shows the timeline's rows as
/// layers over a hidden canvas. Once it hands back, nothing of it stays: the
/// canvas shows, and the timeline at rest is pixel for pixel as before.
@MainActor
@Test
func `the motion presenter hands the rows back to the canvas with nothing left over`() async throws {
    let model = AppModel(launchMode: .offlineTesting)
    let channelID = ChannelID(rawValue: 99_600)
    let author = User(id: UserID(rawValue: 99_601), username: "presenter", displayName: "Presenter")
    model.replaceSelectedMessages(with: (0 ..< 8).map {
        Message(
            id: MessageID(rawValue: UInt64(300_000 + $0)), channelID: channelID, author: author,
            content: "Message \($0) wraps across a line or two when the timeline narrows as a column slides in."
        )
    })
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
    scrollView.frame = CGRect(x: 0, y: 0, width: 820, height: 600)
    let window = NSWindow(contentRect: scrollView.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = scrollView
    defer { window.contentView = nil }
    coordinator.update(parent: timeline, scrollView: scrollView)
    coordinator.reconcileViewportGeometryForTesting()
    scrollView.layoutSubtreeIfNeeded()
    let canvas = try #require(coordinator.canvas)
    let atRest = render(scrollView)

    let presenter = coordinator.motionPresenter
    #expect(presenter.begin())
    // The worker paints the rows for the new width; until then the canvas
    // keeps showing them. Workspace motions in tests running alongside end
    // presenters as they settle: this window is never in a live resize.
    let deadline = ContinuousClock.now + .seconds(30)
    while presenter.presentedWidth != 700, ContinuousClock.now < deadline {
        if !presenter.isActive { _ = presenter.begin() }
        _ = presenter.present(width: 700)
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(presenter.presentedWidth == 700)
    #expect(canvas.isHidden)
    #expect(scrollView.subviews.contains { $0 is NativeTimelineMotionOverlayView })

    presenter.end()
    #expect(!presenter.isActive)
    #expect(!canvas.isHidden)
    #expect(!scrollView.subviews.contains { $0 is NativeTimelineMotionOverlayView })
    #expect(render(scrollView) == atRest)
}

@MainActor
private func render(_ view: NSView) -> [UInt8] {
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.bitmapData else { return [] }
    return Array(UnsafeBufferPointer(start: data, count: representation.bytesPerRow * representation.pixelsHigh))
}
