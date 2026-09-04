import AppKit
import CoreText
import OSLog
import SakuraCordModels
import SwiftUI

struct NativeMemberListView: NSViewRepresentable {
    let sections: [MemberSection]
    let customEmojiURLsByID: [String: URL]
    let profilePresentation: ProfilePresentationState?
    let isProfilePresented: Bool
    let interactionsBlocked: Bool
    let selectMember: (Member) -> Void
    let dismissProfile: () -> Void
    let runsPerformanceAutoScroll: Bool
    let viewportIdentity: ChannelID?
    var presentation = NativeMemberListPresentation()
    var onViewportRange: (ClosedRange<Int>) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self, scrollView: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView as? NativeMemberListScrollView)?
            .inputPerformanceProbe.invalidate()
        coordinator.stop()
        scrollView.documentView = nil
    }

    typealias Coordinator = NativeMemberListCoordinator
}

@MainActor
final class NativeMemberListScrollView: NSScrollView {
    let inputPerformanceProbe = ScrollInputPerformanceProbe(
        surface: .memberList
    )

    override func layout() {
        super.layout()
        synchronizeCanvasFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundForEffectiveAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundForEffectiveAppearance()
    }

    private func updateBackgroundForEffectiveAppearance() {
        backgroundColor = .clear
        needsDisplay = true
        contentView.needsDisplay = true
        documentView?.needsDisplay = true
    }

    func synchronizeCanvasFrame() {
        guard let canvas = documentView as? NativeMemberListCanvasView else { return }
        let targetSize = NSSize(
            width: max(0, contentSize.width),
            height: max(1, canvas.contentHeight)
        )
        guard canvas.frame.size != targetSize else { return }
        canvas.frame.size = targetSize
        canvas.needsDisplay = true
        canvas.updateVisibleOverlaysAndPrewarming(force: true)
    }
}
