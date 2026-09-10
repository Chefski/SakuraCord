import SwiftUI

@MainActor
final class StablePopoverHostingController<Content: View>: NSHostingController<Content> {
    private let dismiss: () -> Void
    private var escapeKeyRegistration: PopoverEscapeKeyRegistration?

    init(rootView: Content, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func monitorEscapeKey(
        in popoverWindow: NSWindow?,
        presentingWindow: NSWindow?
    ) {
        guard let popoverWindow else { return }
        if let escapeKeyRegistration {
            escapeKeyRegistration.update(
                popoverWindow: popoverWindow,
                presentingWindow: presentingWindow,
                dismiss: dismiss
            )
        } else {
            escapeKeyRegistration = PopoverEscapeKeyCoordinator.shared.register(
                popoverWindow: popoverWindow,
                presentingWindow: presentingWindow,
                dismiss: dismiss
            )
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        stopMonitoringEscapeKey()
    }

    func stopMonitoringEscapeKey() {
        escapeKeyRegistration = nil
    }
}
