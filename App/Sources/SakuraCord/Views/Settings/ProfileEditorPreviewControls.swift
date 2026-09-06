import AppKit
import SakuraCordModels
import SwiftUI

struct ProfileEditorImageMenu: ViewModifier {
    enum Target { case avatar, banner }

    let editor: ProfileEditorState?
    let target: Target
    let open: ((ProfileEditorPicker) -> Void)?
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if let editor, let open {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.regularMaterial, in: .circle)
                        .padding(target == .banner ? 12 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: target == .avatar ? .center : .topTrailing)
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(false)
                    ProfileImageMenuButton(editor: editor, target: target, open: open)
                }
            }
            .onHover { isHovered = $0 }
    }
}

/// AppKit owns menu tracking only. Keeping the transparent button above the
/// SwiftUI artwork avoids NSMenu's restricted label rendering on macOS.
private struct ProfileImageMenuButton: NSViewRepresentable {
    let editor: ProfileEditorState
    let target: ProfileEditorImageMenu.Target
    let open: (ProfileEditorPicker) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor, target: target, open: open) }

    func makeNSView(context: Context) -> MenuButton {
        let button = MenuButton(title: "", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.isBordered = false
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .exterior
        return button
    }

    func updateNSView(_ button: MenuButton, context: Context) {
        context.coordinator.editor = editor
        context.coordinator.target = target
        context.coordinator.open = open
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(target == .avatar ? String(localized: "Edit Avatar and Decoration", bundle: #bundle) : String(localized: "Edit Banner and Effect", bundle: #bundle))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MenuButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    final class MenuButton: NSButton {
        override func rightMouseDown(with event: NSEvent) { performClick(nil) }
    }

    final class Coordinator: NSObject {
        var editor: ProfileEditorState
        var target: ProfileEditorImageMenu.Target
        var open: (ProfileEditorPicker) -> Void
        private var actions: [() -> Void] = []

        init(editor: ProfileEditorState, target: ProfileEditorImageMenu.Target, open: @escaping (ProfileEditorPicker) -> Void) {
            self.editor = editor
            self.target = target
            self.open = open
        }

        @objc func showMenu(_ sender: NSButton) {
            guard sender.isEnabled, !editor.isSaving, !editor.requiresReload else { return }
            actions.removeAll()
            let menu = NSMenu()
            switch target {
            case .avatar:
                add(String(localized: "Change Avatar", bundle: #bundle), to: menu) { [open] in open(.avatar) }
                add(String(localized: "Change Avatar Decoration", bundle: #bundle), to: menu) { [open] in open(.collectible(.avatarDecoration)) }
                if editor.hasAvatarSelection || editor.selectedCollectibleID(.avatarDecoration) != nil { menu.addItem(.separator()) }
                if editor.hasAvatarSelection {
                    add(editor.avatarRemovalTitle, to: menu, destructive: true) { [editor] in editor.setAvatar(nil) }
                }
                if editor.selectedCollectibleID(.avatarDecoration) != nil {
                    add(editor.collectibleRemovalTitle(.avatarDecoration), to: menu, destructive: true) { [editor] in editor.setCollectible(nil, kind: .avatarDecoration) }
                }
            case .banner:
                add(String(localized: "Change Banner", bundle: #bundle), to: menu) { [open] in open(.banner) }
                add(String(localized: "Change Profile Effect", bundle: #bundle), to: menu) { [open] in open(.collectible(.effect)) }
                add(String(localized: "Change Profile Frame", bundle: #bundle), to: menu) { [open] in open(.collectible(.frame)) }
                if editor.hasBannerSelection || editor.selectedCollectibleID(.effect) != nil || editor.selectedCollectibleID(.frame) != nil { menu.addItem(.separator()) }
                if editor.hasBannerSelection {
                    add(editor.bannerRemovalTitle, to: menu, destructive: true) { [editor] in editor.setBanner(nil) }
                }
                for kind in [ProfileCollectibleKind.effect, .frame] where editor.selectedCollectibleID(kind) != nil {
                    add(editor.collectibleRemovalTitle(kind), to: menu, destructive: true) { [editor] in editor.setCollectible(nil, kind: kind) }
                }
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
            actions.removeAll()
        }

        private func add(_ title: String, to menu: NSMenu, destructive: Bool = false, action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(activate(_:)), keyEquivalent: "")
            item.target = self
            item.tag = actions.count
            if destructive { ContextMenuItemSupport.configure(item, title: title, systemImage: "trash", isDestructive: true) }
            actions.append(action)
            menu.addItem(item)
        }

        @objc private func activate(_ item: NSMenuItem) {
            guard !editor.isSaving, !editor.isLoading, !editor.requiresReload, actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
        }
    }
}

// Removal captions describe the raw scoped selection, even when the preview
// resolves a main-profile fallback after the selection is cleared.
extension ProfileEditorState {
    var avatarRemovalTitle: String {
        scope == .main ? String(localized: "Remove Avatar", bundle: #bundle) : String(localized: "Reset avatar to default", bundle: #bundle)
    }

    var bannerRemovalTitle: String {
        scope == .main ? String(localized: "Remove Banner", bundle: #bundle) : String(localized: "Reset Banner", bundle: #bundle)
    }

    var nameStyleRemovalTitle: String {
        scope == .main ? String(localized: "Remove Display Name Style", bundle: #bundle) : String(localized: "Reset display name style to default", bundle: #bundle)
    }

    func collectibleRemovalTitle(_ kind: ProfileCollectibleKind) -> String {
        switch kind {
        case .avatarDecoration:
            return scope == .main ? String(localized: "Remove Avatar Decoration", bundle: #bundle) : String(localized: "Reset avatar decoration to default", bundle: #bundle)
        case .nameplate:
            return scope == .main ? String(localized: "Remove Nameplate", bundle: #bundle) : String(localized: "Reset nameplate to default", bundle: #bundle)
        case .effect:
            return scope == .main ? String(localized: "Remove Profile Effect", bundle: #bundle) : String(localized: "Reset Effect", bundle: #bundle)
        case .frame:
            return scope == .main ? String(localized: "Remove Profile Frame", bundle: #bundle) : String(localized: "Reset Frame", bundle: #bundle)
        }
    }
}
