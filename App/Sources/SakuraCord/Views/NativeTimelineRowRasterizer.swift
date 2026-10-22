import AppKit
import CoreText
import OSLog
import Synchronization

/// Serializes heavy row painting across threads.
///
/// Core Graphics bleeds colour between bitmap contexts that two threads
/// paint at once: with timeline rows painted on two threads together,
/// a few antialiased pixels in one row took another row's colours (measured
/// with a pixel-exact stress harness; one thread at a time never did). Every
/// painter of timeline and member rows paints under this lock, so the raster
/// worker never overlaps the main thread's painting.
nonisolated enum NativeTimelinePaintLock {
    struct Stats: Sendable {
        /// Times the main thread found the lock held.
        var mainWaits = 0
        /// Of those, waits of a millisecond or more.
        var longMainWaits = 0
        var longestMainWaitMS = 0.0
        /// Time other threads spent waiting for the lock.
        var workerWaitMS = 0.0
        var longestWorkerWaitMS = 0.0
    }

    private static let lock = NSRecursiveLock()
    private static let stats = Mutex(Stats())
    private static let log = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "TimelinePaintLock")

    static var currentStats: Stats {
        stats.withLock { $0 }
    }

    static func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        if !lock.try() {
            if Thread.isMainThread {
                let start = ProcessInfo.processInfo.systemUptime
                lock.lock()
                let waitedMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                stats.withLock {
                    $0.mainWaits += 1
                    if waitedMS >= 1 { $0.longMainWaits += 1 }
                    $0.longestMainWaitMS = max($0.longestMainWaitMS, waitedMS)
                }
                if waitedMS >= 1 {
                    log.notice("Main waited \(waitedMS, format: .fixed(precision: 2)) ms for the timeline paint lock")
                }
            } else {
                let start = ProcessInfo.processInfo.systemUptime
                lock.lock()
                let waitedMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                stats.withLock {
                    $0.workerWaitMS += waitedMS
                    $0.longestWorkerWaitMS = max($0.longestWorkerWaitMS, waitedMS)
                }
            }
        }
        defer { lock.unlock() }
        return try body()
    }
}

nonisolated extension NativeTimelineRowPainter {
    /// Paints a row, or a tile of it, into a new bitmap exactly as the
    /// timeline canvas caches it, holding the paint lock.
    static func rasterize(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        tileOrigin: CGFloat = 0,
        paint: () -> Void
    ) -> NSBitmapImageRep? {
        let pixelWidth = max(1, Int(ceil(width * scale)))
        let pixelHeight = max(1, Int(ceil(height * scale)))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: representation)
        else { return nil }
        NativeTimelinePaintLock.withLock {
            NSGraphicsContext.saveGraphicsState()
            graphics.cgContext.scaleBy(x: scale, y: scale)
            graphics.cgContext.translateBy(x: 0, y: height)
            graphics.cgContext.scaleBy(x: 1, y: -1)
            graphics.cgContext.translateBy(x: 0, y: -tileOrigin)
            let flippedGraphics = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
            NSGraphicsContext.current = flippedGraphics
            paint()
            flippedGraphics.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }
        representation.size = NSSize(width: width, height: height)
        return representation
    }

    /// Paints a row into a plain bitmap context in `colorSpace`, in the
    /// display's native pixel format, holding the paint lock. In device RGB
    /// it paints exactly what the canvas's cached bitmaps hold.
    static func rasterizeForDisplay(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        colorSpace: CGColorSpace,
        paint: () -> Void
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: max(1, Int(ceil(width * scale))),
            height: max(1, Int(ceil(height * scale))),
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        NativeTimelinePaintLock.withLock {
            NSGraphicsContext.saveGraphicsState()
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = graphics
            paint()
            graphics.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }
        return context.makeImage()
    }
}

/// Paints timeline rows on one background thread, in the order asked, from
/// a snapshot of what they read (`NativeTimelineRowPaintContext`).
///
/// One thread, not a pool: two painting threads bleed colour into each
/// other's rows (see `NativeTimelinePaintLock`). New requests replace the
/// queue, so the worker always paints what the next frames need first.
nonisolated final class NativeTimelineRowRasterizer: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        let identifier: NativeMessageTimelineItem.Identifier
        let pixelWidth: Int
    }

    struct Job: @unchecked Sendable {
        let key: Key
        let item: NativeMessageTimelineItem
        let layout: NativeTimelineRowLayout
        let width: CGFloat
        let scale: CGFloat
        let appearance: NSAppearance
        let context: NativeTimelineRowPaintContext?
        let model: AppModel?
        let spoilerRevealStore: NativeTimelineSpoilerRevealStore
        let animatedReactionIDs: Set<String>
        /// The window's colour space, which layer contents must already be
        /// in, or Core Animation converts them on the main thread as it
        /// commits each frame.
        let displayColorSpace: CGColorSpace
    }

    struct Bitmap: @unchecked Sendable {
        let key: Key
        let width: CGFloat
        let height: CGFloat
        /// In the display's colour space and pixel format, cropped to the
        /// painted columns: for a layer whose contents sit at its top left.
        let image: CGImage
        /// The full row in device RGB, as the canvas caches it; dropped once
        /// it cannot seed the canvas.
        private(set) var deviceImage: CGImage?
        /// Whether the row painted the same pixels as at its last width,
        /// so its converted image was reused.
        let reusedConversion: Bool
        let milliseconds: Double

        func droppingDeviceImage() -> Bitmap {
            var copy = self
            copy.deviceImage = nil
            return copy
        }
    }

    private struct State {
        var pending: [Job] = []
        var finished: [Bitmap] = []
        var isDraining = false
    }

    /// A row's last paint, to skip converting it again when a new width
    /// paints the same pixels (its lines wrap the same).
    private struct LastPaint {
        let device: CFData
        let bytesPerRow: Int
        let height: Int
        let paintedWidth: Int
        let image: CGImage
    }

    private let queue = DispatchQueue(label: "dev.sakuracord.timeline-row-rasterizer", qos: .userInteractive)
    /// Touched only on `queue`.
    nonisolated(unsafe) private var lastPaints: [NativeMessageTimelineItem.Identifier: LastPaint] = [:]
    private let state = Mutex(State())

    /// Replaces the jobs waiting to be painted.
    func submit(_ jobs: [Job]) {
        let starts = state.withLock { state in
            state.pending = jobs
            guard !state.isDraining, !jobs.isEmpty else { return false }
            state.isDraining = true
            return true
        }
        if starts { queue.async { self.drain() } }
    }

    func cancelPending() {
        state.withLock { $0.pending.removeAll() }
    }

    /// Drops what the worker keeps between paints, once a motion is over.
    func reset() {
        cancelPending()
        queue.async { self.lastPaints.removeAll() }
        _ = takeFinished()
    }

    /// The bitmaps painted since the last call.
    func takeFinished() -> [Bitmap] {
        state.withLock { state in
            defer { state.finished.removeAll(keepingCapacity: true) }
            return state.finished
        }
    }

    var isIdle: Bool {
        state.withLock { !$0.isDraining }
    }

    /// Calls `body` on the main thread once no row is being painted.
    func whenIdle(_ body: @escaping @MainActor @Sendable () -> Void) {
        cancelPending()
        queue.async {
            DispatchQueue.main.async { MainActor.assumeIsolated(body) }
        }
    }

    private func drain() {
        while let job = state.withLock({ state -> Job? in
            guard !state.pending.isEmpty else {
                state.isDraining = false
                return nil
            }
            return state.pending.removeFirst()
        }) {
            guard let bitmap = paint(job) else { continue }
            state.withLock { $0.finished.append(bitmap) }
        }
    }

    private func paint(_ job: Job) -> Bitmap? {
        let start = ProcessInfo.processInfo.systemUptime
        var layout = job.layout
        // Core Text layout objects are not shared between threads: the
        // layout's framesetter is cached for the main thread.
        if let content = layout.attributedContent {
            layout.contentFramesetter = CTFramesetterCreateWithAttributedString(content)
        }
        nonisolated(unsafe) let model = job.model
        // Painted in device RGB as the canvas paints, then converted as Core
        // Animation would convert the canvas's: pixel for pixel what the
        // canvas shows. Painting in the display's space blends translucent
        // pixels differently, by up to 17 levels.
        let deviceImage = NativeTimelineRowPainter.rasterizeForDisplay(
            width: job.width, height: layout.height, scale: job.scale, colorSpace: CGColorSpaceCreateDeviceRGB()
        ) {
            job.appearance.performAsCurrentDrawingAppearance {
                NativeTimelineRowPaintContext.$current.withValue(job.context) {
                    NativeTimelineRowPainter.draw(
                        item: job.item,
                        layout: layout,
                        in: CGRect(x: 0, y: 0, width: job.width, height: layout.height),
                        model: model,
                        isHovered: false,
                        spoilerRevealStore: job.spoilerRevealStore,
                        animatedReactionIDs: job.animatedReactionIDs
                    )
                }
            }
        }
        guard let deviceImage, let device = deviceImage.dataProvider?.data else { return nil }
        let paintedWidth = Self.paintedWidth(of: deviceImage) ?? deviceImage.width
        let image: CGImage
        let reused: Bool
        if let last = lastPaints[job.key.identifier],
           Self.samePixels(last, device: device, bytesPerRow: deviceImage.bytesPerRow,
                           height: deviceImage.height, paintedWidth: paintedWidth)
        {
            image = last.image
            reused = true
        } else {
            guard let converted = Self.displayImage(
                deviceImage, colorSpace: job.displayColorSpace, paintedWidth: paintedWidth
            ) else { return nil }
            image = converted
            reused = false
        }
        lastPaints[job.key.identifier] = LastPaint(
            device: device, bytesPerRow: deviceImage.bytesPerRow, height: deviceImage.height,
            paintedWidth: paintedWidth, image: image
        )
        return Bitmap(
            key: job.key, width: job.width, height: layout.height, image: image, deviceImage: deviceImage,
            reusedConversion: reused,
            milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000
        )
    }

    private static func samePixels(
        _ last: LastPaint, device: CFData, bytesPerRow: Int, height: Int, paintedWidth: Int
    ) -> Bool {
        guard last.height == height, last.paintedWidth == paintedWidth,
              let lhs = CFDataGetBytePtr(last.device), let rhs = CFDataGetBytePtr(device)
        else { return false }
        let length = paintedWidth * 4
        for row in 0 ..< height where memcmp(lhs + row * last.bytesPerRow, rhs + row * bytesPerRow, length) != 0 {
            return false
        }
        return true
    }

    /// The conversion Core Animation would otherwise make as it commits:
    /// the image drawn into a context of the display's colour space and
    /// native pixel format.
    static func displayImage(
        _ source: CGImage, colorSpace: CGColorSpace, croppingTransparentEdge: Bool = false, paintedWidth: Int? = nil
    ) -> CGImage? {
        // Conversion maps transparent pixels to transparent ones, so the
        // columns right of the painted ones need none.
        var source = source
        let painted = paintedWidth ?? (croppingTransparentEdge ? Self.paintedWidth(of: source) : nil)
        if let painted, painted < source.width,
           let cropped = source.cropping(to: CGRect(x: 0, y: 0, width: max(1, painted), height: source.height))
        {
            source = cropped
        }
        guard let context = CGContext(
            data: nil, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()
    }

    /// The columns up to the rightmost pixel that is not fully transparent,
    /// in a 32-bit premultiplied image.
    private static func paintedWidth(of image: CGImage) -> Int? {
        guard image.bitsPerPixel == 32, let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return nil }
        let bytesPerRow = image.bytesPerRow
        var painted = 0
        for row in 0 ..< image.height {
            let pixels = UnsafeRawPointer(bytes + row * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            var column = image.width - 1
            while column >= painted, pixels[column] == 0 { column -= 1 }
            painted = max(painted, column + 1)
            if painted == image.width { break }
        }
        return painted
    }
}
