import AppKit
@testable import SakuraCord
import Testing

@MainActor
@Test func `escape dismissal targets the topmost matching popover`() {
    let coordinator = PopoverEscapeKeyCoordinator(installsEventMonitor: false)
    let presentingWindow = makePopoverTestWindow()
    let outerPopoverWindow = makePopoverTestWindow()
    let nestedPopoverWindow = makePopoverTestWindow()
    let unrelatedWindow = makePopoverTestWindow()
    var dismissals: [String] = []

    let outerRegistration = coordinator.register(
        popoverWindow: outerPopoverWindow,
        presentingWindow: presentingWindow,
        dismiss: { dismissals.append("outer") }
    )
    let nestedRegistration = coordinator.register(
        popoverWindow: nestedPopoverWindow,
        presentingWindow: outerPopoverWindow,
        dismiss: { dismissals.append("nested") }
    )

    withExtendedLifetime((outerRegistration, nestedRegistration)) {
        #expect(coordinator.dismissTopmostPopover(in: outerPopoverWindow))
        #expect(dismissals == ["nested"])
        #expect(coordinator.dismissTopmostPopover(in: presentingWindow))
        #expect(dismissals == ["nested", "outer"])
        #expect(!coordinator.dismissTopmostPopover(in: unrelatedWindow))
    }
}

@MainActor
private func makePopoverTestWindow() -> NSWindow {
    NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
}
