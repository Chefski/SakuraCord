import AppKit
import SwiftUI

@MainActor
final class PopoverEscapeKeyRegistration {
    fileprivate weak var popoverWindow: NSWindow?
    fileprivate weak var presentingWindow: NSWindow?
    fileprivate var dismiss: () -> Void

    fileprivate init(
        popoverWindow: NSWindow,
        presentingWindow: NSWindow?,
        dismiss: @escaping () -> Void
    ) {
        self.popoverWindow = popoverWindow
        self.presentingWindow = presentingWindow
        self.dismiss = dismiss
    }

    func update(
        popoverWindow: NSWindow,
        presentingWindow: NSWindow?,
        dismiss: @escaping () -> Void
    ) {
        self.popoverWindow = popoverWindow
        self.presentingWindow = presentingWindow
        self.dismiss = dismiss
    }

    fileprivate func matches(_ window: NSWindow) -> Bool {
        window === popoverWindow || window === presentingWindow
    }
}

@MainActor
final class PopoverEscapeKeyCoordinator {
    static let shared = PopoverEscapeKeyCoordinator()

    private final class WeakRegistration {
        weak var value: PopoverEscapeKeyRegistration?

        init(_ value: PopoverEscapeKeyRegistration) {
            self.value = value
        }
    }

    private var registrations: [WeakRegistration] = []
    private var eventMonitor: Any?
    private let installsEventMonitor: Bool

    init(installsEventMonitor: Bool = true) {
        self.installsEventMonitor = installsEventMonitor
    }

    func register(
        popoverWindow: NSWindow,
        presentingWindow: NSWindow?,
        dismiss: @escaping () -> Void
    ) -> PopoverEscapeKeyRegistration {
        if installsEventMonitor {
            prioritizeEventMonitor()
        }
        let registration = PopoverEscapeKeyRegistration(
            popoverWindow: popoverWindow,
            presentingWindow: presentingWindow,
            dismiss: dismiss
        )
        registrations.append(WeakRegistration(registration))
        return registration
    }

    private func prioritizeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53,
              let eventWindow = event.window ?? NSApp.keyWindow
        else { return event }

        return dismissTopmostPopover(in: eventWindow) ? nil : event
    }

    @discardableResult
    func dismissTopmostPopover(in eventWindow: NSWindow) -> Bool {
        registrations.removeAll { $0.value == nil }
        guard let registration = registrations.reversed().compactMap(\.value).first(where: {
            $0.matches(eventWindow)
        }) else { return false }

        registration.dismiss()
        return true
    }
}

private struct PopoverEscapeKeyReader: NSViewRepresentable {
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeNSView(context: Context) -> PopoverEscapeTrackingView {
        let view = PopoverEscapeTrackingView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.update(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: PopoverEscapeTrackingView, context: Context) {
        context.coordinator.dismiss = dismiss
        context.coordinator.update(window: nsView.window)
    }

    static func dismantleNSView(
        _ nsView: PopoverEscapeTrackingView,
        coordinator: Coordinator
    ) {
        nsView.windowDidChange = nil
        coordinator.registration = nil
    }

    @MainActor
    final class Coordinator {
        var dismiss: () -> Void
        var registration: PopoverEscapeKeyRegistration?

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        func update(window: NSWindow?) {
            guard let window else {
                registration = nil
                return
            }
            if let registration {
                registration.update(
                    popoverWindow: window,
                    presentingWindow: window.parent,
                    dismiss: dismiss
                )
            } else {
                registration = PopoverEscapeKeyCoordinator.shared.register(
                    popoverWindow: window,
                    presentingWindow: window.parent,
                    dismiss: dismiss
                )
            }
        }
    }
}

private final class PopoverEscapeTrackingView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension View {
    func escapeDismissiblePopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        popover(
            isPresented: isPresented,
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge
        ) {
            content()
                .background {
                    PopoverEscapeKeyReader {
                        isPresented.wrappedValue = false
                    }
                    .frame(width: 0, height: 0)
                }
        }
    }

    func escapeDismissiblePopover<Item: Identifiable, PopoverContent: View>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping (Item) -> PopoverContent
    ) -> some View {
        popover(
            item: item,
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge
        ) { value in
            content(value)
                .background {
                    PopoverEscapeKeyReader {
                        item.wrappedValue = nil
                    }
                    .frame(width: 0, height: 0)
                }
        }
    }
}
