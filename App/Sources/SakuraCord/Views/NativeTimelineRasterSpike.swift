import AppKit
import OSLog

// SPIKE (temporary, never shipped): can the existing row painter run off the
// main thread? Paints each visible row on main and on a worker thread, while
// main waits, and logs timings and pixel differences. Enabled only with the
// `--timeline-raster-spike` launch argument.
extension NativeTimelineCanvasView {
    private static let rasterSpikeEnabled = ProcessInfo.processInfo.arguments.contains("--timeline-raster-spike")
    private static var rasterSpikeScheduled: Set<ObjectIdentifier> = []
    private static let spikeLog = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "SideChatMotionBenchmark")

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
        runAppKitPrimitiveSpike()
        guard ProcessInfo.processInfo.arguments.contains("--timeline-raster-spike-rows") else { return }
        var rows: [Int] = []
        forEachDisplayedRow(in: visibleRect) { rows.append($0) }
        let scale = window?.backingScaleFactor ?? 2
        let appearance = effectiveAppearance
        Self.spikeLog.notice("SPIKE begin rows=\(rows.count) scale=\(Double(scale))")
        var paints: [(index: Int, width: CGFloat, height: CGFloat, paint: @Sendable () -> Void, main: [UInt8])] = []
        for index in rows {
            let item = items[index]
            let layout = layouts[index]
            let width = rowFrame(at: index).width
            let height = layout.height
            guard width > 1, height > 1 else { continue }
            let model = model
            let store = spoilerRevealStore
            let animated = animatedReactionIDs(for: item.identifier)
            let paint: @MainActor () -> Void = {
                NativeTimelineRowPainter.draw(
                    item: item, layout: layout,
                    in: CGRect(x: 0, y: 0, width: width, height: height),
                    model: model, isHovered: false,
                    spoilerRevealStore: store, animatedReactionIDs: animated
                )
            }
            // Spike only: calls the main-actor painter from a worker while
            // main is blocked waiting for it.
            let unsafePaint = Self.spikeWrap(unsafeBitCast(paint, to: (@Sendable () -> Void).self), appearance: appearance)
            let mainStart = ProcessInfo.processInfo.systemUptime
            let mainBytes = Self.spikeRaster(width: width, height: height, scale: scale, paint: unsafePaint)
            let mainMS = (ProcessInfo.processInfo.systemUptime - mainStart) * 1_000
            var offBytes: [UInt8] = []
            var offMS = 0.0
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                let start = ProcessInfo.processInfo.systemUptime
                offBytes = Self.spikeRaster(width: width, height: height, scale: scale, paint: unsafePaint)
                offMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                done.signal()
            }
            done.wait()
            let (differing, maximum) = Self.spikeDiff(mainBytes, offBytes)
            let kind = String(describing: item).prefix(28)
            Self.spikeLog.notice("SPIKE row \(index) \(kind, privacy: .public) w=\(Double(width)) h=\(Double(height)) main=\(mainMS) off=\(offMS) differingPixels=\(differing) maxDelta=\(maximum)")
            paints.append((index, width, height, unsafePaint, mainBytes))
        }
        // All rows at once on workers, as the renderer would.
        let results = UnsafeMutableBufferPointer<[UInt8]>.allocate(capacity: paints.count)
        results.initialize(repeating: [])
        let parallelStart = ProcessInfo.processInfo.systemUptime
        let jobs = paints.map { ($0.width, $0.height, $0.paint) }
        DispatchQueue.concurrentPerform(iterations: jobs.count) { job in
            let (width, height, paint) = jobs[job]
            results[job] = Self.spikeRaster(width: width, height: height, scale: scale, paint: paint)
        }
        let parallelMS = (ProcessInfo.processInfo.systemUptime - parallelStart) * 1_000
        var worst = 0
        for (offset, entry) in paints.enumerated() {
            worst = max(worst, Self.spikeDiff(entry.main, results[offset]).differing)
        }
        results.deinitialize()
        results.deallocate()
        Self.spikeLog.notice("SPIKE parallel rows=\(paints.count) wall=\(parallelMS) worstDifferingPixels=\(worst)")
    }

    /// The AppKit primitives the row painter uses, drawn from nonisolated
    /// code on main and on a worker, compared pixel for pixel.
    private func runAppKitPrimitiveSpike() {
        let appearance = effectiveAppearance
        nonisolated(unsafe) let symbol = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)!
        nonisolated(unsafe) let bitmap: NSImage = {
            let image = NSImage(size: NSSize(width: 40, height: 40))
            image.lockFocus(); NSColor.systemPink.setFill(); NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 32, height: 32)).fill(); image.unlockFocus()
            return image
        }()
        let paint: @Sendable () -> Void = { Self.primitivePaint(symbol: symbol, bitmap: bitmap) }
        let wrapped = Self.spikeWrap(paint, appearance: appearance)
        for iteration in 0 ..< 3 {
            let mainStart = ProcessInfo.processInfo.systemUptime
            let mainBytes = Self.spikeRaster(width: 600, height: 120, scale: 2, paint: wrapped)
            let mainMS = (ProcessInfo.processInfo.systemUptime - mainStart) * 1_000
            var offBytes: [UInt8] = []
            var offMS = 0.0
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                let start = ProcessInfo.processInfo.systemUptime
                offBytes = Self.spikeRaster(width: 600, height: 120, scale: 2, paint: wrapped)
                offMS = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                done.signal()
            }
            done.wait()
            let (differing, maximum) = Self.spikeDiff(mainBytes, offBytes)
            Self.spikeLog.notice("SPIKE primitives #\(iteration) main=\(mainMS) off=\(offMS) differingPixels=\(differing) maxDelta=\(maximum) nonEmpty=\(mainBytes.contains { $0 != 0 })")
        }
    }

    nonisolated private static func primitivePaint(symbol: NSImage, bitmap: NSImage) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 600, height: 120)).fill()
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 120, height: 40), xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath(roundedRect: NSRect(x: 140, y: 10, width: 120, height: 40), xRadius: 8, yRadius: 8)
        path.lineWidth = 2
        path.stroke()
        NSGradient(starting: .systemBlue, ending: .controlAccentColor)?.draw(in: NSRect(x: 270, y: 10, width: 100, height: 40), angle: 90)
        symbol.draw(in: NSRect(x: 380, y: 10, width: 30, height: 24))
        bitmap.draw(in: NSRect(x: 420, y: 10, width: 40, height: 40), from: .zero, operation: .sourceOver, fraction: 1)
        let font = NSFont.systemFont(ofSize: 14) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.secondaryLabelColor.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Live re-wrap off the main thread", attributes: attributes))
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: 10, y: 90)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        ("NSString draw" as NSString).draw(at: NSPoint(x: 300, y: 70), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
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
