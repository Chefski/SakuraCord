import AppKit

/// Geometry of the NEW divider's space opening or closing in place.
///
/// The divider is the top `spaceHeight` of its row, so the static layout
/// already holds its final size. The motion displaces rows instead of laying
/// them out again: rows before the divider's row move by `shiftBefore`, and the
/// row itself and everything after it by `shiftAfter`. `gap` is how much of the
/// divider's space is open on screen. Both shifts reach zero when the motion
/// ends, so it finishes exactly on the static layout.
nonisolated enum NativeTimelineUnreadDividerGapGeometry {
    nonisolated struct Frame: Equatable {
        let gap: CGFloat
        let shiftBefore: CGFloat
        let shiftAfter: CGFloat
    }

    /// The gap, and the shifts that put every row where it was on screen when
    /// `progress` is zero and on the static layout when it is one.
    static func frame(
        isAppearing: Bool,
        spaceHeight: CGFloat,
        startGap: CGFloat,
        startBeforeShift: CGFloat,
        progress: CGFloat
    ) -> Frame {
        // The static layout holds the divider's space only while it exists.
        let staticGap = isAppearing ? spaceHeight : 0
        let gap = startGap + (staticGap - startGap) * progress
        let before = startBeforeShift * (1 - progress)
        return Frame(gap: gap, shiftBefore: before, shiftAfter: before + gap - staticGap)
    }

    /// How far rows before the divider must still be displaced for the
    /// picture to match what was on screen before the update.
    static func startBeforeShift(
        topInViewport: CGFloat,
        viewportMinY: CGFloat,
        staticTop: CGFloat
    ) -> CGFloat {
        topInViewport + viewportMinY - staticTop
    }

    /// The space the divider opens or closes: how much its row grew or shrank.
    /// That is less than the divider itself when the divider replaces the
    /// spacing a message normally has above it. Nil when the row changed in
    /// any other way, so the motion would not describe the update.
    static func spaceHeight(
        isAppearing: Bool,
        dividerHeight: CGFloat,
        heightBefore: CGFloat,
        heightAfter: CGFloat
    ) -> CGFloat? {
        let change = (heightAfter - heightBefore) * (isAppearing ? 1 : -1)
        return change > 0.5 && change <= dividerHeight + 0.5 ? change : nil
    }

    /// The update must not have scrolled the timeline by more than the space.
    static func isFeasible(spaceHeight: CGFloat, startBeforeShift: CGFloat) -> Bool {
        abs(startBeforeShift) <= spaceHeight + 1
    }

    /// The part of the divider that may show: from the top of the gap down to
    /// the top of the message below, which sits `dividerHeight - spaceHeight`
    /// under the open gap.
    static func overlayHeight(gap: CGFloat, spaceHeight: CGFloat, dividerHeight: CGFloat) -> CGFloat {
        min(dividerHeight, max(0, gap + dividerHeight - spaceHeight))
    }
}

/// An in-flight opening or closing of the divider's space.
struct NativeTimelineUnreadDividerGap {
    let identifier: NativeMessageTimelineItem.Identifier
    let isAppearing: Bool
    let spaceHeight: CGFloat
    let dividerHeight: CGFloat
    let startGap: CGFloat
    let startBeforeShift: CGFloat
    var rowIndex: Int
    var startUptime: TimeInterval?
    var gap: CGFloat
    var shiftBefore: CGFloat
    var shiftAfter: CGFloat
}

extension NativeTimelineCanvasView {
    /// The top of the divider's gap in canvas coordinates. Rows before it are
    /// displaced by `shiftBefore`, so this is where the gap really starts.
    var unreadDividerGapTop: CGFloat {
        guard let gap = unreadDividerGap, rowOrigins.indices.contains(gap.rowIndex) else { return 0 }
        return contentOriginY + rowOrigins[gap.rowIndex] + gap.shiftBefore
    }

    /// Displacement of a row by the running gap motion.
    func unreadDividerGapShift(at index: Int) -> CGFloat {
        guard let gap = unreadDividerGap else { return 0 }
        return index < gap.rowIndex ? gap.shiftBefore : gap.shiftAfter
    }

    /// The divider's own row never draws above its gap while it slides in.
    func unreadDividerGapSpan(at index: Int, minY: CGFloat, maxY: CGFloat) -> Range<CGFloat> {
        guard unreadDividerGap?.rowIndex == index else { return minY ..< maxY }
        let top = unreadDividerGapTop
        return max(top, minY) ..< max(top, maxY)
    }

    func drawTimelineRowClippedToUnreadDividerGap(
        at index: Int,
        rowFrame: CGRect,
        dirtyRect: CGRect,
        visibleMediaKeys: [NativeMessageTimelineItem.Identifier: Set<NativeTimelineMediaKey>]
    ) {
        let top = unreadDividerGapTop
        guard unreadDividerGap?.rowIndex == index,
              rowFrame.minY < top,
              let context = NSGraphicsContext.current?.cgContext
        else {
            drawTimelineRow(at: index, rowFrame: rowFrame, dirtyRect: dirtyRect, visibleMediaKeys: visibleMediaKeys)
            return
        }
        guard top < rowFrame.maxY else { return }
        context.saveGState()
        context.clip(to: CGRect(x: rowFrame.minX, y: top, width: rowFrame.width, height: rowFrame.maxY - top))
        drawTimelineRow(at: index, rowFrame: rowFrame, dirtyRect: dirtyRect, visibleMediaKeys: visibleMediaKeys)
        context.restoreGState()
    }

    /// Starts the divider's space opening or closing from the picture on
    /// screen before the update. Returns false when the change must apply
    /// instantly: Reduce Motion, another motion running, the divider off
    /// screen, a row that is new, or an update that moved more than the
    /// divider's own space.
    func beginUnreadDividerGap(
        from source: NativeTimelineUnreadDividerSource,
        appearing: Bool
    ) -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              window != nil,
              rowDisclosure == nil,
              sendTransitions.isEmpty,
              !isTranscriptGliding,
              editingRowIndex == nil,
              let index = items.lastIndex(where: { $0.identifier == source.identifier }),
              layouts.indices.contains(index),
              rowOrigins.indices.contains(index)
        else { return false }
        let layout = layouts[index]
        // A row with a date separator above the divider keeps it in place
        // while the rest moves; that cannot be split out of one bitmap.
        guard let frame = appearing ? layout.unreadSeparatorFrame : source.frameInRow,
              abs(frame.minY) < 0.5,
              appearing == (layout.unreadSeparatorFrame != nil)
        else { return false }
        guard let space = NativeTimelineUnreadDividerGapGeometry.spaceHeight(
            isAppearing: appearing,
            dividerHeight: frame.height,
            heightBefore: source.height,
            heightAfter: layout.height
        ) else { return false }
        let startGap = source.startGap ?? (appearing ? 0 : space)
        let staticTop = contentOriginY + rowOrigins[index]
        let startShift = NativeTimelineUnreadDividerGapGeometry.startBeforeShift(
            topInViewport: source.topInViewport,
            viewportMinY: viewportMinY,
            staticTop: staticTop
        )
        guard NativeTimelineUnreadDividerGapGeometry.isFeasible(spaceHeight: space, startBeforeShift: startShift),
              CGRect(x: 0, y: staticTop - space, width: 1, height: space * 3).intersects(visibleRect)
        else { return false }
        let start = NativeTimelineUnreadDividerGapGeometry.frame(
            isAppearing: appearing,
            spaceHeight: space,
            startGap: startGap,
            startBeforeShift: startShift,
            progress: 0
        )
        unreadDividerGap = NativeTimelineUnreadDividerGap(
            identifier: source.identifier,
            isAppearing: appearing,
            spaceHeight: space,
            dividerHeight: frame.height,
            startGap: startGap,
            startBeforeShift: startShift,
            rowIndex: index,
            gap: start.gap,
            shiftBefore: start.shiftBefore,
            shiftAfter: start.shiftAfter
        )
        unreadDividerGapTicker.start(on: self) { [weak self] in self?.stepUnreadDividerGap() }
        redrawForDisclosure()
        return true
    }

    private func stepUnreadDividerGap() {
        guard var gap = unreadDividerGap else {
            unreadDividerGapTicker.stop()
            return
        }
        let index: Int
        if items.indices.contains(gap.rowIndex), items[gap.rowIndex].identifier == gap.identifier {
            index = gap.rowIndex
        } else if let found = items.lastIndex(where: { $0.identifier == gap.identifier }) {
            index = found
        } else {
            finishUnreadDividerGap()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let start = gap.startUptime ?? now
        gap.startUptime = start
        let progress = NativeTimelineRowDisclosure.progress(at: now - start)
        let frame = NativeTimelineUnreadDividerGapGeometry.frame(
            isAppearing: gap.isAppearing,
            spaceHeight: gap.spaceHeight,
            startGap: gap.startGap,
            startBeforeShift: gap.startBeforeShift,
            progress: progress
        )
        gap.rowIndex = index
        gap.gap = frame.gap
        gap.shiftBefore = frame.shiftBefore
        gap.shiftAfter = frame.shiftAfter
        unreadDividerGap = gap
        if progress >= 1 {
            finishUnreadDividerGap()
        } else {
            redrawForDisclosure()
        }
    }

    /// Lands on the static layout. The divider on the gap's overlay goes with
    /// it: the row paints it again once it opens, and a fading one has
    /// nowhere left to be. Not when it is about to return on `identifier`,
    /// where it carries on from its current opacity.
    func finishUnreadDividerGap(preservingFadeFor identifier: NativeMessageTimelineItem.Identifier? = nil) {
        unreadDividerGapTicker.stop()
        guard let gap = unreadDividerGap else { return }
        unreadDividerGap = nil
        if gap.identifier != identifier {
            finishUnreadDividerFade(gap.identifier)
        }
        redrawForDisclosure()
    }
}
