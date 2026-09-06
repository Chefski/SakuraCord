import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// A distinct content type keeps game-row drop targets from consuming a drag of
// the surrounding widget before the board can receive it.
nonisolated struct ProfileWidgetDragPayload: Codable, Transferable {
    let id: String
    static let contentType = UTType(exportedAs: "dev.sakuracord.profile-widget", conformingTo: .data)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}

/// Native Menu starts tracking on mouse-down, before SwiftUI can start a drag.
/// Delay menu tracking until mouse-up; SwiftUI still owns the board's drop and
/// draft update.
struct ProfileWidgetDragMenuButton: NSViewRepresentable {
    let id: String
    let title: String
    let isEnabled: Bool
    let remove: () -> Void

    func makeNSView(context: Context) -> DragMenuButton { DragMenuButton() }

    func updateNSView(_ button: DragMenuButton, context: Context) {
        button.widgetID = id
        button.removeWidget = remove
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(String(localized: "Manage widget: \(title)", bundle: #bundle))
    }

    final class DragMenuButton: NSButton, NSDraggingSource {
        var widgetID = ""
        var removeWidget: (() -> Void)?
        private var pressOrigin: NSPoint?

        init() {
            super.init(frame: .zero)
            image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            imagePosition = .imageOnly
            isBordered = false
            contentTintColor = .secondaryLabelColor
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(showMenu)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            pressOrigin = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard isEnabled, let pressOrigin,
                  hypot(event.locationInWindow.x - pressOrigin.x, event.locationInWindow.y - pressOrigin.y) >= 4,
                  let data = try? JSONEncoder().encode(ProfileWidgetDragPayload(id: widgetID)) else { return }
            self.pressOrigin = nil
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(ProfileWidgetDragPayload.contentType.identifier))
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            draggingItem.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            guard pressOrigin != nil else { return }
            pressOrigin = nil
            if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { performClick(nil) }
        }

        override func rightMouseDown(with event: NSEvent) {
            if isEnabled { performClick(nil) }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        @objc private func showMenu() {
            guard isEnabled else { return }
            let menu = NSMenu()
            let title = String(localized: "Remove Widget", bundle: #bundle)
            let item = NSMenuItem(title: title, action: #selector(remove), keyEquivalent: "")
            item.target = self
            ContextMenuItemSupport.configure(item, title: title, systemImage: "trash", isDestructive: true)
            menu.addItem(item)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
        }

        @objc private func remove() {
            if isEnabled { removeWidget?() }
        }
    }
}
