import AppKit
@testable import SakuraCord
import SwiftUI
import Testing

/// A side chat pane's measured widths are shared with the next pane. A
/// full-width side chat has none of its own: when it measured first, the
/// next pane took the whole window, drawing its content in a narrow column
/// at the leading edge over nothing.
@MainActor
@Test(arguments: [false, true])
func `a side chat pane keeps its own width after a full-width side chat`(flipsInPlace: Bool) {
    // Heights no other test uses: measured widths are shared per height.
    let height: CGFloat = flipsInPlace ? 731 : 733
    let host = WorkspaceColumnsView(frame: NSRect(x: 0, y: 0, width: 1440, height: height))
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    defer { window.contentView = nil }
    let environment = EnvironmentValues()

    if flipsInPlace {
        // The same side chat moves to full width, the window's height
        // changes, and it comes back to the pane.
        host.apply(spec([column(fullWidth: false)]), environment: environment, animates: false)
        host.apply(spec([column(fullWidth: true)]), environment: environment, animates: false)
        window.setContentSize(NSSize(width: 1440, height: height + 40))
        host.layoutSubtreeIfNeeded()
        host.apply(spec([column(fullWidth: false)]), environment: environment, animates: false)
    } else {
        // Full width first, then the parent channel, then a pane.
        host.apply(spec([column(fullWidth: true)]), environment: environment, animates: false)
        host.apply(spec([]), environment: environment, animates: false)
        host.apply(spec([column(fullWidth: false)]), environment: environment, animates: false)
    }
    host.layoutSubtreeIfNeeded()

    let conversation = try? #require(host.subviews.first)
    let pane = try? #require(host.subviews.last)
    #expect(conversation?.alphaValue == 1)
    #expect(pane?.frame.width == paneWidth, "pane \(String(describing: pane?.frame))")
    #expect(pane?.frame.maxX == host.bounds.maxX)
    #expect(conversation?.frame.width == host.bounds.width - paneWidth)
}

private let paneWidth: CGFloat = 440

@MainActor
private func spec(_ columns: [WorkspaceColumnsHost.Column]) -> WorkspaceColumnsHost {
    WorkspaceColumnsHost(
        conversation: AnyView(Color.clear.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)),
        columns: columns,
        widening: nil,
        supplementaryPaneFrameChanged: { _ in }
    )
}

@MainActor
private func column(fullWidth: Bool) -> WorkspaceColumnsHost.Column {
    WorkspaceColumnsHost.Column(
        id: "side-thread-regression",
        isSideConversation: true,
        isFullWidth: fullWidth,
        isDeparting: false,
        content: fullWidth
            ? AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))
            : AnyView(Color.clear.frame(minWidth: 340, idealWidth: paneWidth, maxWidth: paneWidth, maxHeight: .infinity))
    )
}
