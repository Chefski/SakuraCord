import AppKit
import SakuraCordModels

/// Pointer state for the thread card: hover, press and cursor. Each change
/// invalidates only the card, not its row.
extension NativeTimelineCanvasView {
    func threadCardPointerHit(at point: CGPoint) -> MessageID? {
        guard let index = rowIndex(at: point.y),
              items.indices.contains(index),
              layouts.indices.contains(index),
              case let .message(row, _, _) = items[index],
              row.message.thread != nil,
              let frame = layouts[index].threadFrame
        else { return nil }
        let local = CGPoint(x: point.x, y: point.y - displayedRowOrigin(at: index))
        return frame.contains(local) ? row.message.id : nil
    }

    func setHoveredThreadMessageID(_ value: MessageID?) {
        guard hoveredThreadMessageID != value else { return }
        let old = hoveredThreadMessageID
        hoveredThreadMessageID = value
        for messageID in [old, value].compactMap({ $0 }) {
            invalidateThreadCard(messageID: messageID)
        }
    }

    func invalidateThreadCard(messageID: MessageID) {
        guard let index = items.firstIndex(where: { $0.messageID == messageID }),
              layouts.indices.contains(index),
              let frame = layouts[index].threadFrame
        else { return }
        setNeedsDisplay(frame.offsetBy(dx: 0, dy: displayedRowOrigin(at: index)).insetBy(dx: -1, dy: -1))
    }

    func invalidatePressedThreadCard(
        _ old: NativeTimelinePointerActivationTarget?,
        _ new: NativeTimelinePointerActivationTarget?
    ) {
        for case let .thread(messageID, _)? in [old, new] {
            invalidateThreadCard(messageID: messageID)
        }
    }

    func threadCardInteraction(forMessageID messageID: MessageID?) -> NativeTimelineThreadCard.Interaction {
        guard let messageID, hoveredThreadMessageID == messageID else { return .idle }
        var isPressed = false
        if case let .thread(pressedID, _)? = pressedActivationTarget { isPressed = pressedID == messageID }
        return .init(isHovered: true, isPressed: isPressed)
    }

    func installThreadCardCursor(at index: Int, rowOrigin: CGFloat) {
        guard let frame = layouts[index].threadFrame, items[index].messageID != nil else { return }
        addCursorRect(frame.offsetBy(dx: 0, dy: rowOrigin), cursor: .pointingHand)
    }
}

extension NativeTimelineCanvasView {
    /// What the card shows beneath its name, for VoiceOver.
    func threadLastMessageSummary(_ thread: MessageThreadSummary, in message: Message) -> String {
        guard !thread.isArchived, thread.messageCount > 0,
              let preview = model?.threadPreviewMessages[thread.id]
        else { return NativeTimelineThreadCard.emptyText(for: thread) }
        let presented = MessageReplyPreview.presenting(preview)
        let summary = NativeTimelineReplyMetrics.summary(for: presented, in: message, model: model).text
        return "\(presented.author.displayName): \(summary)"
    }
}
