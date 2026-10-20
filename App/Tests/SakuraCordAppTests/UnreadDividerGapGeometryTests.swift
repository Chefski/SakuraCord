@testable import SakuraCord
import CoreGraphics
import Testing

private typealias Geometry = NativeTimelineUnreadDividerGapGeometry

@MainActor @Test func `an opening divider gap starts closed and lands on the static layout`() {
    let start = Geometry.frame(
        isAppearing: true, spaceHeight: 29, startGap: 0, startBeforeShift: 29, progress: 0
    )
    #expect(start == .init(gap: 0, shiftBefore: 29, shiftAfter: 0))
    let end = Geometry.frame(
        isAppearing: true, spaceHeight: 29, startGap: 0, startBeforeShift: 29, progress: 1
    )
    #expect(end == .init(gap: 29, shiftBefore: 0, shiftAfter: 0))
}

@MainActor @Test func `a closing divider gap pushes later rows down until it lands`() {
    let start = Geometry.frame(
        isAppearing: false, spaceHeight: 29, startGap: 29, startBeforeShift: 0, progress: 0
    )
    #expect(start == .init(gap: 29, shiftBefore: 0, shiftAfter: 29))
    let end = Geometry.frame(
        isAppearing: false, spaceHeight: 29, startGap: 29, startBeforeShift: 0, progress: 1
    )
    #expect(end == .init(gap: 0, shiftBefore: 0, shiftAfter: 0))
}

@MainActor @Test func `reversing a divider gap continues from the space already open`() {
    // Closing was interrupted with 10 points still open, then the divider returns.
    let start = Geometry.frame(
        isAppearing: true, spaceHeight: 29, startGap: 10, startBeforeShift: 0, progress: 0
    )
    #expect(start.gap == 10)
    #expect(start.shiftAfter == -19)
    let end = Geometry.frame(
        isAppearing: true, spaceHeight: 29, startGap: 10, startBeforeShift: 0, progress: 1
    )
    #expect(end == .init(gap: 29, shiftBefore: 0, shiftAfter: 0))
}

@MainActor @Test func `the divider's space is how much its row changed`() {
    // The first message of a group loses its group spacing under the divider,
    // so the row grows by less than the divider itself.
    #expect(Geometry.spaceHeight(
        isAppearing: true, dividerHeight: 29, heightBefore: 60, heightAfter: 81
    ) == 21)
    #expect(Geometry.spaceHeight(
        isAppearing: false, dividerHeight: 29, heightBefore: 81, heightAfter: 60
    ) == 21)
    #expect(Geometry.spaceHeight(
        isAppearing: true, dividerHeight: 29, heightBefore: 60, heightAfter: 89
    ) == 29)
    // The row changed some other way, or in the wrong direction.
    #expect(Geometry.spaceHeight(
        isAppearing: true, dividerHeight: 29, heightBefore: 60, heightAfter: 120
    ) == nil)
    #expect(Geometry.spaceHeight(
        isAppearing: true, dividerHeight: 29, heightBefore: 60, heightAfter: 60
    ) == nil)
    #expect(Geometry.spaceHeight(
        isAppearing: false, dividerHeight: 29, heightBefore: 60, heightAfter: 89
    ) == nil)
}

@MainActor @Test func `an update that also scrolled the timeline is not a divider gap`() {
    #expect(Geometry.isFeasible(spaceHeight: 21, startBeforeShift: 21))
    #expect(Geometry.isFeasible(spaceHeight: 21, startBeforeShift: -21))
    #expect(!Geometry.isFeasible(spaceHeight: 21, startBeforeShift: 400))
}

@MainActor @Test func `a divider added at the bottom of a pinned timeline opens without moving rows below`() {
    // Pinned to the bottom, the viewport follows the row's growth, so rows
    // before it moved up on screen by the space and rows after it did not.
    let space: CGFloat = 21
    let shift = Geometry.startBeforeShift(
        topInViewport: 500, viewportMinY: 1000 + space, staticTop: 1500
    )
    #expect(shift == space)
    #expect(Geometry.isFeasible(spaceHeight: space, startBeforeShift: shift))
    let start = Geometry.frame(
        isAppearing: true, spaceHeight: space, startGap: 0, startBeforeShift: shift, progress: 0
    )
    #expect(start.shiftBefore == space)
    #expect(start.shiftAfter == 0)
    let end = Geometry.frame(
        isAppearing: true, spaceHeight: space, startGap: 0, startBeforeShift: shift, progress: 1
    )
    #expect(end.shiftBefore == 0 && end.shiftAfter == 0)
}

@MainActor @Test func `the divider shows only down to the message below its gap`() {
    #expect(Geometry.overlayHeight(gap: 0, spaceHeight: 21, dividerHeight: 29) == 8)
    #expect(Geometry.overlayHeight(gap: 21, spaceHeight: 21, dividerHeight: 29) == 29)
    #expect(Geometry.overlayHeight(gap: 10, spaceHeight: 29, dividerHeight: 29) == 10)
}

@MainActor @Test func `rows before the divider start where they were on screen`() {
    let shift = Geometry.startBeforeShift(topInViewport: 120, viewportMinY: 1000, staticTop: 1091)
    #expect(shift == 29)
}
