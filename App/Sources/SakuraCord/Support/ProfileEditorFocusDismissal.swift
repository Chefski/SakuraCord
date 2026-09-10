import AppKit
import SwiftUI

/// AppKit text views retain first responder when a SwiftUI background is clicked.
/// Let the clicked control act first so editing accessories can retain focus.
struct ProfileEditorFocusDismissal: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusView { FocusView() }
    func updateNSView(_ view: FocusView, context: Context) {}

    static func dismantleNSView(_ view: FocusView, coordinator: ()) { view.stopMonitoring() }

    final class FocusView: NSView {
        private var monitor: Any?
        private weak var textToBlur: NSTextView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                if event.type == .leftMouseUp {
                    let text = self?.textToBlur
                    self?.textToBlur = nil
                    DispatchQueue.main.async { [weak text] in
                        guard let text, let window = text.window, window.firstResponder === text else { return }
                        window.makeFirstResponder(nil)
                    }
                    return event
                }
                self?.textToBlur = nil
                guard let window = self?.window, event.window === window,
                      let text = window.firstResponder as? NSTextView else { return event }
                let point = text.convert(event.locationInWindow, from: nil)
                guard !text.visibleRect.contains(point) else { return event }
                // A field editor can be inset inside its text field. Clicking that
                // field's padding must still position the caret, not finish editing.
                if let field = text.delegate as? NSTextField,
                   field.bounds.contains(field.convert(event.locationInWindow, from: nil)) { return event }
                self?.textToBlur = text
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            textToBlur = nil
        }
    }
}
