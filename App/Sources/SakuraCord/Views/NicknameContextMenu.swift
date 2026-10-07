import AppKit

/// AppKit items for nickname actions, shared by the member list, message
/// author and direct-message context menus.
enum NicknameContextMenu {
    static func items(for actions: [NicknameMenuAction]) -> [NSMenuItem] {
        actions.map { action in
            let target = NativeTimelineMenuAction(action.perform)
            let item = NSMenuItem(title: action.title, action: #selector(NativeTimelineMenuAction.performAction), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            item.isEnabled = true
            ContextMenuItemSupport.configure(item, title: action.title, systemImage: action.systemImage)
            return item
        }
    }

    static func menu(for actions: [NicknameMenuAction]) -> NSMenu? {
        guard !actions.isEmpty else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        items(for: actions).forEach(menu.addItem)
        return menu
    }
}
