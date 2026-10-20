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
    /// Whether the conversation ends with the toolbar's search field, which
    /// moves into it from the window toolbar (`WorkspaceSearchFieldHost`).
    let showsSearch: Bool
    /// The search field's width when the conversation has room for it.
    let searchWidth: CGFloat

    func makeNSView(context _: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.overlay.apply(groups, showsSearch: showsSearch, searchWidth: searchWidth, environment: context.environment)
    }

    static func dismantleNSView(_ anchor: Anchor, coordinator _: ()) {
        anchor.overlay.searchHost.release()
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

        /// - Parameter measures: Whether to measure the content again. A
        ///   measurement lays it out at once, which motions skip: their items
        ///   keep their content.
        func setContent(_ content: AnyView, measures: Bool) {
            host.rootView = AnyView(IdealSizeLayout { content })
            guard measures || size == .zero else { return }
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
        // Assistive apps find the items where the toolbar's were.
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        _ groups: [WorkspaceTitlebar.Group],
        showsSearch: Bool,
        searchWidth: CGFloat,
        environment: EnvironmentValues
    ) {
        self.showsSearch = showsSearch
        self.searchWidth = searchWidth
        // A side chat's items stay while its column is still sliding away,
        // as they were: updates within the change that closes it can come
        // before the column is listed as leaving.
        let measures = !WorkspaceLayoutMotion.isMoving
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
            views.title.setContent(
                AnyView(group.title.workspaceMotionProbe("\(probe).title").environment(\.self, environment)),
                measures: measures
            )
            views.actions.setContent(
                AnyView(group.actions.workspaceMotionProbe("\(probe).actions").environment(\.self, environment)),
                measures: measures
            )
            if let fullWidthActions = group.fullWidthActions {
                let island = views.fullWidthActions ?? {
                    let island = Island(fullWidthActions)
                    views.clip.addSubview(island.host.view)
                    views.fullWidthActions = island
                    return island
                }()
                island.setContent(
                    AnyView(
                        fullWidthActions.workspaceMotionProbe("tb.side.fullActions").environment(\.self, environment)
                    ),
                    measures: measures
                )
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
        // A full-width side chat covers the conversation from its leading
        // edge as it widens.
        let leadingLimit = leadingControlsMaxX
        let fullWidth = geometry.columns.last(where: \.isFullWidth)
        let fullWidthViews = fullWidth.flatMap { groups[$0.id] }
        let conversationViews = groups[WorkspaceTitlebar.conversationID]
        // Search ends the conversation's items, then a full-width side
        // chat's, moving between them as it widens.
        let searchWeight = fullWidthViews == nil ? 0 : conversationViews == nil ? 1 : fullWidth?.widening ?? 0
        var conversationSearch: CGFloat = 0
        var fullWidthSearch: CGFloat = 0
        let holdsSearch = showsSearch && (conversationViews != nil || fullWidthViews != nil)
        if !holdsSearch { searchHost.release() }
        for id in order {
            guard let views = groups[id] else { continue }
            // In window coordinates.
            let span: ClosedRange<CGFloat>
            var visibleMaxX: CGFloat
            var widening: CGFloat = 0
            if id == WorkspaceTitlebar.conversationID {
                guard let conversation = geometry.conversation else { continue }
                span = conversation
                visibleMaxX = min(span.upperBound, fullWidth?.minX ?? .infinity)
            } else {
                guard let column = geometry.columns.first(where: { $0.id == id }) else { continue }
                span = column.minX ... column.maxX
                visibleMaxX = span.upperBound
                if column.isFullWidth { widening = column.widening }
            }
            // Clear of the window's controls and the sidebar button, which
            // the column reaches when the sidebar is hidden.
            let minX = max(convert(CGPoint(x: span.lowerBound, y: 0), from: nil).x, leadingLimit)
            let maxX = min(convert(CGPoint(x: span.upperBound, y: 0), from: nil).x, bounds.maxX)
            visibleMaxX = min(convert(CGPoint(x: visibleMaxX, y: 0), from: nil).x, bounds.maxX)
            views.clip.frame = CGRect(x: minX, y: 0, width: max(0, visibleMaxX - minX), height: bounds.height)
            var reserve: (actions: CGFloat, fullWidthActions: CGFloat) = (0, 0)
            if holdsSearch, views === conversationViews {
                conversationSearch = searchWidth(beside: views.title.size.width + views.actions.size.width, in: maxX - minX)
                reserve.actions = conversationSearch + ChatChromeMetrics.toolbarItemEdgeInset
            } else if holdsSearch, views === fullWidthViews {
                let actions = views.fullWidthActions?.size.width ?? views.actions.size.width
                fullWidthSearch = searchWidth(beside: views.title.size.width + actions, in: maxX - minX)
                reserve.fullWidthActions = fullWidthSearch + ChatChromeMetrics.toolbarItemEdgeInset
            }
            place(views, width: maxX - minX, widening: widening, reserve: reserve,
                  fills: id != WorkspaceTitlebar.conversationID)
        }
        if holdsSearch, let window {
            placeSearch(
                width: conversationSearch * (1 - searchWeight) + fullWidthSearch * searchWeight,
                trailingEdge: localX(geometry.conversation?.upperBound ?? 0),
                fullWidthTrailingEdge: fullWidth.map { localX($0.maxX) },
                weight: searchWeight,
                window: window
            )
        }
    }

    let searchHost = WorkspaceSearchFieldHost()
    private var showsSearch = false
    private var searchWidth: CGFloat = 0

    /// Where the window's own leading controls end in this view: its
    /// buttons and the toolbar's leading items, such as the sidebar button.
    private var leadingControlsMaxX: CGFloat {
        guard let window else { return 0 }
        var maxX: CGFloat = 0
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let view = window.standardWindowButton(button), !view.isHiddenOrHasHiddenAncestor {
                maxX = max(maxX, convert(view.bounds, from: view).maxX)
            }
        }
        for item in window.toolbar?.items ?? [] where !(item is NSSearchToolbarItem) {
            guard let view = item.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
            let frame = convert(view.bounds, from: view)
            // Only items at the leading edge, before the workspace's.
            if frame.minX < bounds.midX / 2 { maxX = max(maxX, frame.maxX) }
        }
        return maxX > 0 ? maxX + ChatChromeMetrics.toolbarItemEdgeInset : 0
    }

    /// A window x in this view, within it.
    private func localX(_ windowX: CGFloat) -> CGFloat {
        min(convert(CGPoint(x: windowX, y: 0), from: nil).x, bounds.maxX)
    }

    /// The search field narrows as its column does, once the column's title
    /// and actions need the room, down to its magnifier.
    private func searchWidth(beside others: CGFloat, in width: CGFloat) -> CGFloat {
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        return min(searchWidth, max(36, width - others - inset * 5))
    }

    /// Places the search field at the trailing edge of the conversation, or
    /// of a full-width side chat as `weight` goes to 1.
    private func placeSearch(
        width: CGFloat,
        trailingEdge: CGFloat,
        fullWidthTrailingEdge: CGFloat?,
        weight: CGFloat,
        window: NSWindow
    ) {
        guard let holder = searchHost.hold(in: window) else { return }
        if holder.superview !== self { addSubview(holder) }
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        let edge = trailingEdge * (1 - weight) + (fullWidthTrailingEdge ?? trailingEdge) * weight
        // It fades across the widening side chat's items rather than over
        // them.
        holder.alphaValue = abs(1 - 2 * weight)
        let height: CGFloat = 36
        setFrame(of: holder, CGRect(
            x: edge - inset - width,
            y: ((bounds.height - height) / 2).rounded(),
            width: width,
            height: height
        ))
    }

    /// Places a group's title at its column's leading edge and its actions
    /// at the trailing edge, within its clip view.
    private func place(
        _ views: GroupViews,
        width: CGFloat,
        widening: CGFloat,
        reserve: (actions: CGFloat, fullWidthActions: CGFloat),
        fills: Bool
    ) {
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        let height = bounds.height
        let actionsWidth = (views.actions.size.width + reserve.actions) * (1 - widening)
            + ((views.fullWidthActions?.size.width ?? 0) + reserve.fullWidthActions) * widening
        for (island, alpha, trailing) in [
            (views.actions, 1 - widening, reserve.actions),
            (views.fullWidthActions, widening, reserve.fullWidthActions),
        ] {
            guard let island else { continue }
            let size = island.size
            setFrame(of: island.host.view, CGRect(
                x: width - trailing - inset - size.width,
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
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // Items in front first; a group's empty clip view takes nothing.
        for view in subviews.reversed() where !view.isHidden {
            if let hit = view.hitTest(local), !(hit is TitlebarClipView) { return hit }
        }
        return nil
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

/// Moves the window toolbar's search field into the conversation's toolbar
/// items and back. It is SwiftUI's own field, with its delegate, tokens and
/// editor, so search works as it does in the toolbar; only its place
/// changes. Its toolbar item stays, hidden (`ToolbarSearchFieldGeometryReader`).
@MainActor
final class WorkspaceSearchFieldHost {
    /// Posted when the field moves out of or back into the toolbar.
    static let didChange = Notification.Name("SakuraCordWorkspaceSearchFieldHostDidChange")
    private(set) static var isHosting = false

    private let holder = SearchFieldHolder()
    private weak var field: NSSearchField?
    private weak var originalSuperview: NSView?
    private var originalConstraints: [NSLayoutConstraint] = []
    private var originalTranslatesAutoresizingMask = false

    /// The view holding the field, taking it from the toolbar if needed.
    func hold(in window: NSWindow) -> NSView? {
        if let field, field.superview === holder.contentView, field.window === window {
            // The toolbar hides a field it has collapsed for lack of room;
            // here it has its own.
            if field.isHidden { field.isHidden = false }
            return holder
        }
        guard let field = ToolbarSearchFieldLocator.searchField(in: window) else { return nil }
        release()
        originalSuperview = field.superview
        originalConstraints = field.superview?.constraints.filter {
            $0.firstItem === field || $0.secondItem === field
        } ?? []
        originalTranslatesAutoresizingMask = field.translatesAutoresizingMaskIntoConstraints
        field.removeFromSuperview()
        field.translatesAutoresizingMaskIntoConstraints = true
        field.autoresizingMask = [.width, .height]
        field.frame = holder.contentView?.bounds ?? holder.bounds
        field.isHidden = false
        holder.contentView?.addSubview(field)
        self.field = field
        Self.isHosting = true
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return holder
    }

    /// Returns the field to the toolbar.
    func release() {
        guard let field else { return }
        self.field = nil
        field.removeFromSuperview()
        field.translatesAutoresizingMaskIntoConstraints = originalTranslatesAutoresizingMask
        if let originalSuperview {
            originalSuperview.addSubview(field)
            NSLayoutConstraint.activate(originalConstraints)
        }
        originalSuperview = nil
        originalConstraints = []
        holder.removeFromSuperview()
        Self.isHosting = false
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// The search field's glass, as the toolbar draws behind its items.
private final class SearchFieldHolder: NSGlassEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 18
        contentView = FlippedView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
