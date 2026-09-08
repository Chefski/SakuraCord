import AppKit
import SwiftUI

/// Reports whether any part of this view's window is on screen, independently
/// of keyboard focus. The observer follows the view when its window changes.
struct WindowVisibilityReader: NSViewRepresentable {
    var changed: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView(frame: .zero)
        view.changed = changed
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.changed = changed
    }

    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) {
        view.detach()
    }

    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        private var observer: NotificationCenter.ObservationToken?
        private var lastVisibility: Bool?
        private var reportTask: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            if let window {
                observer = NotificationCenter.default.addObserver(
                    of: window,
                    for: NSWindow.DidChangeOcclusionStateMessage.self
                ) { [weak self] _ in
                    self?.scheduleReport()
                }
            }
            scheduleReport()
        }

        private func scheduleReport() {
            reportTask?.cancel()
            // Window attachment can occur during a SwiftUI update. Publish on
            // the next actor turn, reading the current window rather than a
            // captured visibility value that may already be stale.
            reportTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self else { return }
                let visible = window?.occlusionState.contains(.visible) == true
                guard lastVisibility != visible else { return }
                lastVisibility = visible
                changed?(visible)
            }
        }

        func detach() {
            reportTask?.cancel()
            reportTask = nil
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }
    }
}
