import SwiftUI

/// Which column of the conversation workspace a view fills.
nonisolated enum WorkspaceColumn: LayoutValueKey {
    case conversation
    case sideConversation
    case inspector

    static let defaultValue = WorkspaceColumn.conversation
}

/// Lays out the conversation, a side chat and the inspector in a row, like
/// an `HStack`, except that a full-width side chat covers the conversation
/// instead of sharing the row. The conversation can then stay beneath a side
/// chat that widens over it, and the side chat keeps its identity, timeline
/// and scroll position when it moves between the pane and full width.
///
/// The layout reads what each column should be from its parameters rather
/// than from which subviews exist, because a column that is sliding away is
/// still a subview until its transition ends. A departing pane keeps the
/// pane width so it leaves without a relayout, and the conversation takes
/// its new width at once.
nonisolated struct WorkspaceColumnsLayout: Layout {
    var showsSideConversation: Bool
    var sideConversationIsFullWidth: Bool
    var showsInspector: Bool
    /// The pane's width when it was last beside the conversation.
    var paneWidth: CGFloat
    /// The conversation's current width while a motion runs. The
    /// conversation never widens during a motion, so no column ever slides
    /// over it: it narrows as a column starts to arrive and widens once a
    /// leaving column is gone. Columns are translucent like the window, and
    /// clipping the conversation beneath one on every frame cost about 80 ms
    /// a frame.
    var conversationWidthLimit: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let height = bounds.height
        let conversation = subviews.filter { $0[WorkspaceColumn.self] == .conversation }
        let sideConversations = subviews.filter { $0[WorkspaceColumn.self] == .sideConversation }
        let inspectors = subviews.filter { $0[WorkspaceColumn.self] == .inspector }

        let inspectorWidths = inspectors.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: height)).width }
        let inspectorWidth = showsInspector ? inspectorWidths.last ?? 0 : 0

        var paneWidth = paneWidth
        if showsSideConversation, !sideConversationIsFullWidth, let pane = sideConversations.last {
            let conversationMinimum = conversation.map {
                $0.sizeThatFits(ProposedViewSize(width: 0, height: height)).width
            }.max() ?? 0
            // As an HStack does, give the pane its widest size the
            // conversation's minimum width leaves room for.
            let available = max(0, bounds.width - inspectorWidth - conversationMinimum)
            paneWidth = pane.sizeThatFits(ProposedViewSize(width: available, height: height)).width
        }

        // A full-width side chat covers the conversation, which keeps the
        // width it had beside the pane.
        var conversationWidth = max(0, bounds.width - inspectorWidth - (showsSideConversation ? paneWidth : 0))
        if let conversationWidthLimit, conversationWidthLimit > 0 {
            conversationWidth = min(conversationWidth, conversationWidthLimit)
        }
        for view in conversation {
            place(view, minX: bounds.minX, width: conversationWidth, in: bounds)
        }
        for view in sideConversations {
            if showsSideConversation, sideConversationIsFullWidth {
                place(view, minX: bounds.minX, width: bounds.width - inspectorWidth, in: bounds)
            } else {
                // A departing pane keeps its width at the trailing edge.
                place(view, minX: bounds.maxX - inspectorWidth - paneWidth, width: paneWidth, in: bounds)
            }
        }
        for (view, width) in zip(inspectors, inspectorWidths) {
            place(view, minX: bounds.maxX - width, width: width, in: bounds)
        }
    }

    private func place(_ view: LayoutSubview, minX: CGFloat, width: CGFloat, in bounds: CGRect) {
        view.place(
            at: CGPoint(x: minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }
}
