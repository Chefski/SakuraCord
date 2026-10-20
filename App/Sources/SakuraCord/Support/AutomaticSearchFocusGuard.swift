import AppKit

/// Replacing the workspace while switching accounts can leave the toolbar
/// search field as the window's only text input, and macOS then focuses it,
/// opening its suggestions. Armed for a switch, the guard reports focus the
/// reader did not give; their next click or key press disarms it.
@MainActor
final class AutomaticSearchFocusGuard {
    private var monitor: Any?

    var isArmed: Bool { monitor != nil }

    func arm() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.disarm()
            return event
        }
    }

    /// Returns the key window's focus from a search field's editor.
    func releaseSearchFieldFocus() {
        guard let window = NSApp.keyWindow,
              let editor = window.firstResponder as? NSText,
              editor.delegate is NSSearchField
        else { return }
        window.makeFirstResponder(nil)
    }

    func disarm() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
