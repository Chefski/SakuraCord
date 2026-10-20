import AppKit
import QuartzCore
import SakuraCordModels

/// A row as it stood before a timeline update moved the NEW divider, read from
/// what was on screen so a motion can start from that picture.
struct NativeTimelineUnreadDividerSource {
    let identifier: NativeMessageTimelineItem.Identifier
    /// Where the divider sat in the row, when the row had one.
    let frameInRow: CGRect?
    /// The top of the divider's space, relative to the viewport.
    let topInViewport: CGFloat
    /// The row's laid-out height, which the divider's space is part of.
    let height: CGFloat
    /// How much of the divider's space was open on screen, when a motion
    /// was already moving it.
    let startGap: CGFloat?
}

/// The NEW divider moving between rows in one timeline update.
struct NativeTimelineUnreadDividerChange {
    let removed: NativeTimelineUnreadDividerSource?
    let added: NativeTimelineUnreadDividerSource?
    let addedMessageID: MessageID?

    @MainActor
    func fade(on canvas: NativeTimelineCanvasView) {
        canvas.transitionUnreadDivider(self)
    }
}

enum NativeTimelineUnreadDividerMotion {
    /// Matches the row disclosure so the fade and the gap land together.
    static let fadeInDuration: CFTimeInterval = NativeTimelineRowDisclosure.duration
    static let fadeOutDuration: CFTimeInterval = 0.2
    /// Reduce Motion keeps a plain, quick fade and nothing else.
    static let reducedMotionDuration: CFTimeInterval = 0.12
    static let opacityKey = "sakuraCordUnreadDividerFade"

    static func duration(appearing: Bool, reducesMotion: Bool) -> CFTimeInterval {
        if reducesMotion { return reducedMotionDuration }
        return appearing ? fadeInDuration : fadeOutDuration
    }
}

/// The divider painted once. It never redraws while it fades or while its
/// container resizes.
final class NativeTimelineUnreadDividerArtwork: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NativeTimelineRowPainter.newMessagesSeparator(frame: bounds)
    }
}

/// Clips the divider to the space it may occupy. While the divider's gap opens
/// or closes this container is exactly the gap, so the line can never draw
/// over a message. Fading is a compositor opacity animation on this layer.
final class NativeTimelineUnreadDividerOverlay: NSView {
    let artwork = NativeTimelineUnreadDividerArtwork(frame: .zero)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(artwork)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setArtworkSize(_ size: CGSize) {
        guard artwork.frame.size != size else { return }
        artwork.frame = CGRect(origin: .zero, size: size)
    }
}

/// A divider that is fading in or out above its row.
struct NativeTimelineUnreadDividerFade {
    let overlay: NativeTimelineUnreadDividerOverlay
    var frameInRow: CGRect
    var isAppearing: Bool
    var finishTask: Task<Void, Never>?
}

extension NativeTimelineCanvasView {
    /// The divider's row as laid out now, whether or not it has one.
    func unreadDividerSource(
        forMessageID messageID: MessageID?
    ) -> NativeTimelineUnreadDividerSource? {
        guard let messageID,
              let index = items.firstIndex(where: { $0.messageID == messageID }),
              layouts.indices.contains(index)
        else { return nil }
        let identifier = items[index].identifier
        let frame = layouts[index].unreadSeparatorFrame
        let activeGap = unreadDividerGap?.identifier == identifier ? unreadDividerGap : nil
        let top = activeGap == nil ? displayedRowOrigin(at: index) : unreadDividerGapTop
        return NativeTimelineUnreadDividerSource(
            identifier: identifier,
            frameInRow: frame,
            topInViewport: top - viewportMinY,
            height: layouts[index].height,
            startGap: activeGap?.gap
        )
    }

    /// The divider's placement in the row that now has it.
    func unreadDividerPlacement(
        forMessageID messageID: MessageID?
    ) -> (identifier: NativeMessageTimelineItem.Identifier, frameInRow: CGRect)? {
        guard let messageID,
              let index = items.firstIndex(where: { $0.messageID == messageID }),
              layouts.indices.contains(index),
              let frame = layouts[index].unreadSeparatorFrame
        else { return nil }
        return (items[index].identifier, frame)
    }

    /// Opens or closes the divider's gap and fades the line inside it. Where
    /// the gap cannot move rows, an arriving divider simply fades in; a
    /// removed one is dropped, since the next message already fills its slot.
    func transitionUnreadDivider(_ change: NativeTimelineUnreadDividerChange) {
        let added = unreadDividerPlacement(forMessageID: change.addedMessageID)
        let removed = change.removed.flatMap { $0.frameInRow == nil ? nil : $0 }
        var opensGap = false
        if let removed, added == nil {
            opensGap = beginUnreadDividerGap(from: removed, appearing: false)
        } else if removed == nil, added != nil, let source = change.added {
            opensGap = beginUnreadDividerGap(from: source, appearing: true)
        }
        if let removed, !opensGap {
            finishUnreadDividerFade(removed.identifier)
        }
        if let added {
            beginUnreadDividerFade(
                identifier: added.identifier,
                frameInRow: added.frameInRow,
                appearing: true,
                usesGap: opensGap
            )
        } else if opensGap, let removed, let frame = removed.frameInRow {
            beginUnreadDividerFade(
                identifier: removed.identifier,
                frameInRow: frame,
                appearing: false,
                usesGap: true
            )
        }
    }

    /// Where the divider's overlay sits: the gap it fills while one is moving,
    /// otherwise its slot in the row.
    private func unreadDividerOverlayFrame(
        identifier: NativeMessageTimelineItem.Identifier,
        index: Int,
        frameInRow: CGRect
    ) -> CGRect {
        if let gap = unreadDividerGap, gap.identifier == identifier {
            return CGRect(
                x: frameInRow.minX,
                y: unreadDividerGapTop,
                width: frameInRow.width,
                height: NativeTimelineUnreadDividerGapGeometry.overlayHeight(
                    gap: gap.gap, spaceHeight: gap.spaceHeight, dividerHeight: gap.dividerHeight
                )
            )
        }
        return frameInRow.offsetBy(dx: 0, dy: displayedRowOrigin(at: index))
    }

    private func beginUnreadDividerFade(
        identifier: NativeMessageTimelineItem.Identifier,
        frameInRow: CGRect,
        appearing: Bool,
        usesGap: Bool
    ) {
        guard window != nil,
              let index = items.lastIndex(where: { $0.identifier == identifier })
        else { return }
        let frame = unreadDividerOverlayFrame(identifier: identifier, index: index, frameInRow: frameInRow)
        let existing = unreadDividerFades[identifier]
        // Only a divider the reader can see is worth animating. A stale fade
        // for the same row is settled so the row simply shows its new state.
        guard usesGap || frame.intersects(visibleRect) else {
            if existing != nil { finishUnreadDividerFade(identifier) }
            return
        }
        existing?.finishTask?.cancel()
        let overlay = existing?.overlay ?? {
            let overlay = NativeTimelineUnreadDividerOverlay(frame: frame)
            addSubview(overlay, positioned: .below, relativeTo: mediaViewerHost)
            return overlay
        }()
        overlay.setArtworkSize(frameInRow.size)
        // A rapid reversal continues from the opacity on screen rather than
        // snapping to either end.
        let startOpacity = existing.map { _ in
            overlay.layer?.presentation()?.opacity ?? Float(overlay.alphaValue)
        } ?? (appearing ? 0 : 1)
        let targetOpacity: Float = appearing ? 1 : 0
        let fullDuration = NativeTimelineUnreadDividerMotion.duration(
            appearing: appearing,
            reducesMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let duration = max(0.05, fullDuration * Double(abs(targetOpacity - startOpacity)))
        unreadDividerFades[identifier] = NativeTimelineUnreadDividerFade(
            overlay: overlay,
            frameInRow: frameInRow,
            isAppearing: appearing,
            finishTask: Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(duration + 0.03))
                } catch {
                    return
                }
                self?.finishUnreadDividerFade(identifier)
            }
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.frame = frame
        overlay.alphaValue = CGFloat(targetOpacity)
        if let layer = overlay.layer {
            layer.removeAnimation(forKey: NativeTimelineUnreadDividerMotion.opacityKey)
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = startOpacity
            animation.toValue = targetOpacity
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: appearing ? .easeOut : .easeIn)
            layer.add(animation, forKey: NativeTimelineUnreadDividerMotion.opacityKey)
        }
        // While it fades in, the row's own bitmap withholds the divider.
        if appearing {
            setNeedsDisplay(rowFrame(at: index))
        }
        CATransaction.commit()
    }

    /// Ends one fade and hands the divider back to the row's own painting.
    func finishUnreadDividerFade(_ identifier: NativeMessageTimelineItem.Identifier) {
        guard let fade = unreadDividerFades.removeValue(forKey: identifier) else { return }
        fade.finishTask?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.overlay.removeFromSuperview()
        if fade.isAppearing,
           let index = items.lastIndex(where: { $0.identifier == identifier })
        {
            setNeedsDisplay(rowFrame(at: index))
            displayIfNeeded()
        }
        CATransaction.commit()
    }

    func finishUnreadDividerFades() {
        finishUnreadDividerGap()
        for identifier in Array(unreadDividerFades.keys) {
            finishUnreadDividerFade(identifier)
        }
    }

    /// Keeps a running fade attached to its row through scrolling, relayout
    /// and row changes.
    func positionUnreadDividerFades() {
        guard !unreadDividerFades.isEmpty else { return }
        for (identifier, fade) in unreadDividerFades {
            guard let index = items.lastIndex(where: { $0.identifier == identifier }),
                  layouts.indices.contains(index)
            else {
                finishUnreadDividerFade(identifier)
                continue
            }
            let frameInRow = layouts[index].unreadSeparatorFrame ?? fade.frameInRow
            let frame = unreadDividerOverlayFrame(identifier: identifier, index: index, frameInRow: frameInRow)
            fade.overlay.setArtworkSize(frameInRow.size)
            if fade.overlay.frame != frame {
                fade.overlay.frame = frame
            }
        }
    }

    /// Whether a row's own divider is withheld because a fade is bringing it
    /// in on its own layer.
    func holdsUnreadDivider(_ identifier: NativeMessageTimelineItem.Identifier) -> Bool {
        !unreadDividerFades.isEmpty && unreadDividerFades[identifier]?.isAppearing == true
    }

    /// Erases the divider the row just painted while its overlay fades in.
    func clearHeldUnreadDivider(
        for item: NativeMessageTimelineItem,
        layout: NativeTimelineRowLayout,
        rowFrame: CGRect
    ) {
        guard holdsUnreadDivider(item.identifier),
              let frame = layout.unreadSeparatorFrame,
              let context = NSGraphicsContext.current?.cgContext
        else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(frame.offsetBy(dx: rowFrame.minX, dy: rowFrame.minY))
        context.restoreGState()
    }
}

extension NativeMessageTimelineCoordinator {
    /// Reads the divider an update is about to move while rows still show it,
    /// so the motion starts from that picture. A running gap is settled first
    /// when the update could reflow rows under it. Nil when the divider does
    /// not change.
    func unreadDividerChange(
        to newParent: NativeMessageTimelineView,
        canvas: NativeTimelineCanvasView
    ) -> NativeTimelineUnreadDividerChange? {
        let previous = parent.unreadMessageID
        let changes = previous != newParent.unreadMessageID
        let reflowsRows = changes
            || newParent.rowsRevision != rowsRevision
            || newParent.presentationRevision != presentationRevision
            || newParent.conversation != parent.conversation
        guard changes else {
            if reflowsRows { canvas.finishUnreadDividerGap() }
            return nil
        }
        let change = NativeTimelineUnreadDividerChange(
            removed: canvas.unreadDividerSource(forMessageID: previous),
            added: canvas.unreadDividerSource(forMessageID: newParent.unreadMessageID),
            addedMessageID: newParent.unreadMessageID
        )
        canvas.finishUnreadDividerGap()
        return change
    }
}
