import AppKit
import SwiftUI

/// Where the workspace's columns are in the window, published by
/// `WorkspaceColumnsView` each time it places them, on every frame of a
/// motion. `WorkspaceTitlebarView` places each column's toolbar items from
/// it in the same frame, so they move with their column.
@MainActor
final class WorkspaceColumnsGeometry {
    struct Column: Equatable {
        let id: String
        /// In window coordinates.
        let minX: CGFloat
        let maxX: CGFloat
        let isFullWidth: Bool
        /// How far a full-width side chat has widened from the pane: 0 in the
        /// pane, 1 at full width.
        let widening: CGFloat
    }

    static let shared = WorkspaceColumnsGeometry()

    /// The conversation's span in window coordinates, or nil without one.
    private(set) var conversation: ClosedRange<CGFloat>?
    private(set) var columns: [Column] = []
    private var observers: [WeakObserver] = []

    private struct WeakObserver {
        weak var view: WorkspaceTitlebarView?
    }

    private init() {}

    func update(conversation: ClosedRange<CGFloat>?, columns: [Column]) {
        guard conversation != self.conversation || columns != self.columns else { return }
        self.conversation = conversation
        self.columns = columns
        observers.removeAll { $0.view == nil }
        for observer in observers {
            observer.view?.placeGroups()
        }
    }

    fileprivate func observe(_ view: WorkspaceTitlebarView) {
        observers.removeAll { $0.view == nil || $0.view === view }
        observers.append(WeakObserver(view: view))
    }
}

/// The workspace's toolbar items, each with the column it belongs to: the
/// conversation's title and actions at the conversation's edges, and each
/// side chat's title and actions on the side chat. They move with their
/// column on every frame of a motion rather than being replaced, as one
/// window toolbar would replace them.
///
/// It is one toolbar item spanning the detail area. Inside it each group is
/// its own SwiftUI hosting view, placed by `WorkspaceTitlebarView` from
/// `WorkspaceColumnsGeometry`, so a motion updates no view graph.
struct WorkspaceTitlebar: NSViewRepresentable {
    struct Group {
        /// `conversationID` or the column's `WorkspaceTrailingColumn` id.
        let id: String
        let title: AnyView
        let actions: AnyView
        /// The actions a side chat shows at full width; they replace
        /// `actions` as it widens.
        var fullWidthActions: AnyView?
    }

    static let conversationID = "conversation"

    let groups: [Group]
    /// The width the toolbar's search field takes at the window's trailing
    /// edge, or 0 without it.
    let searchReserve: CGFloat

    func makeNSView(context _: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.overlay.apply(groups, searchReserve: searchReserve, environment: context.environment)
    }

    static func dismantleNSView(_ anchor: Anchor, coordinator _: ()) {
        anchor.overlay.removeFromSuperview()
    }

    /// Installs the items over the window's titlebar. The toolbar would lay
    /// out an item of its own, and fit it among its other items, on every
    /// change; over it, the items are placed only by their columns.
    final class Anchor: NSView {
        let overlay = WorkspaceTitlebarView()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let titlebar = window?.standardWindowButton(.closeButton)?.superview else {
                overlay.removeFromSuperview()
                return
            }
            guard overlay.superview !== titlebar else { return }
            overlay.frame = titlebar.bounds
            overlay.autoresizingMask = [.width, .height]
            titlebar.addSubview(overlay)
        }
    }
}

final class WorkspaceTitlebarView: NSView {
    private final class Island {
        let host: NSHostingController<AnyView>
        /// Measured when its content is set.
        var size = CGSize.zero

        init(_ content: AnyView) {
            host = NSHostingController(rootView: AnyView(IdealSizeLayout { content }))
            host.sizingOptions = []
            host.view.translatesAutoresizingMaskIntoConstraints = true
        }

        func setContent(_ content: AnyView) {
            host.rootView = AnyView(IdealSizeLayout { content })
            size = host.sizeThatFits(in: CGSize(width: IdealSizeLayout.measuringWidth, height: 52))
        }
    }

    private final class GroupViews {
        /// Clips the group to the part of its column not covered by another.
        let clip = TitlebarClipView()
        let title: Island
        let actions: Island
        var fullWidthActions: Island?

        init(_ group: WorkspaceTitlebar.Group) {
            title = Island(group.title)
            actions = Island(group.actions)
            clip.addSubview(title.host.view)
            clip.addSubview(actions.host.view)
        }
    }

    private var groups: [String: GroupViews] = [:]
    /// Groups whose column the workspace has placed.
    private var placedColumnIDs: Set<String> = []
    private var order: [String] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        WorkspaceColumnsGeometry.shared.observe(self)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ groups: [WorkspaceTitlebar.Group], searchReserve: CGFloat, environment: EnvironmentValues) {
        updateSearchReserve(searchReserve)
        // A side chat's items stay while its column is still sliding away,
        // as they were: updates within the change that closes it can come
        // before the column is listed as leaving.
        let ids = Set(groups.map(\.id))
        let leaving = self.order.filter { id in
            !ids.contains(id) && id != WorkspaceTitlebar.conversationID
                && WorkspaceColumnsGeometry.shared.columns.contains { $0.id == id }
        }
        removeGroups { !ids.contains($0) && !leaving.contains($0) }
        for group in groups {
            let views = self.groups[group.id] ?? {
                let views = GroupViews(group)
                addSubview(views.clip)
                self.groups[group.id] = views
                return views
            }()
            let probe = group.id == WorkspaceTitlebar.conversationID ? "tb.conversation" : "tb.side"
            views.title.setContent(AnyView(
                group.title.workspaceMotionProbe("\(probe).title").environment(\.self, environment)
            ))
            views.actions.setContent(AnyView(
                group.actions.workspaceMotionProbe("\(probe).actions").environment(\.self, environment)
            ))
            if let fullWidthActions = group.fullWidthActions {
                let island = views.fullWidthActions ?? {
                    let island = Island(fullWidthActions)
                    views.clip.addSubview(island.host.view)
                    views.fullWidthActions = island
                    return island
                }()
                island.setContent(AnyView(
                    fullWidthActions.workspaceMotionProbe("tb.side.fullActions").environment(\.self, environment)
                ))
            } else if let island = views.fullWidthActions {
                island.host.view.removeFromSuperview()
                views.fullWidthActions = nil
            }
        }
        // Later groups are in front: a side chat covers the conversation and
        // one arriving covers one leaving.
        order = leaving + groups.map(\.id)
        for id in order {
            if let clip = self.groups[id]?.clip { addSubview(clip) }
        }
        placeGroups()
    }

    override func layout() {
        super.layout()
        placeGroups()
    }

    private func removeGroups(where shouldRemove: (String) -> Bool) {
        for (id, views) in groups where shouldRemove(id) {
            views.clip.removeFromSuperview()
            groups[id] = nil
        }
        order.removeAll { groups[$0] == nil }
    }

    /// Places each group on its column, as the column is now.
    func placeGroups() {
        guard window != nil else { return }
        let geometry = WorkspaceColumnsGeometry.shared
        // A side chat's items leave with its column, once it has had one.
        let columnIDs = Set(geometry.columns.map(\.id))
        removeGroups { id in
            id != WorkspaceTitlebar.conversationID && placedColumnIDs.contains(id) && !columnIDs.contains(id)
        }
        placedColumnIDs.formUnion(columnIDs.intersection(groups.keys))
        placedColumnIDs.formIntersection(groups.keys)
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        // A full-width side chat covers the conversation from its leading
        // edge as it widens.
        let fullWidthMinX = geometry.columns.first(where: \.isFullWidth)?.minX
        // The toolbar's search field ends the conversation's and a full-width
        // side chat's actions.
        let searchMinX = searchReserve > 0
            ? convert(CGPoint(x: bounds.maxX - searchReserve - inset, y: 0), to: nil).x
            : .infinity
        for id in order {
            guard let views = groups[id] else { continue }
            // In window coordinates.
            let span: ClosedRange<CGFloat>
            var visibleMaxX: CGFloat
            var widening: CGFloat = 0
            if id == WorkspaceTitlebar.conversationID {
                guard let conversation = geometry.conversation else { continue }
                span = conversation.lowerBound ... max(conversation.lowerBound, min(conversation.upperBound, searchMinX))
                visibleMaxX = min(span.upperBound, fullWidthMinX ?? .infinity)
            } else {
                guard let column = geometry.columns.first(where: { $0.id == id }) else { continue }
                let maxX = column.isFullWidth ? min(column.maxX, searchMinX) : column.maxX
                span = column.minX ... max(column.minX, maxX)
                visibleMaxX = span.upperBound
                if column.isFullWidth { widening = column.widening }
            }
            // In this view's coordinates; it ends before the toolbar's
            // trailing items.
            let minX = convert(CGPoint(x: span.lowerBound, y: 0), from: nil).x
            let maxX = min(convert(CGPoint(x: span.upperBound, y: 0), from: nil).x, bounds.maxX)
            visibleMaxX = min(convert(CGPoint(x: visibleMaxX, y: 0), from: nil).x, bounds.maxX)
            views.clip.frame = CGRect(x: minX, y: 0, width: max(0, visibleMaxX - minX), height: bounds.height)
            place(views, width: maxX - minX, widening: widening, fills: id != WorkspaceTitlebar.conversationID)
        }
    }

    private var searchReserve: CGFloat = 0
    private var pendingSearchReserve: Task<Void, Never>?

    /// A search field that leaves as a side chat opens leaves room only once
    /// the conversation has made way, so its actions do not jump into it.
    private func updateSearchReserve(_ reserve: CGFloat) {
        pendingSearchReserve?.cancel()
        guard reserve < searchReserve, WorkspaceLayoutMotion.isMoving else {
            searchReserve = reserve
            return
        }
        pendingSearchReserve = Task { [weak self] in
            await WorkspaceLayoutMotion.untilSettled()
            guard let self, !Task.isCancelled else { return }
            searchReserve = reserve
            placeGroups()
        }
    }

    /// Places a group's title at its column's leading edge and its actions
    /// at the trailing edge, within its clip view.
    private func place(_ views: GroupViews, width: CGFloat, widening: CGFloat, fills: Bool) {
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        let height = bounds.height
        let actionsWidth = views.actions.size.width * (1 - widening)
            + (views.fullWidthActions?.size.width ?? 0) * widening
        for (island, alpha) in [(views.actions, 1 - widening), (views.fullWidthActions, widening)] {
            guard let island else { continue }
            let size = island.size
            setFrame(of: island.host.view, CGRect(
                x: width - inset - size.width,
                y: ((height - size.height) / 2).rounded(),
                width: size.width,
                height: size.height
            ))
            island.host.view.alphaValue = alpha
            island.host.view.isHidden = alpha < 0.01
        }
        // A side chat's title fills the pane up to its actions; at full width
        // it takes only the width it needs, like the conversation's.
        let available = max(0, width - actionsWidth - inset * 3)
        let natural = min(views.title.size.width, available)
        let titleWidth = fills ? available * (1 - widening) + natural * widening : natural
        setFrame(of: views.title.host.view, CGRect(
            x: inset,
            y: ((height - views.title.size.height) / 2).rounded(),
            width: titleWidth,
            height: views.title.size.height
        ))
    }

    private func setFrame(of view: NSView, _ frame: CGRect) {
        if view.frame != frame { view.frame = frame }
    }

    /// Empty space between the items moves the window, as the toolbar's own
    /// does.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self || view is TitlebarClipView ? nil : view
    }
}

private final class TitlebarClipView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
}

/// Sizes to its content's ideal size, and lays the content out in whatever
/// frame it is given, so a title that fills its frame still measures only
/// as wide as its text.
nonisolated private struct IdealSizeLayout: Layout {
    /// Proposals this large measure; any other is the frame it is placed in.
    static let measuringWidth: CGFloat = 1_000_000

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let ideal = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        guard let width = proposal.width, width < Self.measuringWidth else { return ideal }
        return CGSize(width: width, height: proposal.height ?? ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
