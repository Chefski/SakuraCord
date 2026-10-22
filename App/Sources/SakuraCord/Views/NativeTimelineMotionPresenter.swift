import AppKit
import OSLog
import QuartzCore

/// Shows the timeline's visible rows while a live window resize changes its
/// width, re-wrapped for the width of every frame.
///
/// Each visible row is its own layer. Rows are laid out on the main thread
/// for the frame's width; their bitmaps are painted off the main thread, one
/// row at a time, by `NativeTimelineRowRasterizer`, from a snapshot of what
/// they read, ahead along the drag's direction. The rows show only at the
/// exact width they were painted for: while a visible row's bitmap is late,
/// the canvas re-wraps its visible rows for that frame instead, as it does
/// during workspace motions, and the frame counts as late (`Stats`).
///
/// Re-wrapping the canvas on the main thread for every frame of a drag cost
/// more than the drag's frames allowed. When the resize ends, the bitmaps
/// for the final width seed the canvas's row cache and the canvas takes
/// over. Workspace motions (the member list, search results) re-wrap the
/// canvas's visible rows instead, as the timeline always has: their hand-over
/// cost more than it saved.
@MainActor
final class NativeTimelineMotionPresenter {
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
        /// Frames the canvas showed because a visible row's bitmap for the
        /// frame's width was late.
        var lateFrames = 0
        var maximumPresentMS = 0.0
        var totalPresentMS = 0.0
        var workerPaints = 0
        var workerMS = 0.0
        var maximumWorkerMS = 0.0
        var reusedConversions = 0
        var activationMS = 0.0
        var firstFrameIsLate = false
        /// The presented frame by which the first worker bitmap arrived.
        var firstWorkerBitmapFrame: Int?
    }

    static let isEnabled = !ProcessInfo.processInfo.arguments.contains("--timeline-canvas-motion")
    private static let log = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "TimelineMotionPresenter")
    /// Main-thread time per call for laying out rows at coming widths: more
    /// as the resize starts.
    private static let layoutBudgetMS = 3.0
    private static let startLayoutBudgetMS = 10.0

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
    private(set) var isActive = false
    private var isShowing = false
    private var lastWidths: [CGFloat] = []
    private(set) var stats = Stats()
    /// Where the resize's width is going.
    private var targetWidth: CGFloat = 0
    /// The rows last shown, for asking the worker for coming frames.
    private var lastVisible: [Int] = []
    /// The width the visible rows were last presented at; nil while the
    /// canvas shows them.
    private(set) var presentedWidth: CGFloat?

    init(coordinator: NativeMessageTimelineCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: Session

    /// Starts presenting rows as a live resize begins. Rows stay on the
    /// canvas until the width first changes.
    /// - Returns: Whether the timeline can be presented this way; if not,
    ///   the canvas re-wraps as before.
    @discardableResult
    func begin() -> Bool {
        guard Self.isEnabled else { return false }
        guard !isActive else { return true }
        let activationStart = ProcessInfo.processInfo.systemUptime
        defer { stats.activationMS = (ProcessInfo.processInfo.systemUptime - activationStart) * 1_000 }
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
        isActive = true
        scale = window.backingScaleFactor
        displayColorSpace = canvas.backingColorSpace
            ?? window.colorSpace?.cgColorSpace
            ?? window.screen?.colorSpace?.cgColorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        appearance = canvas.effectiveAppearance
        metrics = NativeTimelineRowLayout.Metrics(settings: coordinator.parent.model.interfaceSettings)
        stats = Stats()
        lastWidths = []

        let items = coordinator.items
        rowRange = max(0, visible.lowerBound - 6) ..< min(items.count, visible.upperBound + 6)
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
        overlay.translatesAutoresizingMaskIntoConstraints = false
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
        lastVisible = Array(visible)
        Self.log.notice("Motion presenter began rows=\(self.rowRange.count) width=\(Double(width))")
        // Paint the coming frames before the first of them.
        requestBitmaps(currentWidth: width, visible: Array(visible), layoutBudgetMS: Self.startLayoutBudgetMS)
        return true
    }

    /// Presents the rows at `width` for the frame being built.
    /// - Returns: Whether the rows are presented; if not, the canvas
    ///   handles the width as before.
    func present(width: CGFloat) -> Bool {
        guard isActive, let canvas, let scrollView, let overlay else { return false }
        let start = ProcessInfo.processInfo.systemUptime
        collectFinished()
        let pixelWidth = Self.pixelWidth(width, scale: scale)
        overlay.frame = scrollView.contentView.frame
        let viewportHeight = overlay.bounds.height
        guard let placed = placeRows(width: width, pixelWidth: pixelWidth, viewportHeight: viewportHeight),
              placed.allSatisfy({ fitsBitmapBudget($0.layout, width: width) })
        else {
            // The viewport grew past the rows taken at the start, or a row
            // grew past what a bitmap may take.
            end()
            return false
        }
        let visible = placed.filter { $0.minY + $0.layout.height > 0 && $0.minY < viewportHeight }

        // Every visible row needs its bitmap for this width; until then the
        // canvas re-wraps the rows for this frame.
        let bitmaps = visible.reduce(into: [Int: NativeTimelineRowRasterizer.Bitmap]()) { bitmaps, row in
            bitmaps[row.index] = rows[row.index]?.bitmaps[pixelWidth]
        }
        let isLate = bitmaps.count < visible.count
        if isLate {
            showCanvas(canvas, overlay: overlay)
        } else {
            showRows(visible, bitmaps: bitmaps, width: width, viewportHeight: viewportHeight, overlay: overlay, canvas: canvas)
        }
        record(width: width, isLate: isLate)
        lastVisible = visible.map(\.index)
        let upcoming = budgeted(upcomingWidths(after: width))
        requestBitmaps(currentWidth: width, visible: lastVisible, upcoming: upcoming)
        pruneBitmaps(keeping: pixelWidth, upcoming: upcoming)
        let presentMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        stats.totalPresentMS += presentMS
        stats.maximumPresentMS = max(stats.maximumPresentMS, presentMS)
        return !isLate
    }

    private struct PlacedRow {
        let index: Int
        /// From the viewport's top.
        let minY: CGFloat
        let layout: NativeTimelineRowLayout
    }

    /// Lays out the rows from the anchor outward, at this frame's width,
    /// until they cover the viewport.
    /// - Returns: Nil if the rows taken at the start leave part of the
    ///   viewport empty where the timeline has more.
    private func placeRows(width: CGFloat, pixelWidth: Int, viewportHeight: CGFloat) -> [PlacedRow]? {
        var placed: [PlacedRow] = []
        let itemCount = coordinator?.items.count ?? 0
        var covers = true
        func stackUp(from index: Int, bottom: CGFloat) {
            var maxY = bottom
            var index = index
            while index >= rowRange.lowerBound, maxY > 0,
                  let layout = layout(at: index, pixelWidth: pixelWidth, width: width)
            {
                placed.append(PlacedRow(index: index, minY: maxY - layout.height, layout: layout))
                maxY -= layout.height
                index -= 1
            }
            if maxY > 0, index >= 0, index < rowRange.lowerBound { covers = false }
        }
        func stackDown(from index: Int, top: CGFloat) {
            var minY = top
            var index = index
            while index < rowRange.upperBound, minY < viewportHeight,
                  let layout = layout(at: index, pixelWidth: pixelWidth, width: width)
            {
                placed.append(PlacedRow(index: index, minY: minY, layout: layout))
                minY += layout.height
                index += 1
            }
            if minY < viewportHeight, index < itemCount, index >= rowRange.upperBound { covers = false }
        }
        switch anchor {
        case let .bottom(anchorIndex, gap):
            stackUp(from: anchorIndex, bottom: viewportHeight - gap)
            stackDown(from: anchorIndex + 1, top: viewportHeight - gap)
        case let .top(anchorIndex, offset):
            stackDown(from: anchorIndex, top: offset)
            stackUp(from: anchorIndex - 1, bottom: offset)
        }
        return covers ? placed : nil
    }

    /// Moves the row layers to this frame, in one transaction, and hands
    /// the rows from the canvas to the layers the first time.
    private func showRows(
        _ visible: [PlacedRow], bitmaps: [Int: NativeTimelineRowRasterizer.Bitmap], width: CGFloat,
        viewportHeight: CGFloat, overlay: NativeTimelineMotionOverlayView, canvas: NativeTimelineCanvasView
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let placed = Dictionary(uniqueKeysWithValues: visible.map { ($0.index, $0) })
        for (index, row) in rows {
            guard let entry = placed[index], let bitmap = bitmaps[index] else {
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
        CATransaction.commit()
    }

    /// The canvas shows the rows again, mid-resize, for a frame whose
    /// bitmaps are late.
    private func showCanvas(_ canvas: NativeTimelineCanvasView, overlay: NativeTimelineMotionOverlayView) {
        guard isShowing else { return }
        isShowing = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.isHidden = true
        canvas.isHidden = false
        CATransaction.commit()
    }

    private func record(width: CGFloat, isLate: Bool) {
        if stats.frames == 0 { stats.firstFrameIsLate = isLate }
        presentedWidth = isLate ? nil : width
        stats.frames += 1
        if isLate { stats.lateFrames += 1 }
        lastWidths.append(width)
        if lastWidths.count > 3 { lastWidths.removeFirst() }
    }

    /// Puts the bitmaps for the width the rows settle at into the canvas's
    /// cache, so the canvas shows them without painting.
    func seedCanvas(width: CGFloat) {
        guard isActive, let canvas else { return }
        collectFinished()
        let pixelWidth = Self.pixelWidth(width, scale: scale)
        var seeded = 0
        for row in rows.values {
            guard let bitmap = row.bitmaps[pixelWidth], let deviceImage = bitmap.deviceImage,
                  canvas.cachedBitmap(for: row.item, width: width) == nil,
                  canvas.animatedReactionIDs(for: row.item.identifier).isEmpty
            else { continue }
            let image = NSImage(cgImage: deviceImage, size: NSSize(width: bitmap.width, height: bitmap.height))
            let mediaKeys = canvas.mediaKeys(for: row.item, at: row.index)
            canvas.storeBitmap(
                image, for: row.item, width: width, appearanceName: appearance.name,
                preparedMediaKeys: mediaKeys, scale: scale,
                missingMediaKeys: mediaKeys.filter { context?.mediaImage(for: $0) == nil }
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
            Motion presenter ended frames=\(self.stats.frames) \
            late=\(self.stats.lateFrames) presentMax=\(self.stats.maximumPresentMS) \
            presentAvg=\(self.stats.totalPresentMS / Double(max(1, self.stats.frames))) \
            workerPaints=\(self.stats.workerPaints) reused=\(self.stats.reusedConversions) activationMS=\(self.stats.activationMS) \
            firstFrameIsLate=\(self.stats.firstFrameIsLate) \
            workerAvg=\(self.stats.workerMS / Double(max(1, self.stats.workerPaints))) \
            workerMax=\(self.stats.maximumWorkerMS) workerLockWaitMS=\(paintLock.workerWaitMS) longestWorkerLockWaitMS=\(paintLock.longestWorkerWaitMS) \
            firstWorkerBitmapFrame=\(self.stats.firstWorkerBitmapFrame ?? -1) \
            mainLockWaits=\(paintLock.mainWaits) longMainLockWaits=\(paintLock.longMainWaits) \
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
        isActive = false
        isShowing = false
        presentedWidth = nil
    }

    var isWorkerIdle: Bool { rasterizer.isIdle }

    /// Calls `body` once the worker has no row in hand.
    func whenWorkerIdle(_ body: @escaping @MainActor @Sendable () -> Void) {
        rasterizer.whenIdle(body)
    }

    // MARK: Rows

    private func layout(at index: Int, pixelWidth: Int, width: CGFloat) -> NativeTimelineRowLayout? {
        guard let row = rows[index], let coordinator else { return nil }
        if let layout = row.layouts[pixelWidth] { return layout }
        let layout = coordinator.layout(for: row.item, width: width, metrics: metrics)
        rows[index]?.layouts[pixelWidth] = layout
        return layout
    }

    /// The layout the motion made for `item` at `width`, which the canvas
    /// reuses as it lays the rows out for the width they settle at.
    func preparedLayout(for item: NativeMessageTimelineItem, at index: Int, width: CGFloat) -> NativeTimelineRowLayout? {
        guard let row = rows[index], row.item == item else { return nil }
        return row.layouts[Self.pixelWidth(width, scale: scale)]
    }

    /// The exact bitmap, or the one painted for the nearest width.
    private func collectFinished() {
        for bitmap in rasterizer.takeFinished() {
            if stats.firstWorkerBitmapFrame == nil { stats.firstWorkerBitmapFrame = stats.frames }
            stats.workerPaints += 1
            if bitmap.reusedConversion { stats.reusedConversions += 1 }
            stats.workerMS += bitmap.milliseconds
            stats.maximumWorkerMS = max(stats.maximumWorkerMS, bitmap.milliseconds)
            guard let index = rows.first(where: { $0.value.item.identifier == bitmap.key.identifier })?.key else { continue }
            // Only the width the motion settles at seeds the canvas.
            let settles = bitmap.key.pixelWidth == Self.pixelWidth(targetWidth, scale: scale)
            rows[index]?.bitmaps[bitmap.key.pixelWidth] = settles ? bitmap : bitmap.droppingDeviceImage()
        }
    }

    /// The width the next frame will show, continuing the drag.
    private func upcomingWidths(after width: CGFloat) -> [CGFloat] {
        guard isActive, lastWidths.count >= 2 else { return [] }
        let step = lastWidths[lastWidths.count - 1] - lastWidths[lastWidths.count - 2]
        return step == 0 ? [] : [(width + step).rounded()]
    }

    /// Asks the worker for this frame's missing bitmaps, then the next
    /// frames', in that order.
    private func requestBitmaps(
        currentWidth: CGFloat, visible: [Int], upcoming: [CGFloat]? = nil,
        layoutBudgetMS: Double = NativeTimelineMotionPresenter.layoutBudgetMS
    ) {
        let deadline = ProcessInfo.processInfo.systemUptime + layoutBudgetMS / 1_000
        // This frame's width first, then where the drag is heading.
        var widths: [CGFloat] = []
        let upcoming = upcoming ?? budgeted(upcomingWidths(after: currentWidth))
        for width in upcoming where !widths.contains(width) {
            widths.append(width)
        }
        targetWidth = upcoming.last ?? currentWidth
        if !widths.contains(currentWidth) {
            widths.insert(currentWidth, at: 0)
        }
        // Rows re-wrapping shorter, as the timeline widens, bring rows beyond
        // the anchored edge's far side into view; those come after the
        // visible rows of every width.
        var beyond: [Int] = []
        if let first = visible.min(), let last = visible.max(), widths.contains(where: { $0 > currentWidth }) {
            switch anchor {
            case .bottom: beyond = [first - 1, first - 2].filter { rowRange.contains($0) }
            case .top: beyond = [last + 1, last + 2].filter { rowRange.contains($0) }
            }
        }
        var jobs: [NativeTimelineRowRasterizer.Job] = []
        for indexes in [visible, beyond] {
            for width in widths {
                let pixelWidth = Self.pixelWidth(width, scale: scale)
                for index in indexes {
                    // Rows already laid out at this width cost nothing; new
                    // layouts wait for a later frame once the budget is spent.
                    let laidOut = rows[index]?.layouts[pixelWidth] != nil
                    guard laidOut || ProcessInfo.processInfo.systemUptime < deadline else { continue }
                    if let job = job(for: index, width: width, pixelWidth: pixelWidth) { jobs.append(job) }
                }
            }
        }
        rasterizer.submit(jobs)
    }

    private func job(for index: Int, width: CGFloat, pixelWidth: Int) -> NativeTimelineRowRasterizer.Job? {
        guard let coordinator, let row = rows[index], row.bitmaps[pixelWidth] == nil,
              let layout = layout(at: index, pixelWidth: pixelWidth, width: width),
              fitsBitmapBudget(layout, width: width)
        else { return nil }
        return .init(
            key: .init(identifier: row.item.identifier, pixelWidth: pixelWidth),
            item: row.item, layout: layout, width: width, scale: scale,
            appearance: appearance, context: context, model: coordinator.parent.model,
            spoilerRevealStore: spoilerRevealStore,
            // The canvas's animated reactions hide with it: the rows show
            // their first frames, and are not seeded (`seedCanvas`).
            animatedReactionIDs: [],
            displayColorSpace: displayColorSpace
        )
    }

    /// Keeps each row's bitmaps for this width and the coming ones, and the
    /// nearest older one in case the next frame's is late.
    /// Painted rows for every coming width took hundreds of megabytes on
    /// long rows: only the nearest coming widths that fit the budget, for
    /// every row, are painted and kept.
    private static let bitmapBudgetBytes = 64 * 1_024 * 1_024

    private func budgeted(_ upcoming: [CGFloat]) -> [CGFloat] {
        let bytesPerWidth = rows.values.reduce(0) { total, row in
            total + (row.bitmaps.values.first.map { bitmap in
                Int(bitmap.width * scale) * Int(bitmap.height * scale) * 4 * (bitmap.deviceImage == nil ? 1 : 2)
            } ?? 0)
        }
        guard bytesPerWidth > 0 else { return upcoming }
        return Array(upcoming.prefix(max(2, Self.bitmapBudgetBytes / bytesPerWidth - 2)))
    }

    private func pruneBitmaps(keeping pixelWidth: Int, upcoming: [CGFloat]) {
        let upcoming = Set(upcoming.map { Self.pixelWidth($0, scale: scale) })
        for index in Array(rows.keys) {
            guard let row = rows[index], row.bitmaps.count > 4 else { continue }
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
        // Shown by views over the canvas, which hide with it; the rows'
        // bitmaps leave their place empty.
        if !canvas.lottieStickerOverlays.isEmpty { return "Lottie sticker" }
        if canvas.voiceMessageOverlay != nil { return "voice message player" }
        let items = coordinator.items
        let range = max(0, visible.lowerBound - 6) ..< min(items.count, visible.upperBound + 6)
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

    /// The worker paints whole rows, where the canvas paints a tall row's
    /// visible tiles; a bitmap per width would take gigabytes. A row past
    /// this is not painted, and hands the rows back once it shows.
    private func fitsBitmapBudget(_ layout: NativeTimelineRowLayout, width: CGFloat) -> Bool {
        NativeTimelineCanvasView.estimatedBitmapCost(width: width, height: layout.height, scale: scale) <= 24 * 1_024 * 1_024
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
