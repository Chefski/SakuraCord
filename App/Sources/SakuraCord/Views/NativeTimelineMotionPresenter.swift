import AppKit
import OSLog
import QuartzCore

/// Shows the timeline's visible rows while a workspace motion or a live
/// window resize changes its width, re-wrapped for the exact width of every
/// frame, in the frame the column edge moves.
///
/// Each visible row is its own layer. Rows are laid out on the main thread
/// for the frame's width; their bitmaps are painted off the main thread, one
/// row at a time, by `NativeTimelineRowRasterizer`, from a snapshot of what
/// they read. During a workspace motion the worker paints ahead along the
/// columns' spring (`WorkspaceConversationWidthPath`), so a frame's bitmaps
/// are usually ready before it. A row whose exact bitmap is late shows the
/// nearest painted width for that frame and counts as inexact.
///
/// Replaces re-wrapping the canvas on the main thread every few frames,
/// which held each frame's main thread for 30–70 ms on #general and let the
/// text trail the column edge. When the motion settles, the bitmaps for the
/// final width seed the canvas's row cache and the canvas takes over.
@MainActor
final class NativeTimelineMotionPresenter {
    enum Reason: String {
        case workspaceMotion
        case liveResize
    }

    private struct Row {
        let index: Int
        let item: NativeMessageTimelineItem
        let layer: CALayer
        var layouts: [Int: NativeTimelineRowLayout] = [:]
        var bitmaps: [Int: NativeTimelineRowRasterizer.Bitmap] = [:]
    }

    private enum Anchor {
        /// The row whose bottom keeps its distance from the viewport's bottom.
        case bottom(index: Int, gap: CGFloat)
        /// The row whose top keeps its distance from the viewport's top.
        case top(index: Int, offset: CGFloat)
    }

    /// One motion's sync and cost, for the benchmark and the log.
    struct Stats {
        var frames = 0
        /// Frames in which a visible row showed a bitmap painted for
        /// another width, and the largest such difference.
        var inexactFrames = 0
        var maximumLagPoints: CGFloat = 0
        /// Frames in which a visible row had no bitmap at all.
        var missingFrames = 0
        var maximumPresentMS = 0.0
        var totalPresentMS = 0.0
        var workerPaints = 0
        var workerMS = 0.0
        var maximumWorkerMS = 0.0
        var reusedConversions = 0
        /// The presented frame by which the first worker bitmap arrived.
        var firstWorkerBitmapFrame: Int?
    }

    static let isEnabled = !ProcessInfo.processInfo.arguments.contains("--timeline-canvas-motion")
    private static let log = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "TimelineMotionPresenter")
    /// Frames painted ahead of the one on screen during a workspace motion.
    private static let framesAhead = 3

    private weak var coordinator: NativeMessageTimelineCoordinator?
    private weak var canvas: NativeTimelineCanvasView?
    private weak var scrollView: NSScrollView?
    private let rasterizer = NativeTimelineRowRasterizer()
    private var overlay: NativeTimelineMotionOverlayView?
    private var rows: [Int: Row] = [:]
    private var rowRange: Range<Int> = 0 ..< 0
    private var anchor: Anchor = .top(index: 0, offset: 0)
    private var context: NativeTimelineRowPaintContext?
    private var spoilerRevealStore = NativeTimelineSpoilerRevealStore()
    private var appearance = NSAppearance(named: .aqua)!
    private var scale: CGFloat = 2
    private var displayColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var metrics: NativeTimelineRowLayout.Metrics?
    private var reason: Reason?
    private var isShowing = false
    private var lastWidths: [CGFloat] = []
    private(set) var stats = Stats()
    private var pathObservation: NSObjectProtocol?
    /// The rows last shown, for asking the worker for coming frames.
    private var lastVisible: [Int] = []
    /// The width the visible rows were last presented at, and how far the
    /// furthest visible row's bitmap was from it.
    private(set) var presentedWidth: CGFloat?
    private(set) var presentedLagPoints: CGFloat = 0

    var isActive: Bool { reason != nil }

    init(coordinator: NativeMessageTimelineCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: Session

    /// Starts presenting rows for a motion. Rows stay on the canvas until
    /// the width first changes.
    /// - Returns: Whether the timeline can be presented this way now; if
    ///   not, the canvas re-wraps as before.
    @discardableResult
    func begin(_ reason: Reason) -> Bool {
        guard Self.isEnabled else { return false }
        if self.reason != nil {
            if reason == .workspaceMotion { self.reason = reason }
            return true
        }
        guard let coordinator, let canvas = coordinator.canvas, let scrollView = coordinator.scrollView,
              let window = canvas.window, coordinator.layoutWidth > 0,
              let visible = coordinator.visibleItemRangeForWidthRelayout()
        else { return false }
        if let declined = declineReason(canvas: canvas, coordinator: coordinator, visible: visible) {
            Self.log.notice("Motion presenter declined: \(declined, privacy: .public)")
            return false
        }
        self.canvas = canvas
        self.scrollView = scrollView
        self.reason = reason
        scale = window.backingScaleFactor
        displayColorSpace = window.colorSpace?.cgColorSpace
            ?? window.screen?.colorSpace?.cgColorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        appearance = canvas.effectiveAppearance
        metrics = NativeTimelineRowLayout.Metrics(settings: coordinator.parent.model.interfaceSettings)
        stats = Stats()
        lastWidths = []

        let items = coordinator.items
        rowRange = max(0, visible.lowerBound - 12) ..< min(items.count, visible.upperBound + 12)
        let nearBottom = coordinator.lastReportedState?.isNearBottom ?? coordinator.scrollState().isNearBottom
        let viewport = scrollView.contentView.bounds
        if nearBottom {
            let last = visible.upperBound - 1
            let frame = canvas.convert(canvas.rowFrame(at: last), to: scrollView.contentView)
            anchor = .bottom(index: last, gap: viewport.maxY - frame.maxY)
        } else {
            let first = visible.lowerBound
            let frame = canvas.convert(canvas.rowFrame(at: first), to: scrollView.contentView)
            anchor = .top(index: first, offset: frame.minY - viewport.minY)
        }

        var mediaImages: [NativeTimelineMediaKey: NSImage] = [:]
        for index in rowRange {
            for key in canvas.mediaKeys(for: items[index], at: index) {
                if let image = NativeTimelineMediaStore.shared.firstAnimatedFrame(for: key)
                    ?? NativeTimelineMediaStore.shared.image(for: key)
                {
                    mediaImages[key] = image
                }
            }
        }
        context = NativeTimelineRowPaintContext(
            model: coordinator.parent.model, items: items[rowRange], mediaImages: mediaImages
        )
        // A reveal while the rows move shows once they settle.
        spoilerRevealStore = NativeTimelineSpoilerRevealStore()
        spoilerRevealStore.revealedMedia = canvas.spoilerRevealStore.revealedMedia
        spoilerRevealStore.revealedText = canvas.spoilerRevealStore.revealedText

        let overlay = NativeTimelineMotionOverlayView(frame: scrollView.contentView.frame)
        overlay.isHidden = true
        scrollView.addSubview(overlay, positioned: .above, relativeTo: scrollView.contentView)
        self.overlay = overlay
        rows = [:]
        let width = coordinator.layoutWidth
        let pixelWidth = Self.pixelWidth(width, scale: scale)
        for index in rowRange {
            let layer = CALayer()
            layer.contentsGravity = .topLeft
            layer.contentsScale = scale
            layer.masksToBounds = true
            layer.isHidden = true
            overlay.rowsLayer.addSublayer(layer)
            var row = Row(index: index, item: items[index], layer: layer)
            row.layouts[pixelWidth] = coordinator.layouts[index]
            rows[index] = row
        }
        pathObservation = NotificationCenter.default.addObserver(
            forName: WorkspaceConversationWidthPath.didStartMoving, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive, let width = self.presentedWidth ?? self.coordinator?.layoutWidth else { return }
                self.requestBitmaps(currentWidth: width, visible: self.lastVisible)
            }
        }
        lastVisible = Array(visible)
        Self.log.notice("Motion presenter began (\(reason.rawValue, privacy: .public)) rows=\(self.rowRange.count) width=\(Double(width))")
        // Paint the coming frames before the first of them.
        requestBitmaps(currentWidth: width, visible: Array(visible))
        return true
    }

    /// Presents the rows at `width` for the frame being built.
    /// - Returns: Whether the rows are presented; if not, the canvas
    ///   handles the width as before.
    func present(width: CGFloat) -> Bool {
        guard isActive, let coordinator, let canvas, let scrollView, let overlay else { return false }
        let start = ProcessInfo.processInfo.systemUptime
        collectFinished()
        let pixelWidth = Self.pixelWidth(width, scale: scale)
        overlay.frame = scrollView.contentView.frame
        let viewportHeight = overlay.bounds.height

        // Lay out the rows from the anchor outward until they cover the
        // viewport, at this frame's width.
        var placed: [(index: Int, minY: CGFloat, layout: NativeTimelineRowLayout)] = []
        switch anchor {
        case let .bottom(anchorIndex, gap):
            var maxY = viewportHeight - gap
            var index = anchorIndex
            while index >= rowRange.lowerBound, maxY > 0 {
                guard let layout = layout(at: index, pixelWidth: pixelWidth, width: width) else { break }
                placed.append((index, maxY - layout.height, layout))
                maxY -= layout.height
                index -= 1
            }
            var minY = viewportHeight - gap
            index = anchorIndex + 1
            while index < rowRange.upperBound, minY < viewportHeight {
                guard let layout = layout(at: index, pixelWidth: pixelWidth, width: width) else { break }
                placed.append((index, minY, layout))
                minY += layout.height
                index += 1
            }
        case let .top(anchorIndex, offset):
            var minY = offset
            var index = anchorIndex
            while index < rowRange.upperBound, minY < viewportHeight {
                guard let layout = layout(at: index, pixelWidth: pixelWidth, width: width) else { break }
                placed.append((index, minY, layout))
                minY += layout.height
                index += 1
            }
            var maxY = offset
            index = anchorIndex - 1
            while index >= rowRange.lowerBound, maxY > 0 {
                guard let layout = layout(at: index, pixelWidth: pixelWidth, width: width) else { break }
                placed.append((index, maxY - layout.height, layout))
                maxY -= layout.height
                index -= 1
            }
        }
        let visible = placed.filter { $0.minY + $0.layout.height > 0 && $0.minY < viewportHeight }

        // Every visible row needs a bitmap to show; until then the canvas
        // keeps showing them.
        var lag: CGFloat = 0
        var missing = false
        var choices: [Int: NativeTimelineRowRasterizer.Bitmap] = [:]
        for entry in visible {
            guard let bitmap = bestBitmap(for: entry.index, pixelWidth: pixelWidth) else {
                missing = true
                continue
            }
            choices[entry.index] = bitmap
            lag = max(lag, abs(bitmap.width - width))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !missing {
            let shown = Set(visible.map(\.index))
            for (index, row) in rows {
                guard shown.contains(index), let entry = visible.first(where: { $0.index == index }),
                      let bitmap = choices[index]
                else {
                    row.layer.isHidden = true
                    continue
                }
                // The overlay's root layer is not flipped.
                row.layer.frame = CGRect(
                    x: 0, y: viewportHeight - entry.minY - entry.layout.height,
                    width: width, height: entry.layout.height
                )
                if row.layer.contents as AnyObject? !== bitmap.image { row.layer.contents = bitmap.image }
                row.layer.isHidden = false
            }
            if !isShowing {
                isShowing = true
                overlay.isHidden = false
                canvas.isHidden = true
            }
        }
        CATransaction.commit()

        presentedWidth = missing ? nil : width
        presentedLagPoints = missing ? .infinity : lag
        stats.frames += 1
        if missing { stats.missingFrames += 1 }
        if lag >= 0.5 { stats.inexactFrames += 1 }
        stats.maximumLagPoints = max(stats.maximumLagPoints, missing ? 0 : lag)
        lastWidths.append(width)
        if lastWidths.count > 3 { lastWidths.removeFirst() }
        lastVisible = visible.map(\.index)
        requestBitmaps(currentWidth: width, visible: lastVisible)
        pruneBitmaps(keeping: pixelWidth)
        let presentMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        stats.totalPresentMS += presentMS
        stats.maximumPresentMS = max(stats.maximumPresentMS, presentMS)
        _ = coordinator
        return true
    }

    /// Puts the bitmaps for the width the rows settle at into the canvas's
    /// cache, so the canvas shows them without painting.
    func seedCanvas(width: CGFloat) {
        guard isActive, let canvas else { return }
        collectFinished()
        let pixelWidth = Self.pixelWidth(width, scale: scale)
        var seeded = 0
        for row in rows.values {
            guard let bitmap = row.bitmaps[pixelWidth], canvas.cachedBitmap(for: row.item, width: width) == nil
            else { continue }
            let image = NSImage(cgImage: bitmap.deviceImage, size: NSSize(width: bitmap.width, height: bitmap.height))
            canvas.storeBitmap(
                image, for: row.item, width: width, appearanceName: appearance.name,
                preparedMediaKeys: canvas.mediaKeys(for: row.item, at: row.index), scale: scale
            )
            seeded += 1
        }
        Self.log.notice("Motion presenter seeded \(seeded) row bitmaps at width \(Double(width))")
    }

    /// Hands the rows back to the canvas, in the same frame.
    func end() {
        guard isActive else { return }
        rasterizer.reset()
        let paintLock = NativeTimelinePaintLock.currentStats
        Self.log.notice(
            """
            Motion presenter ended (\(self.reason?.rawValue ?? "", privacy: .public)) frames=\(self.stats.frames) \
            inexact=\(self.stats.inexactFrames) missing=\(self.stats.missingFrames) \
            maxLagPt=\(Double(self.stats.maximumLagPoints)) presentMax=\(self.stats.maximumPresentMS) \
            presentAvg=\(self.stats.totalPresentMS / Double(max(1, self.stats.frames))) \
            workerPaints=\(self.stats.workerPaints) reused=\(self.stats.reusedConversions) workerAvg=\(self.stats.workerMS / Double(max(1, self.stats.workerPaints))) \
            workerMax=\(self.stats.maximumWorkerMS) workerLockWaitMS=\(paintLock.workerWaitMS) longestWorkerLockWaitMS=\(paintLock.longestWorkerWaitMS) \
            exactFrames=\(self.stats.frames - self.stats.inexactFrames - self.stats.missingFrames) firstWorkerBitmapFrame=\(self.stats.firstWorkerBitmapFrame ?? -1) mainLockWaits=\(paintLock.mainWaits) longMainLockWaits=\(paintLock.longMainWaits) \
            longestMainLockWaitMS=\(paintLock.longestMainWaitMS)
            """
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas?.isHidden = false
        overlay?.removeFromSuperview()
        CATransaction.commit()
        overlay = nil
        rows = [:]
        context = nil
        if let pathObservation { NotificationCenter.default.removeObserver(pathObservation) }
        pathObservation = nil
        reason = nil
        isShowing = false
        presentedWidth = nil
        presentedLagPoints = 0
    }

    var isWorkerIdle: Bool { rasterizer.isIdle }

    /// Calls `body` once the worker has no row in hand.
    func whenWorkerIdle(_ body: @escaping @MainActor @Sendable () -> Void) {
        rasterizer.whenIdle(body)
    }

    // MARK: Rows

    private func layout(at index: Int, pixelWidth: Int, width: CGFloat) -> NativeTimelineRowLayout? {
        guard var row = rows[index], let coordinator else { return nil }
        if let layout = row.layouts[pixelWidth] { return layout }
        let layout = coordinator.layout(for: row.item, width: width, metrics: metrics)
        row.layouts[pixelWidth] = layout
        rows[index] = row
        return layout
    }

    /// The exact bitmap, or the one painted for the nearest width.
    private func bestBitmap(for index: Int, pixelWidth: Int) -> NativeTimelineRowRasterizer.Bitmap? {
        guard let row = rows[index] else { return nil }
        if let exact = row.bitmaps[pixelWidth] { return exact }
        return row.bitmaps.min { abs($0.key - pixelWidth) < abs($1.key - pixelWidth) }?.value
    }

    private func collectFinished() {
        for bitmap in rasterizer.takeFinished() {
            if stats.firstWorkerBitmapFrame == nil { stats.firstWorkerBitmapFrame = stats.frames }
            stats.workerPaints += 1
            if bitmap.reusedConversion { stats.reusedConversions += 1 }
            stats.workerMS += bitmap.milliseconds
            stats.maximumWorkerMS = max(stats.maximumWorkerMS, bitmap.milliseconds)
            guard let index = rows.first(where: { $0.value.item.identifier == bitmap.key.identifier })?.key else { continue }
            rows[index]?.bitmaps[bitmap.key.pixelWidth] = bitmap
        }
    }

    /// The widths the next frames will show: along the columns' spring in
    /// a workspace motion, or continuing the drag in a live resize.
    private func upcomingWidths(after width: CGFloat) -> [CGFloat] {
        guard let scrollView else { return [] }
        switch reason {
        case .workspaceMotion?:
            let path = WorkspaceConversationWidthPath.shared
            guard let columnNow = path.width(of: scrollView, framesAhead: 0) else { return [] }
            // The timeline's width differs from its column's by fixed chrome.
            let offset = columnNow - scrollView.contentView.bounds.width
            return (1 ... Self.framesAhead).compactMap { frames in
                path.width(of: scrollView, framesAhead: frames).map { ($0 - offset).rounded() }
            }
        case .liveResize?:
            guard lastWidths.count >= 2 else { return [] }
            let step = lastWidths[lastWidths.count - 1] - lastWidths[lastWidths.count - 2]
            return step == 0 ? [] : [(width + step).rounded()]
        case nil:
            return []
        }
    }

    /// Asks the worker for this frame's missing bitmaps, then the next
    /// frames', in that order.
    private func requestBitmaps(currentWidth: CGFloat, visible: [Int]) {
        guard let coordinator else { return }
        var jobs: [NativeTimelineRowRasterizer.Job] = []
        // The frame being built is already on its way: in a workspace motion
        // the worker paints the next frames' widths, then this one in case
        // the motion holds still. A live resize has no path to follow.
        var widths: [CGFloat] = []
        for width in upcomingWidths(after: currentWidth) where !widths.contains(width) {
            widths.append(width)
        }
        if !widths.contains(currentWidth) {
            if reason == .liveResize { widths.insert(currentWidth, at: 0) } else { widths.append(currentWidth) }
        }
        // Rows re-wrapping shorter bring the ones beyond the edges into view.
        var candidates = visible
        if let first = visible.min(), let last = visible.max() {
            candidates += [first - 2, first - 1, last + 1, last + 2].filter { rowRange.contains($0) }
        }
        for width in widths {
            let pixelWidth = Self.pixelWidth(width, scale: scale)
            for index in candidates {
                guard let row = rows[index], row.bitmaps[pixelWidth] == nil,
                      let layout = layout(at: index, pixelWidth: pixelWidth, width: width)
                else { continue }
                jobs.append(.init(
                    key: .init(identifier: row.item.identifier, pixelWidth: pixelWidth),
                    item: row.item, layout: layout, width: width, scale: scale,
                    appearance: appearance, context: context, model: coordinator.parent.model,
                    spoilerRevealStore: spoilerRevealStore,
                    animatedReactionIDs: canvas?.animatedReactionIDs(for: row.item.identifier) ?? [],
                    displayColorSpace: displayColorSpace
                ))
            }
        }
        rasterizer.submit(jobs)
    }

    /// Keeps each row's bitmaps for this width and the coming ones, and the
    /// nearest older one in case the next frame's is late.
    private func pruneBitmaps(keeping pixelWidth: Int) {
        let upcoming = Set(upcomingWidths(after: CGFloat(pixelWidth) / scale).map { Self.pixelWidth($0, scale: scale) })
        for (index, row) in rows where row.bitmaps.count > 4 {
            let nearest = row.bitmaps.keys.min { abs($0 - pixelWidth) < abs($1 - pixelWidth) }
            rows[index]?.bitmaps = row.bitmaps.filter { key, _ in
                key == pixelWidth || key == nearest || upcoming.contains(key)
            }
            rows[index]?.layouts = row.layouts.filter { key, _ in
                abs(key - pixelWidth) <= Int(scale * 64) || upcoming.contains(key)
            }
        }
    }

    private func declineReason(
        canvas: NativeTimelineCanvasView,
        coordinator: NativeMessageTimelineCoordinator,
        visible: Range<Int>
    ) -> String? {
        if canvas.editingMessageID != nil { return "editing" }
        if !canvas.sendTransitions.isEmpty { return "send transition" }
        if canvas.transcriptGlide != nil { return "glide" }
        if canvas.messageJumpHighlight != nil { return "jump highlight" }
        if !canvas.disclosureRange.isEmpty { return "disclosure" }
        if canvas.historySkeleton != nil { return "history skeleton" }
        let items = coordinator.items
        let range = max(0, visible.lowerBound - 12) ..< min(items.count, visible.upperBound + 12)
        for index in range {
            switch items[index] {
            case .inboxGroup, .inboxEvent, .inboxForumPost: return "inbox rows"
            case .suppressedMessages: return "suppressed messages"
            case .message where coordinator.layouts[index].pollLayout != nil: return "poll"
            default: continue
            }
        }
        return nil
    }

    private static func pixelWidth(_ width: CGFloat, scale: CGFloat) -> Int {
        Int((width * scale).rounded())
    }
}

/// Holds the motion presenter's row layers above the timeline's clip view.
final class NativeTimelineMotionOverlayView: NSView {
    let rowsLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-hosting: the rows are layers this view never draws.
        layer = rowsLayer
        wantsLayer = true
        rowsLayer.isGeometryFlipped = false
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }
}
