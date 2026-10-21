import AppKit
import OSLog

// SPIKE (temporary, never shipped): can timeline rows paint off the main
// thread, pixel for pixel, fast enough to follow a motion? Enabled only with
// the `--timeline-raster-spike` launch argument; the rows phase also needs
// `--timeline-raster-spike-rows`. Results go to the log under "SPIKE".
//
// Findings so far: one worker painting while main draws is pixel-exact; a
// wide fan-out across all cores is not (Core Graphics bleeds colour between
// contexts drawn at once), so rows paint on one serial queue.
private struct SpikePaint: @unchecked Sendable {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    let paint: @Sendable () -> Void
    let main: [UInt8]
}

extension NativeTimelineCanvasView {
    private static let rasterSpikeEnabled = ProcessInfo.processInfo.arguments.contains("--timeline-raster-spike")
    private static var rasterSpikeScheduled: Set<ObjectIdentifier> = []
    private static let spikeLog = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "SideChatMotionBenchmark")
    nonisolated private static let spikeQueue = DispatchQueue(label: "dev.sakuracord.timeline-raster-spike", qos: .userInteractive)

    func scheduleRasterSpikeIfNeeded() {
        guard Self.rasterSpikeEnabled, window != nil,
              !Self.rasterSpikeScheduled.contains(ObjectIdentifier(self))
        else { return }
        Self.rasterSpikeScheduled.insert(ObjectIdentifier(self))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.runRasterSpike()
        }
    }

    private func runRasterSpike() {
        guard ProcessInfo.processInfo.arguments.contains("--timeline-raster-spike-rows") else { return }
        let scale = window?.backingScaleFactor ?? 2
        let appearance = effectiveAppearance
        let rows = Array(items.indices.prefix(400))
        var visible: [Int] = []
        forEachDisplayedRow(in: visibleRect) { visible.append($0) }
        Self.spikeLog.notice("SPIKE begin rows=\(rows.count) visible=\(visible.count) width=\(Double(self.bounds.width)) scale=\(Double(scale))")

        let contextStart = ProcessInfo.processInfo.systemUptime
        let context = paintContext(for: rows)
        Self.spikeLog.notice("SPIKE context build=\(Self.milliseconds(since: contextStart))")

        // Each row on main (the production path) and on the serial worker.
        var paints: [SpikePaint] = []
        var mainTotal = 0.0
        for index in rows {
            let layout = layouts[index]
            let width = rowFrame(at: index).width
            guard width > 1, layout.height > 1 else { continue }
            let mainPaint = rowPaint(index: index, layout: layout, width: width, context: nil, appearance: appearance)
            let start = ProcessInfo.processInfo.systemUptime
            let main = Self.spikeRaster(width: width, height: layout.height, scale: scale, paint: mainPaint)
            mainTotal += Self.milliseconds(since: start)
            let workerPaint = rowPaint(index: index, layout: layout, width: width, context: context, appearance: appearance)
            paints.append(SpikePaint(index: index, width: width, height: layout.height, paint: workerPaint, main: main))
        }
        for pass in 0 ..< 3 {
            let results = Self.paintSerially(paints, scale: scale)
            let differing = zip(paints, results).filter { Self.spikeDiff($0.main, $1.bytes).differing != 0 }.map(\.0.index)
            let total = results.reduce(0) { $0 + $1.milliseconds }
            let slowest = results.map(\.milliseconds).max() ?? 0
            Self.spikeLog.notice(
                "SPIKE serial pass=\(pass) rows=\(paints.count) workerTotal=\(total) mainTotal=\(mainTotal) slowestRow=\(slowest) differingRows=\(differing.description, privacy: .public)"
            )
        }
        runWidthSweep(visible: visible, context: context, appearance: appearance, scale: scale)
        runStress(paints, appearance: appearance, scale: scale)
    }

    /// The motion's width path: per frame, layouts on main at the new width,
    /// then the visible rows painted on the worker.
    private func runWidthSweep(
        visible: [Int], context: NativeTimelineRowPaintContext?, appearance: NSAppearance, scale: CGFloat
    ) {
        let startWidth = bounds.width
        let frames = 40
        var layoutTimes: [Double] = []
        var paintTimes: [Double] = []
        var differingFrames = 0
        for frame in 0 ..< frames {
            let width = (startWidth - 320 * CGFloat(frame) / CGFloat(frames - 1)).rounded()
            let layoutStart = ProcessInfo.processInfo.systemUptime
            let frameLayouts = visible.map { NativeTimelineRowLayout.make(item: items[$0], width: width, model: model) }
            layoutTimes.append(Self.milliseconds(since: layoutStart))
            let paints = zip(visible, frameLayouts).map { index, layout in
                SpikePaint(
                    index: index, width: width, height: layout.height,
                    paint: rowPaint(index: index, layout: layout, width: width, context: context, appearance: appearance),
                    main: []
                )
            }
            let results = Self.paintSerially(paints, scale: scale)
            paintTimes.append(results.reduce(0) { $0 + $1.milliseconds })
            // Every tenth frame, the same rows painted on main must match.
            if frame.isMultiple(of: 10) {
                let mismatch = zip(zip(visible, frameLayouts), results).contains { pair, result in
                    let mainPaint = rowPaint(index: pair.0, layout: pair.1, width: width, context: nil, appearance: appearance)
                    let main = Self.spikeRaster(width: width, height: pair.1.height, scale: scale, paint: mainPaint)
                    return Self.spikeDiff(main, result.bytes).differing != 0
                }
                if mismatch { differingFrames += 1 }
            }
        }
        Self.spikeLog.notice(
            """
            SPIKE sweep frames=\(frames) rows=\(visible.count) \
            layoutMain p50=\(Self.percentile(layoutTimes, 0.5)) p95=\(Self.percentile(layoutTimes, 0.95)) max=\(layoutTimes.max() ?? 0) \
            paintWorker p50=\(Self.percentile(paintTimes, 0.5)) p95=\(Self.percentile(paintTimes, 0.95)) max=\(paintTimes.max() ?? 0) \
            parityFramesDiffering=\(differingFrames) of \(frames / 10)
            """
        )
    }

    /// The parity harness's stress checks: the serial worker while main
    /// draws, and the fan-out the renderer must not use.
    private func runStress(_ paints: [SpikePaint], appearance: NSAppearance, scale: CGFloat) {
        let mainLoad = Self.spikeWrap({
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            for index in 0 ..< 20 {
                let path = CGPath(
                    roundedRect: CGRect(x: index * 20, y: 4, width: 40, height: 20),
                    cornerWidth: 9, cornerHeight: 9, transform: nil
                )
                context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 0.16))
                context.addPath(path)
                context.fillPath()
                context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 0.3))
                context.addPath(path)
                context.fillPath()
            }
        }, appearance: appearance)
        // Serial worker, five passes over every row, while main draws.
        nonisolated(unsafe) var serialDiffering = 0
        nonisolated(unsafe) var finished = false
        let lock = NSLock()
        Self.spikeQueue.async {
            for _ in 0 ..< 5 {
                for entry in paints {
                    let bytes = Self.spikeRaster(width: entry.width, height: entry.height, scale: scale, paint: entry.paint)
                    if Self.spikeDiff(entry.main, bytes).differing != 0 { serialDiffering += 1 }
                }
            }
            lock.withLock { finished = true }
        }
        var mainDraws = 0
        while !lock.withLock({ finished }) {
            _ = Self.spikeRaster(width: 440, height: 30, scale: scale, paint: mainLoad)
            mainDraws += 1
        }
        Self.spikeLog.notice("SPIKE stress serialWhileMainDraws paints=\(paints.count * 5) differing=\(serialDiffering) mainDraws=\(mainDraws)")

        // Fan-out across every core, for the record.
        let copies = paints.count * 4
        let results = UnsafeMutableBufferPointer<[UInt8]>.allocate(capacity: copies)
        results.initialize(repeating: [])
        DispatchQueue.concurrentPerform(iterations: copies) { job in
            let entry = paints[job % paints.count]
            results[job] = Self.spikeRaster(width: entry.width, height: entry.height, scale: scale, paint: entry.paint)
        }
        let fanOutDiffering = (0 ..< copies).filter {
            Self.spikeDiff(paints[$0 % paints.count].main, results[$0]).differing != 0
        }.count
        results.deinitialize()
        results.deallocate()
        Self.spikeLog.notice("SPIKE stress fanOut paints=\(copies) differing=\(fanOutDiffering)")
    }

    /// The rows' app state and loaded images, gathered on main.
    private func paintContext(for rows: [Int]) -> NativeTimelineRowPaintContext? {
        var mediaImages: [NativeTimelineMediaKey: NSImage] = [:]
        for index in rows {
            for key in mediaKeys(for: items[index], at: index) {
                if let image = NativeTimelineMediaStore.shared.firstAnimatedFrame(for: key)
                    ?? NativeTimelineMediaStore.shared.image(for: key)
                {
                    mediaImages[key] = image
                }
            }
        }
        return model.map {
            NativeTimelineRowPaintContext(model: $0, items: rows.map { items[$0] }, mediaImages: mediaImages)
        }
    }

    /// One row's paint; without a context it reads the app on main, as the
    /// canvas does.
    private func rowPaint(
        index: Int, layout: NativeTimelineRowLayout, width: CGFloat,
        context: NativeTimelineRowPaintContext?, appearance: NSAppearance
    ) -> @Sendable () -> Void {
        nonisolated(unsafe) let item = items[index]
        nonisolated(unsafe) let layout = layout
        nonisolated(unsafe) let model = model
        nonisolated(unsafe) let store = spoilerRevealStore
        nonisolated(unsafe) let context = context
        let animated = animatedReactionIDs(for: item.identifier)
        let paint: @Sendable () -> Void = {
            let draw = {
                NativeTimelineRowPainter.draw(
                    item: item, layout: layout,
                    in: CGRect(x: 0, y: 0, width: width, height: layout.height),
                    model: model, isHovered: false,
                    spoilerRevealStore: store, animatedReactionIDs: animated
                )
            }
            if let context {
                NativeTimelineRowPaintContext.$current.withValue(context, operation: draw)
            } else {
                draw()
            }
        }
        return Self.spikeWrap(paint, appearance: appearance)
    }

    /// Paints in order on the serial worker while main waits.
    nonisolated private static func paintSerially(
        _ paints: [SpikePaint], scale: CGFloat
    ) -> [(bytes: [UInt8], milliseconds: Double)] {
        nonisolated(unsafe) var results: [(bytes: [UInt8], milliseconds: Double)] = []
        spikeQueue.sync {
            for entry in paints {
                let start = ProcessInfo.processInfo.systemUptime
                let bytes = spikeRaster(width: entry.width, height: entry.height, scale: scale, paint: entry.paint)
                results.append((bytes, milliseconds(since: start)))
            }
        }
        return results
    }

    nonisolated private static func milliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    nonisolated private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
    }

    /// Appearance applied from a nonisolated block: a main-actor closure
    /// handed to AppKit checks its thread when called.
    nonisolated private static func spikeWrap(
        _ paint: @escaping @Sendable () -> Void, appearance: NSAppearance
    ) -> @Sendable () -> Void {
        nonisolated(unsafe) let appearance = appearance
        return { appearance.performAsCurrentDrawingAppearance { paint() } }
    }

    nonisolated private static func spikeRaster(
        width: CGFloat, height: CGFloat, scale: CGFloat, paint: @Sendable () -> Void
    ) -> [UInt8] {
        let pixelWidth = max(1, Int(ceil(width * scale)))
        let pixelHeight = max(1, Int(ceil(height * scale)))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return [] }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        paint()
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = context.data else { return [] }
        let count = pixelWidth * pixelHeight * 4
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
    }

    nonisolated private static func spikeDiff(_ lhs: [UInt8], _ rhs: [UInt8]) -> (differing: Int, maximum: Int) {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return (-1, -1) }
        let equal = lhs.withUnsafeBytes { lhs in
            rhs.withUnsafeBytes { rhs in memcmp(lhs.baseAddress!, rhs.baseAddress!, lhs.count) == 0 }
        }
        if equal { return (0, 0) }
        var differing = 0
        var maximum = 0
        var index = 0
        while index < lhs.count {
            var pixelMax = 0
            for channel in 0 ..< 4 {
                pixelMax = max(pixelMax, abs(Int(lhs[index + channel]) - Int(rhs[index + channel])))
            }
            if pixelMax > 0 { differing += 1 }
            maximum = max(maximum, pixelMax)
            index += 4
        }
        return (differing, maximum)
    }
}
