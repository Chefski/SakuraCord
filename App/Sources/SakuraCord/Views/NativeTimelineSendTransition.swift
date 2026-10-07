import AppKit
import CoreText
import QuartzCore
import SakuraCordModels

/// Where a sent message was in the composer, in window coordinates.
struct NativeTimelineSendTransitionSource {
    struct Text {
        let image: NSImage
        let frame: CGRect
        /// The leading end of the first line's baseline.
        let baseline: CGPoint
    }

    let channelID: ChannelID
    /// The trimmed draft, which becomes the optimistic message content.
    let content: String
    let capturedAt: TimeInterval
    weak var window: NSWindow?
    let fieldFrame: CGRect
    let text: Text?
}

/// Hands a composer send to the timeline that later appends its optimistic
/// row. The sent text is held in place over the clearing field until then,
/// and released if no timeline claims it in time.
@MainActor
final class NativeTimelineSendTransitionStore {
    struct Pending {
        let source: NativeTimelineSendTransitionSource
        let overlay: NativeTimelineSendTransitionOverlay
    }

    static let lifetime: TimeInterval = 0.5

    private var pending: [ChannelID: Pending] = [:]

    func register(_ source: NativeTimelineSendTransitionSource) {
        discard(source.channelID)
        guard let overlay = NativeTimelineSendTransitionOverlay.holding(source)
        else { return }
        pending[source.channelID] = Pending(source: source, overlay: overlay)
        Task { @MainActor [weak self, weak overlay] in
            try? await Task.sleep(for: .seconds(Self.lifetime))
            guard let self, let overlay,
                  self.pending[source.channelID]?.overlay === overlay
            else { return }
            self.discard(source.channelID)
        }
    }

    func hasPendingSource(
        for channelID: ChannelID,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard let entry = pending[channelID] else { return false }
        guard now - entry.source.capturedAt <= Self.lifetime else {
            discard(channelID)
            return false
        }
        return true
    }

    /// Claims the pending send whose text became `message`. The caller owns
    /// the returned overlay and must run or dismiss it.
    func consume(
        for message: Message,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Pending? {
        guard hasPendingSource(for: message.channelID, now: now),
              pending[message.channelID]?.source.content == message.content
        else { return nil }
        return pending.removeValue(forKey: message.channelID)
    }

    private func discard(_ channelID: ChannelID) {
        pending.removeValue(forKey: channelID)?.overlay.dismiss()
    }
}

/// Telegram's open-source iOS client reproduces the iMessage send transition
/// by animating each axis on its own curve: the bubble settles into its width
/// and column almost immediately while it travels up more gradually, and the
/// transcript moves on the same vertical curve.
enum NativeTimelineSendTransitionTiming {
    static let duration: CFTimeInterval = 0.36
    static let fillFadeDuration: CFTimeInterval = 0.08
    static let sourceTextFadeDuration: CFTimeInterval = 0.1
    static let contentFadeDuration: CFTimeInterval = 0.08
    static let tailFadeDelay: CFTimeInterval = 0.06
    static let tailFadeDuration: CFTimeInterval = 0.12
    static let dismissalDuration: CFTimeInterval = 0.12

    static var horizontal: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    static var vertical: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.01, 0.28, 0.91)
    }
}

/// The flying bubble. It sits above the composer and timeline while the
/// canvas leaves the destination bubble transparent.
@MainActor
final class NativeTimelineSendTransitionOverlay: NSView {
    /// Destination geometry in this view's (unflipped) coordinates.
    struct Geometry {
        let fieldFrame: CGRect
        let bubbleFrame: CGRect
        let bubbleCornerRadius: CGFloat
        /// Relative to the bubble's bottom trailing corner.
        let tailPath: CGPath?
        let fillColor: CGColor
        let contentImage: NSImage
        let contentFrame: CGRect
        let contentBaseline: CGPoint
    }

    private let bubbleLayer = CALayer()
    private let tailLayer = CAShapeLayer()
    private let contentLayer = CALayer()
    private let finalContentLayer = CALayer()
    private let sourceTextLayer = CALayer()
    private var sourceBaseline: CGPoint?

    /// Covers the composer's text with an identical copy so clearing the
    /// field cannot blink before the timeline takes the message over.
    static func holding(
        _ source: NativeTimelineSendTransitionSource
    ) -> NativeTimelineSendTransitionOverlay? {
        guard let window = source.window,
              let container = window.contentView?.superview ?? window.contentView
        else { return nil }
        let overlay = NativeTimelineSendTransitionOverlay(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.addSubview(overlay, positioned: .above, relativeTo: nil)
        if let text = source.text {
            let baseline = overlay.convert(text.baseline, from: nil)
            overlay.sourceBaseline = baseline
            overlay.contentLayer.position = baseline
            overlay.sourceTextLayer.contents = text.image
            overlay.sourceTextLayer.contentsScale = window.backingScaleFactor
            overlay.sourceTextLayer.frame = overlay.convert(text.frame, from: nil)
                .offsetBy(dx: -baseline.x, dy: -baseline.y)
        }
        CATransaction.commit()
        return overlay
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        for sublayer in [bubbleLayer, tailLayer, contentLayer] {
            root.addSublayer(sublayer)
        }
        bubbleLayer.opacity = 0
        tailLayer.opacity = 0
        contentLayer.bounds = .zero
        contentLayer.anchorPoint = .zero
        contentLayer.addSublayer(finalContentLayer)
        contentLayer.addSublayer(sourceTextLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func run(_ geometry: Geometry, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let field = geometry.fieldFrame
        let bubble = geometry.bubbleFrame
        typealias Timing = NativeTimelineSendTransitionTiming

        bubbleLayer.frame = bubble
        bubbleLayer.backgroundColor = geometry.fillColor
        bubbleLayer.cornerRadius = geometry.bubbleCornerRadius
        bubbleLayer.cornerCurve = .continuous
        animateAxes(
            bubbleLayer,
            offset: CGPoint(x: field.midX - bubble.midX, y: field.midY - bubble.midY)
        )
        add(bubbleLayer, "bounds.size.width", from: field.width, to: bubble.width, timing: Timing.horizontal)
        add(bubbleLayer, "bounds.size.height", from: field.height, to: bubble.height, timing: Timing.vertical)
        add(
            bubbleLayer, "cornerRadius",
            from: min(geometry.bubbleCornerRadius, field.height / 2),
            to: geometry.bubbleCornerRadius,
            timing: Timing.vertical
        )
        fadeIn(bubbleLayer, duration: Timing.fillFadeDuration)

        if let tailPath = geometry.tailPath {
            tailLayer.bounds = .zero
            tailLayer.anchorPoint = .zero
            tailLayer.position = CGPoint(x: bubble.maxX, y: bubble.minY)
            tailLayer.path = tailPath
            tailLayer.fillColor = geometry.fillColor
            animateAxes(
                tailLayer,
                offset: CGPoint(x: field.maxX - bubble.maxX, y: field.minY - bubble.minY)
            )
            fadeIn(tailLayer, duration: Timing.tailFadeDuration, delay: Timing.tailFadeDelay)
        }

        finalContentLayer.contents = geometry.contentImage
        finalContentLayer.contentsScale = scale
        finalContentLayer.frame = geometry.contentFrame.offsetBy(
            dx: -geometry.contentBaseline.x,
            dy: -geometry.contentBaseline.y
        )
        fadeIn(finalContentLayer, duration: Timing.contentFadeDuration)
        sourceTextLayer.opacity = 0
        add(sourceTextLayer, "opacity", from: 1, to: 0, duration: Timing.sourceTextFadeDuration)
        // Without a text snapshot, the content leaves with the field's edge.
        let sourceBaseline = sourceBaseline ?? CGPoint(
            x: geometry.contentBaseline.x + field.minX - bubble.minX,
            y: geometry.contentBaseline.y + field.minY - bubble.minY
        )
        contentLayer.position = geometry.contentBaseline
        animateAxes(
            contentLayer,
            offset: CGPoint(
                x: sourceBaseline.x - geometry.contentBaseline.x,
                y: sourceBaseline.y - geometry.contentBaseline.y
            )
        )
    }

    /// Moves the in-flight bubble when its destination row moves, for example
    /// when a multiline composer collapses after sending.
    func retarget(by delta: CGPoint, duration: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for layer in [bubbleLayer, tailLayer, contentLayer] {
            layer.position.x += delta.x
            layer.position.y += delta.y
            animateAxes(layer, offset: CGPoint(x: -delta.x, y: -delta.y), duration: duration)
        }
    }

    /// Releases held text that no timeline animated.
    func dismiss() {
        guard let layer else {
            removeFromSuperview()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeFromSuperview()
        }
        layer.opacity = 0
        add(
            layer, "opacity", from: 1, to: 0,
            duration: NativeTimelineSendTransitionTiming.dismissalDuration
        )
        CATransaction.commit()
    }

    private func animateAxes(
        _ layer: CALayer,
        offset: CGPoint,
        duration: CFTimeInterval = NativeTimelineSendTransitionTiming.duration
    ) {
        if abs(offset.x) >= 0.5 {
            add(
                layer, "position.x", from: offset.x, to: 0,
                timing: NativeTimelineSendTransitionTiming.horizontal,
                duration: duration, isAdditive: true
            )
        }
        if abs(offset.y) >= 0.5 {
            add(
                layer, "position.y", from: offset.y, to: 0,
                timing: NativeTimelineSendTransitionTiming.vertical,
                duration: duration, isAdditive: true
            )
        }
    }

    private func fadeIn(_ layer: CALayer, duration: CFTimeInterval, delay: CFTimeInterval = 0) {
        layer.opacity = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.beginTime = delay > 0 ? layer.convertTime(CACurrentMediaTime(), from: nil) + delay : 0
        animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: nil)
    }

    private func add(
        _ layer: CALayer,
        _ keyPath: String,
        from: CGFloat,
        to: CGFloat,
        timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut),
        duration: CFTimeInterval = NativeTimelineSendTransitionTiming.duration,
        isAdditive: Bool = false
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        animation.isAdditive = isAdditive
        layer.add(animation, forKey: nil)
    }
}

/// An in-flight send transition owned by the timeline canvas.
@MainActor
final class NativeTimelineSendTransition {
    let identifier: NativeMessageTimelineItem.Identifier
    let overlay: NativeTimelineSendTransitionOverlay
    var bubbleFrameInWindow: CGRect
    var endUptime: TimeInterval
    var finishTask: Task<Void, Never>?

    init(
        identifier: NativeMessageTimelineItem.Identifier,
        overlay: NativeTimelineSendTransitionOverlay,
        bubbleFrameInWindow: CGRect,
        endUptime: TimeInterval
    ) {
        self.identifier = identifier
        self.overlay = overlay
        self.bubbleFrameInWindow = bubbleFrameInWindow
        self.endUptime = endUptime
    }
}

extension NativeTimelineCanvasView {
    private static let sendTransitionShiftKey = "sakuraCordSendTransitionShift"

    /// Starts the held text leaving the composer for its row as a bubble.
    /// `transcriptShift` is how far the earlier rows just moved in window
    /// coordinates, so they can glide there with the bubble instead of
    /// jumping.
    func beginSendTransition(
        from pending: NativeTimelineSendTransitionStore.Pending,
        rowIndex index: Int,
        transcriptShift: CGFloat
    ) {
        finishSendTransition()
        guard let window,
              let (geometry, bubbleInWindow) = sendTransitionGeometry(
                  from: pending, rowIndex: index, in: window
              )
        else {
            pending.overlay.dismiss()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let transition = NativeTimelineSendTransition(
            identifier: items[index].identifier,
            overlay: pending.overlay,
            bubbleFrameInWindow: bubbleInWindow,
            endUptime: ProcessInfo.processInfo.systemUptime
                + NativeTimelineSendTransitionTiming.duration
        )
        sendTransition = transition
        setNeedsDisplay(rowFrame(at: index))
        shiftTranscriptForSendTransition(by: transcriptShift)
        displayIfNeeded()
        pending.overlay.run(geometry, scale: window.backingScaleFactor)
        CATransaction.commit()
        scheduleSendTransitionFinish(transition)
    }

    private func sendTransitionGeometry(
        from pending: NativeTimelineSendTransitionStore.Pending,
        rowIndex index: Int,
        in window: NSWindow
    ) -> (NativeTimelineSendTransitionOverlay.Geometry, CGRect)? {
        let source = pending.source
        let overlay = pending.overlay
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              source.window === window,
              overlay.window === window,
              items.indices.contains(index),
              layouts.indices.contains(index),
              case let .message(row, _, _) = items[index],
              row.message.attachments.isEmpty,
              row.message.stickers.isEmpty,
              row.message.poll == nil,
              let region = layouts[index].bubbleRegion,
              region.isOutgoing
        else { return nil }
        let rowFrame = rowFrame(at: index)
        let bubbleInWindow = convert(region.frame.offsetBy(dx: rowFrame.minX, dy: rowFrame.minY), to: nil)
        guard convert(visibleRect, to: nil).intersects(bubbleInWindow),
              let content = sendTransitionContent(item: items[index], layout: layouts[index], rowFrame: rowFrame)
        else { return nil }
        let bubbleFrame = overlay.convert(bubbleInWindow, from: nil)
        var fillColor = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fillColor = NativeTimelineBubbleDrawing.fillColor(for: region).cgColor
        }
        let geometry = NativeTimelineSendTransitionOverlay.Geometry(
            fieldFrame: overlay.convert(source.fieldFrame, from: nil),
            bubbleFrame: bubbleFrame,
            bubbleCornerRadius: min(
                NativeTimelineBubbleDrawing.cornerRadius,
                bubbleFrame.height / 2,
                bubbleFrame.width / 2
            ),
            tailPath: region.showsTail ? Self.sendTransitionTailPath() : nil,
            fillColor: fillColor,
            contentImage: content.image,
            contentFrame: overlay.convert(content.frameInWindow, from: nil),
            contentBaseline: overlay.convert(content.baselineInWindow, from: nil)
        )
        return (geometry, bubbleInWindow)
    }

    /// Keeps an in-flight bubble aimed at its row after a later timeline
    /// update moves it, and ends the transition if the row changed shape.
    func reconcileSendTransition() {
        guard let transition = sendTransition else { return }
        guard let index = items.firstIndex(where: { $0.identifier == transition.identifier }),
              layouts.indices.contains(index),
              let region = layouts[index].bubbleRegion
        else {
            finishSendTransition()
            return
        }
        let rowFrame = rowFrame(at: index)
        let bubbleInWindow = convert(region.frame.offsetBy(dx: rowFrame.minX, dy: rowFrame.minY), to: nil)
        let previous = transition.bubbleFrameInWindow
        guard abs(bubbleInWindow.width - previous.width) < 0.5,
              abs(bubbleInWindow.height - previous.height) < 0.5
        else {
            finishSendTransition()
            return
        }
        let delta = CGPoint(x: bubbleInWindow.minX - previous.minX, y: bubbleInWindow.minY - previous.minY)
        guard abs(delta.x) >= 0.5 || abs(delta.y) >= 0.5 else { return }
        transition.bubbleFrameInWindow = bubbleInWindow
        let now = ProcessInfo.processInfo.systemUptime
        let duration = max(0.2, transition.endUptime - now)
        transition.endUptime = max(transition.endUptime, now + duration)
        transition.overlay.retarget(by: delta, duration: duration)
        scheduleSendTransitionFinish(transition)
    }

    func finishSendTransition() {
        guard let transition = sendTransition else { return }
        sendTransition = nil
        transition.finishTask?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let index = items.firstIndex(where: { $0.identifier == transition.identifier }) {
            setNeedsDisplay(rowFrame(at: index))
            displayIfNeeded()
        }
        transition.overlay.removeFromSuperview()
        CATransaction.commit()
    }

    /// The destination bubble stays transparent while its copy is in flight.
    func clearSendTransitionBubble(
        for item: NativeMessageTimelineItem,
        layout: NativeTimelineRowLayout,
        rowFrame: CGRect
    ) {
        guard sendTransition?.identifier == item.identifier,
              let region = layout.bubbleRegion,
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.addPath(NativeTimelineBubbleDrawing.path(for: NativeTimelineBubbleRegion(
            frame: region.frame.offsetBy(dx: rowFrame.minX, dy: rowFrame.minY).insetBy(dx: -1, dy: -1),
            isOutgoing: region.isOutgoing,
            showsTail: region.showsTail
        )).cgPath)
        context.fillPath()
        context.restoreGState()
    }

    private func scheduleSendTransitionFinish(_ transition: NativeTimelineSendTransition) {
        transition.finishTask?.cancel()
        transition.finishTask = Task { @MainActor [weak self, weak transition] in
            while let transition {
                let remaining = transition.endUptime - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { break }
                do {
                    try await Task.sleep(for: .milliseconds(Int(ceil(remaining * 1_000))))
                } catch {
                    return
                }
            }
            guard let self, let transition, self.sendTransition === transition else { return }
            self.finishSendTransition()
        }
    }

    /// Plays the earlier rows' jump back as a glide on the bubble's vertical
    /// curve. The animation is additive and presentation-only, so hit testing
    /// and scroll state already describe the final positions.
    private func shiftTranscriptForSendTransition(by shift: CGFloat) {
        guard abs(shift) >= 0.5, let layer else { return }
        // Rows that start above the viewport become visible during the glide.
        let exposed = visibleRect
        setNeedsDisplay(CGRect(
            x: exposed.minX,
            y: exposed.minY - abs(shift),
            width: exposed.width,
            height: abs(shift)
        ))
        // Layer geometry follows the superview's coordinate space.
        let translation = superview?.isFlipped == true ? shift : -shift
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = translation
        animation.toValue = 0
        animation.duration = NativeTimelineSendTransitionTiming.duration
        animation.timingFunction = NativeTimelineSendTransitionTiming.vertical
        animation.isAdditive = true
        layer.add(animation, forKey: Self.sendTransitionShiftKey)
    }

    private struct SendTransitionContent {
        let image: NSImage
        let frameInWindow: CGRect
        let baselineInWindow: CGPoint
    }

    /// Renders what the destination bubble contains, without its fill, so the
    /// flying copy can morph its own background independently.
    private func sendTransitionContent(
        item: NativeMessageTimelineItem,
        layout: NativeTimelineRowLayout,
        rowFrame: CGRect
    ) -> SendTransitionContent? {
        guard let region = layout.bubbleRegion,
              let contentFrame = layout.contentFrame,
              let attributedContent = layout.attributedContent,
              let framesetter = layout.contentFramesetter
        else { return nil }
        let bubblePath = NativeTimelineBubbleDrawing.path(for: region)
        let drawRect = bubblePath.bounds.insetBy(dx: -1, dy: -1).integral
        let scale = max(1, window?.backingScaleFactor ?? 2)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(drawRect.width * scale))),
            pixelsHigh: max(1, Int(ceil(drawRect.height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: representation)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: drawRect.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -drawRect.minX, y: -drawRect.minY)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bubblePath.addClip()
            NativeTimelineRowPainter.draw(
                item: item,
                layout: layout,
                in: CGRect(x: 0, y: 0, width: rowFrame.width, height: layout.height),
                model: model,
                isHovered: false,
                drawsBubbleBackground: false,
                spoilerRevealStore: spoilerRevealStore
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        representation.size = drawRect.size
        let image = NSImage(size: drawRect.size)
        image.addRepresentation(representation)

        // Match the painter's CoreText frame to find the first baseline.
        let drawingFrame = NativeTimelineTextGeometry.messageContentDrawingFrame(contentFrame)
        let textFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedContent.length),
            CGPath(rect: CGRect(origin: .zero, size: drawingFrame.size), transform: nil),
            nil
        )
        var lineOrigin = CGPoint.zero
        if CFArrayGetCount(CTFrameGetLines(textFrame)) > 0 {
            CTFrameGetLineOrigins(textFrame, CFRange(location: 0, length: 1), &lineOrigin)
        }
        let baseline = CGPoint(
            x: rowFrame.minX + drawingFrame.minX + lineOrigin.x,
            y: rowFrame.minY + drawingFrame.maxY - lineOrigin.y
        )
        return SendTransitionContent(
            image: image,
            frameInWindow: convert(drawRect.offsetBy(dx: rowFrame.minX, dy: rowFrame.minY), to: nil),
            baselineInWindow: convert(baseline, to: nil)
        )
    }

    /// The bubble tail relative to its bottom trailing corner, in the
    /// overlay's unflipped coordinates.
    private static func sendTransitionTailPath() -> CGPath {
        let size: CGFloat = 64
        let path = NativeTimelineBubbleDrawing.tailPath(for: NativeTimelineBubbleRegion(
            frame: CGRect(x: -size, y: -size, width: size, height: size),
            isOutgoing: true,
            showsTail: true
        ))
        path.transform(using: AffineTransform(scaleByX: 1, byY: -1))
        return path.cgPath
    }
}

extension NativeMessageTimelineCoordinator {
    struct SendTransitionTranscriptAnchor {
        let identifier: NativeMessageTimelineItem.Identifier
        let frameInWindow: CGRect
    }

    /// Records where the newest existing row is before a pending send's
    /// optimistic row arrives, so its jump can be measured afterwards.
    func sendTransitionTranscriptAnchor(
        for parent: NativeMessageTimelineView
    ) -> SendTransitionTranscriptAnchor? {
        guard parent.conversation == self.parent.conversation,
              let channelID = parent.conversation.sendTransitionChannelID,
              parent.model.timelineSendTransitionStore.hasPendingSource(for: channelID),
              let canvas,
              let index = items.lastIndex(where: { $0.messageID != nil })
        else { return nil }
        return SendTransitionTranscriptAnchor(
            identifier: items[index].identifier,
            frameInWindow: canvas.convert(canvas.rowFrame(at: index), to: nil)
        )
    }

    func startSendTransitionIfNeeded(
        parent: NativeMessageTimelineView,
        preparation: TimelineUpdatePreparation,
        transcriptAnchor: SendTransitionTranscriptAnchor?
    ) {
        guard didMutateItems,
              !preparation.conversationChanged,
              let channelID = parent.conversation.sendTransitionChannelID,
              let canvas
        else { return }
        let store = parent.model.timelineSendTransitionStore
        guard store.hasPendingSource(for: channelID) else { return }
        let currentUserID = parent.model.snapshot?.currentUser.id
        // The optimistic row joins the tail of the newest window.
        for index in items.indices.reversed().prefix(3) {
            guard case let .message(row, _, _) = items[index],
                  // A fast confirmation can replace the optimistic row
                  // before this update; the nonce still marks a local send.
                  row.message.nonce != nil,
                  row.message.outboxState != .failed,
                  row.message.author.id == currentUserID,
                  let pending = store.consume(for: row.message)
            else { continue }
            let shift = transcriptAnchor.flatMap { anchor in
                items.firstIndex(where: { $0.identifier == anchor.identifier }).map {
                    canvas.convert(canvas.rowFrame(at: $0), to: nil).minY - anchor.frameInWindow.minY
                }
            } ?? 0
            canvas.beginSendTransition(from: pending, rowIndex: index, transcriptShift: shift)
            return
        }
    }
}

extension NativeTimelineConversation {
    /// Conversations whose composer can send into this timeline.
    var sendTransitionChannelID: ChannelID? {
        switch self {
        case let .channel(id), let .thread(id):
            id
        case .search, .pins, .inbox, .resource:
            nil
        }
    }
}
