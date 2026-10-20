import AppKit
import Observation
import QuartzCore
import SakuraCordModels
import SwiftUI

/// What the board shows. The SwiftUI shell builds it from the model; the
/// board resolves per-card presentation itself, for visible cards only.
struct ForumBoardSnapshot: Equatable {
    /// Changing it scrolls back to the first post: a new query must not keep a
    /// deep offset into a different, possibly shorter, result.
    struct Query: Equatable {
        let channelID: ChannelID
        let searchText: String
        let tagIDs: Set<ForumTagID>
        let tagMatch: ForumTagMatch
        let sortOrder: ForumSortOrder
    }

    let query: Query
    let mode: ForumLayout
    let posts: [ForumPost]
    let recentCount: Int
    let showsPlaceholders: Bool
    let isLoadingMore: Bool
    let paginationError: String?
    let hasMore: Bool

    var items: [ForumBoardItem] {
        if posts.isEmpty, showsPlaceholders {
            return (0 ..< 8).map(ForumBoardItem.placeholder)
        }
        var items: [ForumBoardItem] = []
        items.reserveCapacity(posts.count + 4)
        for (index, post) in posts.enumerated() {
            if index == recentCount, index > 0 || recentCount == 0, index < posts.count {
                items.append(.olderPostsHeader)
            }
            items.append(.post(ForumCardGeometryInput(post: post)))
        }
        if isLoadingMore {
            items += (0 ..< (mode == .gallery ? 3 : 2)).map { .placeholder(100 + $0) }
        } else if paginationError != nil {
            items.append(.paginationStatus)
        }
        return items
    }
}

struct NativeForumBoardView: NSViewRepresentable {
    let model: AppModel
    let channel: Channel
    let snapshot: ForumBoardSnapshot
    /// The SwiftUI header's height; the board scrolls beneath it.
    let headerHeight: CGFloat

    func makeNSView(context _: Context) -> ForumBoardScrollView {
        ForumBoardScrollView()
    }

    func updateNSView(_ scrollView: ForumBoardScrollView, context _: Context) {
        scrollView.headerHeight = headerHeight
        scrollView.board.update(model: model, channel: channel, snapshot: snapshot)
    }

    static func dismantleNSView(_ scrollView: ForumBoardScrollView, coordinator _: ()) {
        scrollView.board.tearDown()
    }
}

final class ForumBoardScrollView: NSScrollView {
    let board = ForumBoardView()
    var headerHeight: CGFloat = 0 {
        didSet { if headerHeight != oldValue { updateTopInset() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        verticalScrollElasticity = .allowed
        horizontalScrollElasticity = .none
        automaticallyAdjustsContentInsets = false
        documentView = board
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            board,
            selector: #selector(ForumBoardView.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
        setAccessibilityIdentifier("forum-board-scroll")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        updateTopInset()
        board.viewportDidResize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTopInset()
    }

    /// Insets the first post below the window toolbar and the SwiftUI header,
    /// both of which the board extends beneath.
    private func updateTopInset() {
        guard let window else { return }
        let frameInWindow = convert(bounds, to: nil)
        let toolbarHeight = max(0, frameInWindow.maxY - window.contentLayoutRect.maxY)
        let top = toolbarHeight + headerHeight
        guard abs(contentInsets.top - top) > 0.25 else { return }
        let wasAtTop = contentView.bounds.minY <= -contentInsets.top + 1
        var insets = contentInsets
        insets.top = top
        contentInsets = insets
        if wasAtTop {
            contentView.scroll(to: NSPoint(x: 0, y: -top))
            reflectScrolledClipView(contentView)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard WindowModalCoordinator.allowsInput(for: self) else { return }
        super.scrollWheel(with: event)
    }
}

/// The forum's post board: a flipped document view whose visible items are
/// recycled `ForumBoardCard` layers painted with Core Graphics and Core Text.
///
/// It replaced a SwiftUI `LazyVStack`/`LazyVGrid` of cards, whose rows changed
/// height as starter messages, thumbnails, reactions and fonts arrived. Here
/// geometry comes only from `ForumBoardLayout`, late data repaints in place,
/// and structural changes animate on the compositor.
final class ForumBoardView: NSView, NSViewToolTipOwner {
    private weak var model: AppModel?
    private var channel: Channel?
    private var snapshot: ForumBoardSnapshot?
    private var items: [ForumBoardItem] = []
    private var postsByID: [ChannelID: ForumPost] = [:]
    private var layoutState: ForumBoardLayout?
    private var metrics = ForumBoardMetrics.current()
    private var titleCounter: ForumTitleLineCounter
    private let cardsLayer = CALayer()
    private var cards: [ForumBoardItem.Identifier: ForumBoardCard] = [:]
    private var reusableCards: [ForumBoardCard] = []
    private var presentations: [ChannelID: ForumCardPresentation] = [:]
    private var regions: [ForumBoardItem.Identifier: ForumCardRegions] = [:]
    private var excerptRenderers: [ChannelID: ForumPostPreviewTextRenderer] = [:]
    private var interactions: [ForumBoardItem.Identifier: ForumCardInteraction] = [:]
    private var hoveredID: ForumBoardItem.Identifier?
    private var pressedID: ForumBoardItem.Identifier?
    private var keyboardID: ForumBoardItem.Identifier?
    private var trackingArea: NSTrackingArea?
    private let mediaOwner = UUID()
    private var requestedMediaKeys: Set<NativeTimelineMediaKey> = []
    private var presentationRefreshScheduled = false
    private var observationGeneration = 0
    private var minuteTimer: Timer?
    private var lastLayoutWidth: CGFloat = 0
    private var lastScale: CGFloat = InterfaceScale.factor
    private var menuCoordinator: ForumPostContextMenuBridge.Coordinator?
    private var isReactionTooltipShown = false
    private let reactionTooltip = StableAnchoredPopoverPresenter<MessageReactionTooltip>.Coordinator()
    private var accessibilityProxies: [ChannelID: ForumBoardAccessibilityProxyView] = [:]
    private var lastPaginationRequestCount = -1
    private var realizedIDs = Set<ForumBoardItem.Identifier>()
    private var settledWorkTask: Task<Void, Never>?
    private var needsObservationRefresh = false

    override var isFlipped: Bool { true }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    init() {
        titleCounter = ForumTitleLineCounter(font: metrics.titleFont, maximumLines: metrics.maximumTitleLines)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        cardsLayer.anchorPoint = .zero
        layer?.addSublayer(cardsLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Forum posts")
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(fontsDidLoad), name: ProfileNameFontLoader.didLoadFonts, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func tearDown() {
        settledWorkTask?.cancel()
        minuteTimer?.invalidate()
        minuteTimer = nil
        reactionTooltip.close()
        NativeTimelineMediaStore.shared.releaseVisibleImages(owner: mediaOwner)
        NativeTimelineMediaStore.shared.cancelStaticRequestsOutsideVisibleSet(owner: mediaOwner)
        for renderer in excerptRenderers.values { renderer.stopObservingReveals() }
        excerptRenderers.removeAll()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            minuteTimer?.invalidate()
            minuteTimer = nil
            return
        }
        orientCardsLayer()
        if minuteTimer == nil {
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.repaintVisibleCards(fading: false) }
            }
            RunLoop.main.add(timer, forMode: .common)
            minuteTimer = timer
        }
        #if DEBUG
        if let scrollView = enclosingScrollView {
            ForumBoardBenchmark.register(scrollView: scrollView)
        }
        #endif
    }

    /// Card coordinates are top-down like the view's. AppKit may or may not
    /// flip a flipped view's backing layer, so the host layer adapts.
    private func orientCardsLayer() {
        guard let layer else { return }
        if cardsLayer.superlayer !== layer { layer.addSublayer(cardsLayer) }
        cardsLayer.isGeometryFlipped = false
        cardsLayer.isGeometryFlipped = !cardsLayer.contentsAreFlipped()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for (id, card) in cards { applyChrome(card, id: id, animated: false) }
        repaintVisibleCards(fading: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for card in cards.values {
            card.render(scale: scale, fading: false)
        }
    }

    @objc private func fontsDidLoad() { repaintVisibleCards(fading: false) }

    @objc private func displayOptionsDidChange() {
        for (id, card) in cards { refreshShimmer(card, id: id) }
    }

    // MARK: Updates

    func update(model: AppModel, channel: Channel, snapshot: ForumBoardSnapshot) {
        let previousSnapshot = self.snapshot
        let channelChanged = self.channel?.id != channel.id
        self.model = model
        self.channel = channel
        guard previousSnapshot != snapshot || channelChanged else {
            schedulePresentationRefresh()
            return
        }
        self.snapshot = snapshot
        postsByID = Dictionary(snapshot.posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let queryChanged = previousSnapshot?.query != snapshot.query
        let modeChanged = previousSnapshot?.mode != snapshot.mode
        let wasShowingPlaceholders = previousSnapshot.map { $0.posts.isEmpty && $0.showsPlaceholders } ?? true
        let newItems = snapshot.items
        let structureChanged = newItems != items || modeChanged
        items = newItems
        if queryChanged || channelChanged {
            presentations.removeAll()
            lastPaginationRequestCount = -1
        }
        if structureChanged || layoutState == nil {
            let transition: ForumBoardTransition =
                previousSnapshot == nil || channelChanged ? .none
                    : wasShowingPlaceholders || queryChanged ? .reveal
                    : modeChanged ? .morph
                    : .reflow
            if transition == .morph, !reducesMotion {
                // List and gallery cards differ too much to glide between;
                // the whole board cross-fades, then tiles settle in.
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.22
                cardsLayer.add(fade, forKey: "morph")
            }
            relayout(transition: transition == .morph ? .none : transition, scrollsToTop: queryChanged || channelChanged)
        } else {
            refreshVisibleCards(transition: .none)
        }
        schedulePresentationRefresh()
    }

    func viewportDidResize() {
        guard let scrollView = enclosingScrollView else { return }
        let width = scrollView.contentView.bounds.width
        let scale = InterfaceScale.factor
        guard width > 0, abs(width - lastLayoutWidth) > 0.5 || scale != lastScale else {
            refreshVisibleCards(transition: .none)
            return
        }
        relayout(transition: .none, scrollsToTop: false)
    }

    @objc func clipViewBoundsDidChange(_: Notification) {
        refreshVisibleCards(transition: .none)
        updateHoverFromCurrentPointer()
        requestNextPageIfNeeded()
    }

    private func relayout(transition: ForumBoardTransition, scrollsToTop: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        let width = scrollView.contentView.bounds.width
        guard width > 0 else { return }
        if InterfaceScale.factor != lastScale || metrics.scale != InterfaceScale.factor {
            metrics = ForumBoardMetrics.current()
            titleCounter = ForumTitleLineCounter(font: metrics.titleFont, maximumLines: metrics.maximumTitleLines)
            lastScale = InterfaceScale.factor
            regions.removeAll()
        }
        let anchor = transition == .none && !scrollsToTop ? scrollAnchor() : nil
        let counter = titleCounter
        let signpost = AppPerformanceSignposts.signposter.beginInterval("ForumBoardLayout")
        let newLayout = ForumBoardLayout.make(
            items: items,
            mode: snapshot?.mode ?? .list,
            width: width,
            metrics: metrics,
            titleLines: { counter.lines($0, width: $1) }
        )
        AppPerformanceSignposts.signposter.endInterval("ForumBoardLayout", signpost)
        let widthChanged = abs(width - lastLayoutWidth) > 0.5
        lastLayoutWidth = width
        layoutState = newLayout
        if widthChanged { regions.removeAll() }
        let height = max(newLayout.contentHeight, scrollView.contentView.bounds.height - scrollView.contentInsets.top)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setFrameSize(NSSize(width: width, height: height))
        cardsLayer.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        CATransaction.commit()
        if scrollsToTop {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else if let anchor {
            restore(anchor)
        }
        // Geometry changed under the same cards: rebuild settled state too.
        realizedIDs = []
        refreshVisibleCards(transition: transition)
        window?.invalidateCursorRects(for: self)
    }

    private struct ScrollAnchor {
        let id: ForumBoardItem.Identifier
        let offset: CGFloat
    }

    private func scrollAnchor() -> ScrollAnchor? {
        guard let layoutState else { return nil }
        let visible = visibleRect
        guard visible.minY > 1,
              let entry = layoutState.entries(intersecting: visible).first(where: { $0.frame.maxY > visible.minY })
        else { return nil }
        return ScrollAnchor(id: entry.item.id, offset: entry.frame.minY - visible.minY)
    }

    private func restore(_ anchor: ScrollAnchor) {
        guard let scrollView = enclosingScrollView, let entry = layoutState?.entry(for: anchor.id) else { return }
        let maximum = max(-scrollView.contentInsets.top, frame.height - scrollView.contentView.bounds.height)
        let targetY = min(max(-scrollView.contentInsets.top, entry.frame.minY - anchor.offset), maximum)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Visible cards

    private var realizationRect: CGRect {
        let visible = visibleRect
        let overscan = max(InterfaceScale.metric(360), visible.height * 0.6)
        return visible.insetBy(dx: 0, dy: -overscan)
    }

    private func refreshVisibleCards(transition: ForumBoardTransition) {
        guard let layoutState else { return }
        let realized = layoutState.entries(intersecting: realizationRect)
        var liveIDs = Set<ForumBoardItem.Identifier>()
        let animates = transition != .none
        let visible = visibleRect
        var revealIndex = 0
        var realizedNewPost = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for entry in realized {
            let id = entry.item.id
            liveIDs.insert(id)
            if let card = cards[id] {
                let oldFrame = card.frame
                // Scrolling leaves realized cards untouched.
                guard oldFrame != entry.frame || transition != .none else { continue }
                configure(card, entry: entry)
                if animates, oldFrame != entry.frame, oldFrame.intersects(visible) || entry.frame.intersects(visible) {
                    animateMove(card, from: oldFrame)
                }
            } else {
                let card = dequeueCard()
                cards[id] = card
                if case let .post(postID) = id, presentations[postID] == nil {
                    // Resolve before the first paint, so a card scrolled into
                    // view never shows an empty frame for a turn.
                    resolvePresentation(for: postID)
                    realizedNewPost = true
                }
                configure(card, entry: entry)
                cardsLayer.addSublayer(card.layer)
                if animates, entry.frame.intersects(visible) {
                    animateEntrance(card, delay: transition == .reveal ? Double(min(revealIndex, 10)) * 0.025 : 0)
                    revealIndex += 1
                } else if case .placeholder = entry.item {
                    animatePlaceholderEntrance(card)
                }
            }
        }
        for (id, card) in cards where !liveIDs.contains(id) {
            cards[id] = nil
            regions[id] = nil
            interactions[id] = nil
            if animates, card.frame.intersects(visible) {
                animateExit(card)
            } else {
                recycle(card)
            }
        }
        CATransaction.commit()
        let livePostIDs = Set(liveIDs.compactMap { if case let .post(id) = $0 { id } else { nil } })
        for id in excerptRenderers.keys where !livePostIDs.contains(id) {
            excerptRenderers[id]?.stopObservingReveals()
            excerptRenderers[id] = nil
        }
        reportStability()
        guard liveIDs != realizedIDs || transition != .none else { return }
        realizedIDs = liveIDs
        refreshMedia()
        if realizedNewPost { needsObservationRefresh = true }
        scheduleSettledWork()
    }

    /// Tooltips, accessibility proxies and observation of newly realized
    /// cards wait until scrolling pauses; cards are already painted, so
    /// this keeps per-frame work to realizing and positioning layers.
    private func scheduleSettledWork() {
        settledWorkTask?.cancel()
        let assistiveTechnology = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        if assistiveTechnology { updateAccessibilityChildren() }
        settledWorkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            rebuildToolTips()
            if !assistiveTechnology { updateAccessibilityChildren() }
            window?.invalidateCursorRects(for: self)
            if needsObservationRefresh {
                needsObservationRefresh = false
                schedulePresentationRefresh()
            }
        }
    }

    private func resolvePresentation(for postID: ChannelID) {
        guard let model, let channel, let post = postsByID[postID] else { return }
        presentations[postID] = model.forumCardPresentation(for: post, in: channel)
        configureExcerpt(for: postID)
    }

    private func dequeueCard() -> ForumBoardCard {
        if let card = reusableCards.popLast() {
            card.layer.removeAllAnimations()
            card.layer.opacity = 1
            card.layer.transform = CATransform3DIdentity
            return card
        }
        return ForumBoardCard()
    }

    private func recycle(_ card: ForumBoardCard) {
        card.layer.removeFromSuperlayer()
        card.clearContent()
        card.updateShimmer(frames: [], color: .clear, animates: false)
        if reusableCards.count < 24 { reusableCards.append(card) }
    }

    private func configure(_ card: ForumBoardCard, entry: ForumBoardLayout.Entry) {
        let id = entry.item.id
        let kind: ForumBoardCard.Kind =
            switch entry.item {
            case .post: .card
            case .placeholder: .placeholder
            case .olderPostsHeader: .sectionHeader
            case .paginationStatus: .paginationStatus
            }
        let sizeChanged = card.frame.size != entry.frame.size || card.kind != kind
        card.configure(kind: kind, cornerRadius: metrics.cardCornerRadius)
        card.frame = entry.frame
        card.painter = { [weak self] size in
            self?.paint(id: id, size: size)
        }
        if sizeChanged || !card.hasContent {
            regions[id] = nil
            card.render(scale: backingScale, fading: false)
        }
        applyChrome(card, id: id, animated: false)
        refreshShimmer(card, id: id)
    }

    private func applyChrome(_ card: ForumBoardCard, id: ForumBoardItem.Identifier, animated: Bool) {
        let postID: ChannelID? = if case let .post(value) = id { value } else { nil }
        card.applyChrome(
            isHovered: hoveredID == id || keyboardID == id,
            isKeyboardFocused: keyboardID == id,
            isPressed: pressedID == id,
            isSelected: postID != nil && postID == model?.openThread?.id,
            appearance: effectiveAppearance,
            animated: animated
        )
    }

    private func refreshShimmer(_ card: ForumBoardCard, id: ForumBoardItem.Identifier) {
        let frames = cardRegions(for: id)?.skeletonFrames ?? []
        var color = NSColor.white
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.withAlphaComponent(0.09)
        }
        card.updateShimmer(
            frames: frames,
            color: color,
            animates: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                && window?.occlusionState.contains(.visible) != false
        )
    }

    // MARK: Animation

    /// Reduce Motion replaces travel and scaling with cross-fades.
    private var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func animateMove(_ card: ForumBoardCard, from oldFrame: CGRect) {
        if reducesMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.4
            fade.toValue = 1
            fade.duration = 0.22
            card.layer.add(fade, forKey: "move")
            return
        }
        let spring = CASpringAnimation(keyPath: "position")
        spring.fromValue = NSValue(point: CGPoint(
            x: oldFrame.minX + oldFrame.width * card.layer.anchorPoint.x,
            y: oldFrame.minY + oldFrame.height * card.layer.anchorPoint.y
        ))
        spring.toValue = NSValue(point: card.layer.position)
        spring.damping = 26
        spring.stiffness = 260
        spring.mass = 1
        spring.duration = min(spring.settlingDuration, 0.55)
        card.layer.add(spring, forKey: "move")
    }

    private func animateEntrance(_ card: ForumBoardCard, delay: CFTimeInterval) {
        let group = CAAnimationGroup()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let lift = CABasicAnimation(keyPath: "transform")
        lift.fromValue = NSValue(caTransform3D: CATransform3DConcat(
            CATransform3DMakeScale(0.97, 0.97, 1),
            CATransform3DMakeTranslation(0, InterfaceScale.metric(8), 0)
        ))
        lift.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        group.animations = reducesMotion ? [fade] : [fade, lift]
        group.duration = 0.28
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        card.layer.add(group, forKey: "entrance")
    }

    /// Placeholders appear only if loading lasts long enough to notice, so a
    /// fast load never flashes skeletons.
    private func animatePlaceholderEntrance(_ card: ForumBoardCard) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        fade.beginTime = CACurrentMediaTime() + 0.12
        fade.fillMode = .backwards
        card.layer.add(fade, forKey: "placeholder-entrance")
    }

    private func animateExit(_ card: ForumBoardCard) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak card] in
            guard let card else { return }
            MainActor.assumeIsolated { self?.recycle(card) }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = card.layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.18
        card.layer.opacity = 0
        card.layer.add(fade, forKey: "exit")
        CATransaction.commit()
    }

    // MARK: Presentation

    /// Resolves presentation for realized posts under observation, so any
    /// model change that affects a visible card (read state, reactions,
    /// selection, emoji URLs, members) repaints just that card.
    private func schedulePresentationRefresh() {
        guard !presentationRefreshScheduled else { return }
        presentationRefreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshPresentations()
        }
    }

    private func refreshPresentations() {
        presentationRefreshScheduled = false
        guard let model, let channel else { return }
        observationGeneration &+= 1
        let generation = observationGeneration
        var changed: [ChannelID] = []
        withObservationTracking {
            for id in cards.keys {
                guard case let .post(postID) = id, let post = postsByID[postID] else { continue }
                let presentation = model.forumCardPresentation(for: post, in: channel)
                if presentations[postID] != presentation {
                    changed.append(postID)
                    presentations[postID] = presentation
                }
            }
            _ = model.openThread?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, observationGeneration == generation else { return }
                schedulePresentationRefresh()
            }
        }
        for postID in changed {
            let id = ForumBoardItem.Identifier.post(postID)
            if isReactionTooltipShown, hoveredID == id, interactions[id]?.isReactionHovered == true,
               let summary = presentations[postID]?.reaction
            {
                presentReactionTooltip(postID: postID, summary: summary, event: nil)
            }
            regions[id] = nil
            guard let card = cards[id] else { continue }
            configureExcerpt(for: postID)
            applyChrome(card, id: id, animated: true)
            refreshShimmer(card, id: id)
            card.render(scale: backingScale, fading: card.hasContent)
        }
        if !changed.isEmpty {
            refreshMedia()
            rebuildToolTips()
            updateAccessibilityChildren()
        }
    }

    private func configureExcerpt(for postID: ChannelID) {
        guard let model, let presentation = presentations[postID] else { return }
        let message: Message?
        let lines: Int
        var prefix: ForumPostPreviewTextView.Prefix?
        if snapshot?.mode == .gallery {
            guard case let .text(value) = presentation.hero else {
                excerptRenderers[postID] = nil
                return
            }
            message = value
            let tagReserve = presentation.tags.isEmpty ? 0 : InterfaceScale.metric(34)
            lines = max(1, Int((metrics.galleryHeroHeight - InterfaceScale.metric(28) - tagReserve) / metrics.excerptLineHeight))
        } else {
            guard case let .message(value, author) = presentation.excerpt else {
                excerptRenderers[postID] = nil
                return
            }
            message = value
            lines = metrics.excerptLines
            prefix = authorPrefix(author)
        }
        guard let message else { return }
        let renderer = excerptRenderers[postID] ?? {
            let renderer = ForumPostPreviewTextRenderer()
            renderer.onDisplayChange = { [weak self] in
                guard let self, let card = cards[.post(postID)] else { return }
                card.render(scale: backingScale, fading: false)
            }
            excerptRenderers[postID] = renderer
            return renderer
        }()
        let resolver = MessageMentionResolver(model: model, message: message)
        let prepared = RichMessageAttributedText.prepare(source: message.content)
        var mentions: [String: MentionPresentation] = [:]
        for case let .mention(mention) in prepared.tokens {
            mentions[mention.rawToken] = resolver.presentation(mention)
        }
        let fontSize = metrics.excerptFont.pointSize
        renderer.configure(
            ForumPostPreviewTextView.Configuration(
                messageID: message.id,
                source: message.content,
                mentionPresentations: mentions,
                fontSize: fontSize,
                emojiSize: (fontSize * 1.375).rounded(),
                maximumNumberOfLines: lines,
                isEmphasized: presentation.isEmphasized,
                underlinesLinks: presentation.underlinesLinks,
                prefix: prefix
            ),
            revealStore: model.timelineSpoilerRevealStore
        )
    }

    private func authorPrefix(_ author: ForumCardPresentation.Author) -> ForumPostPreviewTextView.Prefix {
        let bodySize = metrics.excerptFont.pointSize
        let value = NSMutableAttributedString()
        if let dotColor = author.roleDotColor,
           let dot = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
           .withSymbolConfiguration(
               NSImage.SymbolConfiguration(pointSize: InterfaceScale.fontSize(8), weight: .regular)
                   .applying(.init(paletteColors: [dotColor]))
           )
        {
            let attachment = NSTextAttachment()
            attachment.image = dot
            attachment.bounds = CGRect(origin: CGPoint(x: 0, y: 1), size: dot.size)
            value.append(NSAttributedString(attachment: attachment))
            value.append(NSAttributedString(string: " "))
        }
        let fallback = NSFont.interfaceSystemFont(ofSize: bodySize, weight: .semibold)
        ProfileNameFontLoader.shared.request(id: author.fontID)
        value.append(NSAttributedString(
            string: author.name,
            attributes: [
                .font: ProfileNameFontCache.font(id: author.fontID, fallback: fallback),
                .foregroundColor: author.color ?? NSColor.labelColor,
            ]
        ))
        value.append(NSAttributedString(
            string: ": ",
            attributes: [.font: NSFont.interfaceSystemFont(ofSize: bodySize), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return ForumPostPreviewTextView.Prefix(value: value, accessibilityText: "\(author.name): ")
    }

    private func repaintVisibleCards(fading: Bool) {
        for (id, card) in cards {
            regions[id] = nil
            card.render(scale: backingScale, fading: fading)
        }
        rebuildToolTips()
    }

    // MARK: Painting

    private func cardRegions(for id: ForumBoardItem.Identifier) -> ForumCardRegions? {
        if let cached = regions[id] { return cached }
        guard let entry = layoutState?.entry(for: id) else { return nil }
        let value: ForumCardRegions
        switch entry.item {
        case let .post(input):
            guard let presentation = presentations[input.id] else {
                value = ForumCardPainter.regions(for: nil, mode: layoutState?.mode ?? .list, size: entry.frame.size, titleLines: entry.titleLines, metrics: metrics)
                    .withoutSkeleton()
                regions[id] = value
                return value
            }
            value = ForumCardPainter.regions(for: presentation, mode: layoutState?.mode ?? .list, size: entry.frame.size, titleLines: entry.titleLines, metrics: metrics)
        case .placeholder:
            value = ForumCardPainter.regions(for: nil, mode: layoutState?.mode ?? .list, size: entry.frame.size, titleLines: 1, metrics: metrics)
        case .olderPostsHeader, .paginationStatus:
            value = ForumCardRegions()
        }
        regions[id] = value
        return value
    }

    private func paint(id: ForumBoardItem.Identifier, size: CGSize) {
        guard let entry = layoutState?.entry(for: id) else { return }
        let bounds = CGRect(origin: .zero, size: size)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch entry.item {
            case let .post(input):
                guard let presentation = presentations[input.id], let regions = cardRegions(for: id) else { return }
                if !regions.skeletonFrames.isEmpty {
                    ForumCardPainter.drawSkeleton(regions.skeletonFrames)
                }
                if let renderer = excerptRenderers[input.id], let frame = layoutState?.mode == .gallery ? regions.heroFrame : regions.excerptFrame {
                    renderer.size = CGSize(width: frame.width - (layoutState?.mode == .gallery ? InterfaceScale.metric(32) : 0), height: frame.height)
                }
                ForumCardPainter.draw(ForumCardPainter.DrawInput(
                    presentation: presentation,
                    mode: layoutState?.mode ?? .list,
                    regions: regions,
                    titleLines: entry.titleLines,
                    excerpt: excerptRenderers[input.id],
                    interaction: interactions[id] ?? ForumCardInteraction(),
                    model: model,
                    metrics: metrics
                ))
            case .placeholder:
                if let regions = cardRegions(for: id) {
                    ForumCardPainter.drawSkeleton(regions.skeletonFrames)
                }
            case .olderPostsHeader:
                ForumCardPainter.drawSectionHeader("Older Posts", in: bounds)
            case .paginationStatus:
                ForumCardPainter.drawPaginationError(
                    snapshot?.paginationError ?? "",
                    in: bounds,
                    isRetryHovered: interactions[id]?.isRetryHovered == true
                )
            }
        }
    }

    // MARK: Media

    private func refreshMedia() {
        var keys = Set<NativeTimelineMediaKey>()
        var keysByPost: [ChannelID: Set<NativeTimelineMediaKey>] = [:]
        for id in cards.keys {
            guard case let .post(postID) = id, let presentation = presentations[postID] else { continue }
            var postKeys = Set<NativeTimelineMediaKey>()
            if let key = presentation.thumbnail?.mediaKey { postKeys.insert(key) }
            for tag in presentation.tags {
                if let key = tag.emoji?.mediaKey { postKeys.insert(key) }
            }
            if let reaction = presentation.reaction?.reaction {
                let reference = reaction.emojiReference
                if let emojiID = reference.id,
                   let url = model?.customEmojiURLsByID[emojiID] ?? reference.imageURL(size: 64)
                {
                    postKeys.insert(.media(url, maximumPixelDimension: 64))
                }
                for reactor in MessageReactionPresentation.previewPlan(for: reaction).reactors {
                    if let url = reactor.avatarURL { postKeys.insert(.avatar(url)) }
                }
            }
            keys.formUnion(postKeys)
            keysByPost[postID] = postKeys
        }
        let store = NativeTimelineMediaStore.shared
        store.retainVisibleImages(for: keys, owner: mediaOwner)
        for (postID, postKeys) in keysByPost {
            for key in postKeys where store.image(for: key) == nil {
                // The store keys subscribers by timeline item; a forum post is
                // the same post identity the Inbox uses.
                store.request(key, owner: mediaOwner, subscriber: .inboxForumPost(postID)) { [weak self] outcome in
                    guard outcome == .ready, let self else { return }
                    cards[.post(postID)]?.render(scale: backingScale, fading: true)
                }
            }
        }
        requestedMediaKeys = keys
        store.cancelStaticRequestsOutsideVisibleSet(owner: mediaOwner)
    }

    // MARK: Pagination

    private func requestNextPageIfNeeded() {
        guard let snapshot, snapshot.hasMore, !snapshot.isLoadingMore, snapshot.paginationError == nil,
              let model
        else { return }
        let visible = visibleRect
        guard visible.maxY > frame.height - visible.height * 1.5 else { return }
        guard lastPaginationRequestCount != snapshot.posts.count else { return }
        lastPaginationRequestCount = snapshot.posts.count
        Task { await model.loadMoreForumPosts() }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private struct Hit {
        let entry: ForumBoardLayout.Entry
        let local: CGPoint
    }

    private func hit(at point: CGPoint) -> Hit? {
        guard let layoutState else { return nil }
        let probe = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        guard let entry = layoutState.entries(intersecting: probe).first(where: { $0.frame.contains(point) }) else { return nil }
        return Hit(entry: entry, local: CGPoint(x: point.x - entry.frame.minX, y: point.y - entry.frame.minY))
    }

    private func isInteractive(_ item: ForumBoardItem) -> Bool {
        switch item {
        case .post, .paginationStatus: true
        case .placeholder, .olderPostsHeader: false
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil), event: event)
    }

    override func mouseExited(with _: NSEvent) {
        setHovered(nil)
        clearInnerHover()
    }

    private func updateHoverFromCurrentPointer() {
        guard let window, window.isKeyWindow else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else {
            setHovered(nil)
            clearInnerHover()
            return
        }
        updateHover(at: point, event: nil)
    }

    private func updateHover(at point: CGPoint, event: NSEvent?) {
        guard WindowModalCoordinator.allowsInput(for: self) else {
            setHovered(nil)
            clearInnerHover()
            return
        }
        guard let hit = hit(at: point), isInteractive(hit.entry.item) else {
            setHovered(nil)
            clearInnerHover()
            return
        }
        setHovered(hit.entry.item.id)
        let id = hit.entry.item.id
        var interaction = interactions[id] ?? ForumCardInteraction()
        let previous = interaction
        switch hit.entry.item {
        case let .post(input):
            let regions = cardRegions(for: id)
            let isOnReaction = regions?.reactionRegionFrame?.contains(hit.local) == true
            interaction.isReactionHovered = isOnReaction
            if isOnReaction, let summary = presentations[input.id]?.reaction {
                presentReactionTooltip(postID: input.id, summary: summary, event: event)
            } else if !isOnReaction, previous.isReactionHovered {
                closeReactionTooltip()
            }
            if let renderer = excerptRenderers[input.id], let excerptOrigin = excerptOrigin(for: id) {
                let location = renderer.hiddenSpoilerLocation(at: CGPoint(x: hit.local.x - excerptOrigin.x, y: hit.local.y - excerptOrigin.y))
                if renderer.setHoveredSpoiler(location) { cards[id]?.render(scale: backingScale, fading: false) }
            }
        case .paginationStatus:
            interaction.isRetryHovered = ForumCardPainter.paginationRetryFrame(in: CGRect(origin: .zero, size: hit.entry.frame.size)).contains(hit.local)
        case .placeholder, .olderPostsHeader:
            break
        }
        for (otherID, other) in interactions where otherID != id && other != ForumCardInteraction() {
            interactions[otherID] = ForumCardInteraction()
            cards[otherID]?.render(scale: backingScale, fading: false)
        }
        if interaction != previous {
            interactions[id] = interaction
            cards[id]?.render(scale: backingScale, fading: false)
        }
    }

    private func excerptOrigin(for id: ForumBoardItem.Identifier) -> CGPoint? {
        guard let regions = cardRegions(for: id) else { return nil }
        if layoutState?.mode == .gallery {
            return regions.heroFrame.map { CGPoint(x: $0.minX + InterfaceScale.metric(16), y: $0.minY + InterfaceScale.metric(14)) }
        }
        return regions.excerptFrame?.origin
    }

    private func clearInnerHover() {
        closeReactionTooltip()
        for (id, interaction) in interactions where interaction != ForumCardInteraction() {
            interactions[id] = ForumCardInteraction()
            cards[id]?.render(scale: backingScale, fading: false)
        }
        for (postID, renderer) in excerptRenderers where renderer.setHoveredSpoiler(nil) {
            cards[.post(postID)]?.render(scale: backingScale, fading: false)
        }
    }

    private func closeReactionTooltip() {
        guard isReactionTooltipShown else { return }
        isReactionTooltipShown = false
        reactionTooltip.close()
    }

    private func setHovered(_ id: ForumBoardItem.Identifier?) {
        guard hoveredID != id else { return }
        let previous = hoveredID
        hoveredID = id
        for changed in [previous, id].compactMap(\.self) {
            if let card = cards[changed] { applyChrome(card, id: changed, animated: true) }
        }
    }

    private func presentReactionTooltip(postID: ChannelID, summary: ForumCardPresentation.ReactionSummary, event: NSEvent?) {
        guard let model, let window else { return }
        let anchor = StablePopoverAnchor(sourceView: self) { [weak self] in
            guard let self, let entry = layoutState?.entry(for: .post(postID)),
                  let frame = cardRegions(for: .post(postID))?.reactionRegionFrame
            else { return nil }
            return frame.offsetBy(dx: entry.frame.minX, dy: entry.frame.minY)
        }
        let screenPoint = NSEvent.mouseLocation
        let pointInView = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        var snapshot: StablePopoverAnchorSnapshot?
        if let source = anchor.sourceRect() {
            snapshot = StablePopoverAnchorSnapshot(
                mouseLocationInScreen: screenPoint,
                mouseLocationInSource: CGPoint(x: pointInView.x - source.minX, y: pointInView.y - source.minY)
            )
        }
        let reaction = summary.reaction
        let reference = reaction.emojiReference
        let emojiURL = reference.id.flatMap { model.customEmojiURLsByID[$0] } ?? reference.imageURL(size: 64)
        let wasShown = isReactionTooltipShown
        isReactionTooltipShown = true
        reactionTooltip.update(
            anchor: anchor,
            anchorSnapshot: snapshot,
            isPresented: true,
            configuration: .hover,
            onDismiss: { [weak self] in self?.isReactionTooltipShown = false },
            presentationIdentity: AnyHashable(postID),
            content: MessageReactionTooltip(reaction: reaction, emojiURL: emojiURL)
        )
        if !wasShown, reaction.count > 0 {
            Task { await model.loadReactionReactors(reaction, on: summary.message) }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hit(at: point), isInteractive(hit.entry.item) else { return }
        pressedID = hit.entry.item.id
        if case .post = hit.entry.item, let card = cards[hit.entry.item.id] {
            applyChrome(card, id: hit.entry.item.id, animated: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressedID else { return }
        let point = convert(event.locationInWindow, from: nil)
        let isInside = layoutState?.entry(for: pressedID)?.frame.contains(point) == true
        if let card = cards[pressedID] {
            card.applyChrome(
                isHovered: isInside,
                isKeyboardFocused: false,
                isPressed: isInside,
                isSelected: false,
                appearance: effectiveAppearance,
                animated: true
            )
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let pressedID else { return }
        self.pressedID = nil
        let point = convert(event.locationInWindow, from: nil)
        if let card = cards[pressedID] { applyChrome(card, id: pressedID, animated: true) }
        guard let hit = hit(at: point), hit.entry.item.id == pressedID else { return }
        activate(hit)
    }

    private func activate(_ hit: Hit) {
        guard let model else { return }
        switch hit.entry.item {
        case let .post(input):
            guard let post = postsByID[input.id] else { return }
            let id = hit.entry.item.id
            if let renderer = excerptRenderers[input.id], let origin = excerptOrigin(for: id),
               let location = renderer.hiddenSpoilerLocation(at: CGPoint(x: hit.local.x - origin.x, y: hit.local.y - origin.y))
            {
                renderer.revealSpoiler(at: location)
                return
            }
            if let frame = cardRegions(for: id)?.reactionRegionFrame, frame.contains(hit.local),
               let summary = presentations[input.id]?.reaction
            {
                guard !summary.isDisabled else { return }
                Task { await model.toggleReaction(summary.reaction.emoji, on: summary.message) }
                return
            }
            model.open(post)
        case .paginationStatus:
            Task { await model.loadMoreForumPosts() }
        case .placeholder, .olderPostsHeader:
            break
        }
    }

    override func resetCursorRects() {
        guard let layoutState else { return }
        for entry in layoutState.entries(intersecting: visibleRect) where isInteractive(entry.item) {
            addCursorRect(entry.frame, cursor: .pointingHand)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let layoutState else { return super.keyDown(with: event) }
        let posts = layoutState.entries.filter { $0.item.postID != nil }
        guard !posts.isEmpty else { return super.keyDown(with: event) }
        let currentIndex = keyboardID.flatMap { id in posts.firstIndex { $0.item.id == id } }
        let columns = max(1, posts.prefix(while: { $0.frame.minY == posts[0].frame.minY }).count)
        let step = layoutState.mode == .gallery ? columns : 1
        var next: Int?
        switch event.specialKey {
        case .downArrow: next = currentIndex.map { min(posts.count - 1, $0 + step) } ?? 0
        case .upArrow: next = currentIndex.map { max(0, $0 - step) } ?? 0
        case .rightArrow where layoutState.mode == .gallery: next = currentIndex.map { min(posts.count - 1, $0 + 1) } ?? 0
        case .leftArrow where layoutState.mode == .gallery: next = currentIndex.map { max(0, $0 - 1) } ?? 0
        case .carriageReturn, .enter:
            if let currentIndex, let postID = posts[currentIndex].item.postID, let post = postsByID[postID] {
                model?.open(post)
            }
            return
        default:
            if event.charactersIgnoringModifiers == " ", let currentIndex,
               let postID = posts[currentIndex].item.postID, let post = postsByID[postID]
            {
                model?.open(post)
                return
            }
            return super.keyDown(with: event)
        }
        guard let next else { return }
        let previous = keyboardID
        keyboardID = posts[next].item.id
        for id in [previous, keyboardID].compactMap(\.self) {
            if let card = cards[id] { applyChrome(card, id: id, animated: true) }
        }
        scrollToVisible(posts[next].frame.insetBy(dx: 0, dy: -metrics.cardSpacing))
    }

    override func resignFirstResponder() -> Bool {
        if let keyboardID {
            self.keyboardID = nil
            if let card = cards[keyboardID] { applyChrome(card, id: keyboardID, animated: true) }
        }
        return super.resignFirstResponder()
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let channel,
              let hit = hit(at: convert(event.locationInWindow, from: nil)),
              let postID = hit.entry.item.postID,
              let post = postsByID[postID]
        else { return nil }
        return contextMenu(for: post, model: model, channel: channel)
    }

    private func contextMenu(for post: ForumPost, model: AppModel, channel: Channel) -> NSMenu {
        let bridge = contextMenuBridge(for: post, model: model, channel: channel)
        if let menuCoordinator {
            menuCoordinator.update(from: bridge)
        } else {
            menuCoordinator = ForumPostContextMenuBridge.Coordinator(from: bridge)
        }
        return menuCoordinator?.makeMenu() ?? NSMenu()
    }

    private func contextMenuBridge(for post: ForumPost, model: AppModel, channel: Channel) -> ForumPostContextMenuBridge {
        ForumPostContextMenuBridge(
            actionsMenu: ThreadActionsMenu(
                model: model,
                thread: post.thread,
                surface: .forumCard,
                isUnread: model.isForumPostUnread(post),
                offersTags: true
            ),
            tags: channel.availableTags,
            appliedTagIDs: post.thread.appliedTagIDs,
            customEmojiURLsByID: model.customEmojiURLsByID,
            requiresTag: channel.requiresForumTag,
            canManage: model.threadActionPolicy(post.thread).canManage,
            toggleTag: { [weak model] tagID in
                guard let model else { return }
                ForumBoardView.toggleTag(tagID, on: post, in: channel, model: model)
            }
        )
    }

    static func toggleTag(_ tagID: ForumTagID, on post: ForumPost, in channel: Channel, model: AppModel) {
        guard let tag = channel.availableTags.first(where: { $0.id == tagID }),
              model.canToggleForumTag(tag, on: post)
        else { return }
        var tags = Set(post.thread.appliedTagIDs)
        if tags.contains(tagID) {
            tags.remove(tagID)
        } else if tags.count < 5 {
            tags.insert(tagID)
        }
        Task { await model.updateForumPost(post, mutation: .tags(Array(tags))) }
    }

    // MARK: Tooltips

    private func rebuildToolTips() {
        removeAllToolTips()
        for (id, _) in cards {
            guard case .post = id, let entry = layoutState?.entry(for: id),
                  let frame = cardRegions(for: id)?.timestampFrame
            else { continue }
            addToolTip(frame.offsetBy(dx: entry.frame.minX, dy: entry.frame.minY), owner: self, userData: nil)
        }
    }

    func view(_: NSView, stringForToolTip _: NSView.ToolTipTag, point: NSPoint, userData _: UnsafeMutableRawPointer?) -> String {
        guard let hit = hit(at: point), let postID = hit.entry.item.postID, let presentation = presentations[postID] else { return "" }
        return "Last activity \(presentation.lastActivityAt.formatted(date: .complete, time: .shortened))"
    }

    // MARK: Accessibility

    /// Mirrors realized posts as invisible proxy views, so VoiceOver can find,
    /// read and activate cards that are only painted into layers.
    private func updateAccessibilityChildren() {
        guard let layoutState else { return }
        var live: [ChannelID: ForumBoardAccessibilityProxyView] = [:]
        for entry in layoutState.entries(intersecting: realizationRect) {
            guard let postID = entry.item.postID, let presentation = presentations[postID] else { continue }
            let proxy = accessibilityProxies.removeValue(forKey: postID) ?? {
                let proxy = ForumBoardAccessibilityProxyView(
                    press: { [weak self] in self?.accessibilityOpen(postID) ?? false },
                    showMenu: { [weak self] in self?.accessibilityShowMenu(postID) ?? false }
                )
                addSubview(proxy)
                return proxy
            }()
            proxy.frame = entry.frame
            proxy.update(
                presentation: presentation,
                excerpt: excerptRenderers[postID]?.accessibilityText,
                toggleReaction: { [weak self] in self?.accessibilityToggleReaction(postID) ?? false }
            )
            live[postID] = proxy
        }
        for proxy in accessibilityProxies.values { proxy.removeFromSuperview() }
        accessibilityProxies = live
    }

    fileprivate func accessibilityOpen(_ postID: ChannelID) -> Bool {
        guard let post = postsByID[postID] else { return false }
        model?.open(post)
        return true
    }

    fileprivate func accessibilityToggleReaction(_ postID: ChannelID) -> Bool {
        guard let model, let summary = presentations[postID]?.reaction, !summary.isDisabled else { return false }
        Task { await model.toggleReaction(summary.reaction.emoji, on: summary.message) }
        return true
    }

    fileprivate func accessibilityShowMenu(_ postID: ChannelID) -> Bool {
        guard let model, let channel, let post = postsByID[postID], let entry = layoutState?.entry(for: .post(postID)) else { return false }
        let menu = contextMenu(for: post, model: model, channel: channel)
        menu.popUp(positioning: nil, at: CGPoint(x: entry.frame.minX + 20, y: entry.frame.minY + 20), in: self)
        return true
    }

    // MARK: Stability probe

    /// Reports realized cards' on-screen sizes to the DEBUG layout-stability
    /// probe, which counts any card that resizes after first appearing.
    private func reportStability() {
        #if DEBUG
        guard let width = layoutState?.width else { return }
        for (id, card) in cards {
            guard case let .post(postID) = id else { continue }
            ForumLayoutStabilityProbe.shared.record(postID: postID, size: card.frame.size, containerWidth: width)
        }
        #endif
    }
}

enum ForumBoardTransition: Equatable {
    /// Width, scale or first population: no motion.
    case none
    /// Loaded or re-queried content arriving: a short staggered entrance.
    case reveal
    /// List and gallery swap: the board cross-fades.
    case morph
    /// Live inserts, removals and reorders.
    case reflow
}

private extension ForumCardRegions {
    func withoutSkeleton() -> Self {
        var value = self
        value.skeletonFrames = []
        return value
    }
}

/// One post as VoiceOver sees it: a button with its unread state, excerpt,
/// counts and actions, laid over the painted card. It never takes clicks.
final class ForumBoardAccessibilityProxyView: NSView {
    nonisolated let press: @MainActor @Sendable () -> Bool
    nonisolated let showMenu: @MainActor @Sendable () -> Bool

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(press: @escaping @MainActor @Sendable () -> Bool, showMenu: @escaping @MainActor @Sendable () -> Bool) {
        self.press = press
        self.showMenu = showMenu
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Opens this post as a thread")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func isAccessibilityElement() -> Bool { true }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func draw(_: NSRect) {}

    func update(
        presentation: ForumCardPresentation,
        excerpt: String?,
        toggleReaction: @escaping @MainActor () -> Bool
    ) {
        setAccessibilityLabel(presentation.accessibilityLabel)
        var value = [presentation.isEmphasized ? "Unread" : "Read"]
        if let excerpt, !excerpt.isEmpty { value.append(excerpt) }
        value.append(presentation.messageCountAccessibilityText)
        value.append("Last activity \(presentation.lastActivityAt.formatted(date: .abbreviated, time: .shortened))")
        setAccessibilityValue(value.joined(separator: ", "))
        setAccessibilitySelected(presentation.isSelected)
        var actions: [NSAccessibilityCustomAction] = []
        if let reaction = presentation.reaction, !reaction.isDisabled {
            let verb = reaction.reaction.didCurrentUserReact ? "Remove" : "Add"
            actions.append(NSAccessibilityCustomAction(name: "\(verb) Reaction \(reaction.reaction.emojiReference.name)") {
                toggleReaction()
            })
        }
        setAccessibilityCustomActions(actions)
    }

    nonisolated override func accessibilityPerformPress() -> Bool {
        let action = press
        return MainActor.assumeIsolated { action() }
    }

    nonisolated override func accessibilityPerformShowMenu() -> Bool {
        let action = showMenu
        return MainActor.assumeIsolated { action() }
    }
}
