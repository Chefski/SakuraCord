import AppKit
import SwiftUI

/// The right-click menu of a server folder, hosted like the server menu so a
/// left click still reaches the folder's button.
struct ServerFolderContextMenuBridge: NSViewRepresentable {
    let isUnread: Bool
    let markRead: () -> Void
    let openSettings: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ServerContextMenuHitView {
        let view = ServerContextMenuHitView()
        view.menuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeMenu()
        }
        return view
    }

    func updateNSView(_ nsView: ServerContextMenuHitView, context: Context) {
        context.coordinator.bridge = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var bridge: ServerFolderContextMenuBridge

        init(_ bridge: ServerFolderContextMenuBridge) {
            self.bridge = bridge
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(menuItem(
                "Mark Folder as Read",
                systemImage: "envelope.open.fill",
                action: #selector(markReadFromMenu),
                isEnabled: bridge.isUnread
            ))
            menu.addItem(.separator())
            menu.addItem(menuItem(
                "Folder Settings",
                systemImage: "folder.fill.badge.gearshape",
                action: #selector(openSettingsFromMenu)
            ))
            return menu
        }

        private func menuItem(
            _ title: String,
            systemImage: String,
            action: Selector,
            isEnabled: Bool = true
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = isEnabled
            ContextMenuItemSupport.configure(item, title: title, systemImage: systemImage)
            return item
        }

        @objc private func markReadFromMenu() {
            bridge.markRead()
        }

        @objc private func openSettingsFromMenu() {
            bridge.openSettings()
        }
    }
}
