import AppKit

enum NativeTimelineCompactTimestampMetrics {
    static var font: NSFont {
        .preferredFont(forTextStyle: .caption2)
    }
}

nonisolated enum NativeTimelineMessageMenuAction: Equatable {
    case jumpToMessage
    case retrySending
    case addReaction
    case reply
    case forward
    case markUnread
    case editMessage
    case pinMessage
    case unpinMessage
    case copyText
    case copyLink
    case copyMessageID
    case copyAuthorID
    case deleteMessage
    case discardFailedMessage
}

nonisolated enum NativeTimelineSearchResultPresentation {
    static let jumpToMessageSystemImage = "arrow.forward.to.line"
}

nonisolated enum NativeTimelineMessageMenuEntry: Equatable {
    case action(
        NativeTimelineMessageMenuAction,
        title: String,
        systemImage: String,
        isDestructive: Bool = false
    )
    case separator
}

nonisolated enum NativeTimelineMessageMenuPolicy {
    static func entries(
        canEdit: Bool,
        canDelete: Bool,
        canRetry: Bool,
        canReply: Bool,
        canForward: Bool = false,
        canPin: Bool = false,
        isPinned: Bool = false,
        context: NativeTimelineMessageInteractionContext = .conversation
    ) -> [NativeTimelineMessageMenuEntry] {
        if context == .searchResult {
            return resultEntries(
                canDelete: canDelete,
                canPin: canPin,
                isPinned: isPinned,
                includesMarkUnread: true
            )
        }
        if context == .pinnedResult {
            return resultEntries(
                canDelete: canDelete,
                canPin: canPin,
                isPinned: true,
                includesMarkUnread: false
            )
        }

        return conversationEntries(
            canEdit: canEdit,
            canDelete: canDelete,
            canRetry: canRetry,
            canReply: canReply,
            canForward: canForward,
            canPin: canPin,
            isPinned: isPinned
        )
    }

    private static func conversationEntries(
        canEdit: Bool,
        canDelete: Bool,
        canRetry: Bool,
        canReply: Bool,
        canForward: Bool,
        canPin: Bool,
        isPinned: Bool
    ) -> [NativeTimelineMessageMenuEntry] {
        if canRetry {
            return [
                .action(
                    .retrySending,
                    title: "Retry Send",
                    systemImage: "arrow.clockwise"
                ),
                .separator,
                .action(
                    .copyText,
                    title: "Copy Text",
                    systemImage: "doc.on.doc"
                ),
                .separator,
                .action(
                    .discardFailedMessage,
                    title: "Delete Message…",
                    systemImage: "trash",
                    isDestructive: true
                ),
            ]
        }

        var result: [NativeTimelineMessageMenuEntry] = []
        result.append(.action(
            .addReaction,
            title: "Add Reaction",
            systemImage: SakuraCordSystemSymbol.emojiFaceGrinning
        ))
        if canReply {
            result.append(.action(
                .reply,
                title: "Reply",
                systemImage: "arrowshape.turn.up.left"
            ))
        }
        if canForward {
            result.append(.action(
                .forward,
                title: "Forward",
                systemImage: "arrowshape.turn.up.right"
            ))
        }
        if canEdit {
            result.append(.action(
                .editMessage,
                title: "Edit Message",
                systemImage: "pencil"
            ))
        }
        if canPin {
            result.append(.action(
                isPinned ? .unpinMessage : .pinMessage,
                title: isPinned ? "Unpin Message" : "Pin Message",
                systemImage: isPinned ? "pin.slash" : "pin"
            ))
        }
        result.append(.action(
            .markUnread,
            title: "Mark Unread",
            systemImage: "envelope.badge"
        ))
        result.append(.separator)
        result.append(.action(
            .copyText,
            title: "Copy Text",
            systemImage: "doc.on.doc"
        ))
        result.append(.action(
            .copyLink,
            title: "Copy Link",
            systemImage: "link"
        ))
        result.append(.action(
            .copyMessageID,
            title: "Copy Message ID",
            systemImage: "number.square.fill"
        ))
        if canDelete {
            result.append(.separator)
            result.append(.action(
                .deleteMessage,
                title: "Delete Message…",
                systemImage: "trash",
                isDestructive: true
            ))
        }
        return result
    }

    private static func resultEntries(
        canDelete: Bool,
        canPin: Bool,
        isPinned: Bool,
        includesMarkUnread: Bool
    ) -> [NativeTimelineMessageMenuEntry] {
        var result: [NativeTimelineMessageMenuEntry] = [
            .action(
                .jumpToMessage,
                title: "Jump to Message",
                systemImage: NativeTimelineSearchResultPresentation
                    .jumpToMessageSystemImage
            ),
        ]
        if includesMarkUnread {
            result.append(.action(
                .markUnread,
                title: "Mark Unread",
                systemImage: "envelope.badge"
            ))
        }
        if canPin {
            result.append(.action(
                isPinned ? .unpinMessage : .pinMessage,
                title: isPinned ? "Unpin Message" : "Pin Message",
                systemImage: isPinned ? "pin.slash" : "pin"
            ))
        }
        result.append(.separator)
        result.append(contentsOf: [
            .action(
                .copyText,
                title: "Copy Text",
                systemImage: "doc.on.doc"
            ),
            .action(
                .copyLink,
                title: "Copy Link",
                systemImage: "link"
            ),
            .action(
                .copyMessageID,
                title: "Copy Message ID",
                systemImage: "number.square.fill"
            ),
            .action(
                .copyAuthorID,
                title: "Copy Message Author ID",
                systemImage: "number.square.fill"
            ),
        ])
        if canDelete {
            result.append(contentsOf: [
                .separator,
                .action(
                    .deleteMessage,
                    title: "Delete Message…",
                    systemImage: "trash",
                    isDestructive: true
                ),
            ])
        }
        return result
    }
}
