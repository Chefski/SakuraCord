import AppKit

/// Sheets must finish before their popover's hosting window is released.
@MainActor
enum PopoverSheetLifecycle {
    static func hasSheet(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        return !window.sheets.isEmpty
            || (window.childWindows ?? []).contains { hasSheet(in: $0) }
    }

    static func cancelSheets(in window: NSWindow?) {
        guard let window else { return }
        // Include nested popovers, whose sheets also depend on this host.
        for child in window.childWindows ?? [] { cancelSheets(in: child) }
        for sheet in window.sheets {
            window.endSheet(sheet, returnCode: .cancel)
            sheet.orderOut(nil)
        }
    }
}
