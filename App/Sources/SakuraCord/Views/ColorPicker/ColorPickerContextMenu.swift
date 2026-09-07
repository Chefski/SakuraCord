import AppKit
import SwiftUI

// Keep the theme designer’s native right-click hit testing and menu behavior.
struct ColorPickerContextMenuBridge: NSViewRepresentable {
    let canInputColor: Bool
    let canRemoveColor: Bool
    let input: () -> Void
    let remove: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(bridge: self) }

    func makeNSView(context: Context) -> MediaImageContextMenuHitView {
        let view = MediaImageContextMenuHitView()
        view.menuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeMenu()
        }
        return view
    }

    func updateNSView(_ nsView: MediaImageContextMenuHitView, context: Context) {
        context.coordinator.bridge = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var bridge: ColorPickerContextMenuBridge

        init(bridge: ColorPickerContextMenuBridge) { self.bridge = bridge }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(item(
                String(localized: "Input Hex Code…", bundle: #bundle),
                image: "number",
                action: #selector(inputHexCode),
                isEnabled: bridge.canInputColor
            ))
            if bridge.canRemoveColor, bridge.remove != nil {
                menu.addItem(.separator())
                menu.addItem(item(
                    String(localized: "Remove Color", bundle: #bundle),
                    image: "trash",
                    action: #selector(removeColor),
                    isEnabled: bridge.canRemoveColor,
                    isDestructive: true
                ))
            }
            return menu
        }

        private func item(
            _ title: String,
            image: String,
            action: Selector,
            isEnabled: Bool,
            isDestructive: Bool = false
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = isEnabled
            ContextMenuItemSupport.configure(item, title: title, systemImage: image, isDestructive: isDestructive)
            return item
        }

        @objc private func inputHexCode() {
            guard bridge.canInputColor else { return }
            bridge.input()
        }

        @objc private func removeColor() {
            guard bridge.canRemoveColor else { return }
            bridge.remove?()
        }
    }
}
