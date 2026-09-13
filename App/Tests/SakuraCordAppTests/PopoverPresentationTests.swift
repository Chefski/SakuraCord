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
    var nestedRegistration: PopoverEscapeKeyRegistration? = coordinator.register(
        popoverWindow: nestedPopoverWindow,
        presentingWindow: outerPopoverWindow,
        dismiss: { dismissals.append("nested") }
    )

    withExtendedLifetime(outerRegistration) {
        withExtendedLifetime(nestedRegistration) {
            for window in [nestedPopoverWindow, outerPopoverWindow, presentingWindow] {
                #expect(coordinator.dismissTopmostPopover(in: window))
            }
            #expect(dismissals == ["nested", "nested", "nested"])
        }
        // The host unregisters when the topmost popover closes. Only the next
        // key press may reach its parent, regardless of the event's window.
        nestedRegistration = nil
        dismissals = []
        #expect(coordinator.dismissTopmostPopover(in: presentingWindow))
        #expect(dismissals == ["outer"])
        #expect(!coordinator.dismissTopmostPopover(in: unrelatedWindow))
    }
}

@MainActor
@Test func `a nested popover alert keeps its hosts alive and forced teardown ends the sheet`() async {
    let coordinator = PopoverEscapeKeyCoordinator(installsEventMonitor: false)
    let presentingWindow = makePopoverTestWindow()
    let outerPopoverWindow = makePopoverTestWindow()
    let nestedPopoverWindow = makePopoverTestWindow()
    let sheet = makePopoverTestWindow()
    presentingWindow.addChildWindow(outerPopoverWindow, ordered: .above)
    outerPopoverWindow.addChildWindow(nestedPopoverWindow, ordered: .above)
    defer {
        outerPopoverWindow.removeChildWindow(nestedPopoverWindow)
        presentingWindow.removeChildWindow(outerPopoverWindow)
    }
    var dismissals = 0
    let registration = coordinator.register(popoverWindow: nestedPopoverWindow, presentingWindow: outerPopoverWindow) {
        dismissals += 1
    }

    let response = await withCheckedContinuation { continuation in
        nestedPopoverWindow.beginSheet(sheet) { continuation.resume(returning: $0) }
        #expect(PopoverSheetLifecycle.hasSheet(in: presentingWindow))
        #expect(!coordinator.dismissTopmostPopover(in: sheet))
        #expect(!coordinator.dismissTopmostPopover(in: nestedPopoverWindow))
        #expect(!coordinator.dismissTopmostPopover(in: outerPopoverWindow))
        #expect(dismissals == 0)
        PopoverSheetLifecycle.cancelSheets(in: outerPopoverWindow)
    }

    withExtendedLifetime(registration) {
        #expect(response == .cancel)
        #expect(sheet.sheetParent == nil)
        #expect(!PopoverSheetLifecycle.hasSheet(in: presentingWindow))
        #expect(coordinator.dismissTopmostPopover(in: outerPopoverWindow))
        #expect(dismissals == 1)
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
