import AppKit
import SakuraCordModels

extension NativeTimelineCanvasView {
    @objc func restoreInboxKeyboardFocus() {
        guard messageInteractionContext == .inboxResult || messageInteractionContext == .inboxMention else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, let window, window.isVisible, NSApp.isActive,
                  window.attachedSheet == nil, model?.inbox.isPresented == true,
                  WindowModalCoordinator.allowsInput(for: self) else { return }
            window.makeKey()
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard messageInteractionContext == .inboxResult || messageInteractionContext == .inboxMention,
              WindowModalCoordinator.allowsInput(for: self), let model else {
            super.keyDown(with: event)
            return
        }
        let inbox = model.inbox
        let messages = inbox.rows.map(\.message)
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z", inbox.tab == .unread {
            model.undoInboxRead()
            return
        }
        switch event.keyCode {
        case 53:
            model.dismissInbox()
        case 125, 126:
            moveInboxSelection(forward: event.keyCode == 125, model: model)
        case 36, 76:
            if let message = messages.first(where: { $0.id == inbox.selectedMessageID }) {
                model.navigateToInboxResult(message)
            }
        case 51, 117:
            guard inbox.tab == .mentions else { super.keyDown(with: event); return }
            if let message = messages.first(where: { $0.id == inbox.selectedMessageID }) {
                model.dismissInboxMention(message)
            }
        case 115:
            inbox.scrollRequest = MessageTimelineScrollRequest(target: .top)
        case 119:
            inbox.scrollRequest = MessageTimelineScrollRequest(target: .bottom)
            model.loadMoreInbox()
        case 116, 121:
            if let scrollView = enclosingScrollView {
                let viewport = scrollView.contentView.bounds
                let delta = viewport.height * (event.keyCode == 121 ? 1 : -1)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, viewport.minY + delta)))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        default:
            super.keyDown(with: event)
        }
    }
    private func moveInboxSelection(forward: Bool, model: AppModel) {
        let inbox = model.inbox
        let messages = inbox.rows.map(\.message)
        guard !messages.isEmpty else { return }
        let current = inbox.selectedMessageID.flatMap { id in messages.firstIndex { $0.id == id } }
        let next = if let current {
            min(messages.count - 1, max(0, current + (forward ? 1 : -1)))
        } else { forward ? 0 : messages.count - 1 }
        inbox.selectedMessageID = messages[next].id
        inbox.scrollRequest = MessageTimelineScrollRequest(target: .message(messages[next].id, anchor: .center))
        if next >= messages.count - 2 { model.loadMoreInbox() }
    }

}
