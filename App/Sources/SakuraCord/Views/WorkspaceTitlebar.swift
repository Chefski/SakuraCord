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
    /// Whether the window toolbar shows its search field. The field keeps
    /// its place at the trailing edge; it fades out over a thread pane as it
    /// opens, and back, on the columns' frames.
    let showsSearch: Bool

    func makeNSView(context _: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.overlay.apply(groups, showsSearch: showsSearch, environment: context.environment)
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
        /// The content's ideal size, which its layout reports.
        let measurement = IslandMeasurement()
        var size: CGSize { measurement.size }

        init(_ content: AnyView) {
            host = NSHostingController(rootView: AnyView(EmptyView()))
            host.sizingOptions = []
            host.view.translatesAutoresizingMaskIntoConstraints = true
            setContent(content)
        }

        func setContent(_ content: AnyView) {
            host.rootView = AnyView(IdealSizeLayout(measurement: measurement) { content })
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
        environment: EnvironmentValues
    ) {
        self.showsSearch = showsSearch
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
                for island in [views.title, views.actions] { observe(island) }
                addSubview(views.clip)
                self.groups[group.id] = views
                return views
            }()
            let probe = group.id == WorkspaceTitlebar.conversationID ? "tb.conversation" : "tb.side"
            views.title.setContent(
                AnyView(group.title.workspaceMotionProbe("\(probe).title").environment(\.self, environment))
            )
            views.actions.setContent(
                AnyView(group.actions.workspaceMotionProbe("\(probe).actions").environment(\.self, environment))
            )
            if let fullWidthActions = group.fullWidthActions {
                let island = views.fullWidthActions ?? {
                    let island = Island(fullWidthActions)
                    observe(island)
                    views.clip.addSubview(island.host.view)
                    views.fullWidthActions = island
                    return island
                }()
                island.setContent(
                    AnyView(
                        fullWidthActions.workspaceMotionProbe("tb.side.fullActions").environment(\.self, environment)
                    )
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

    /// Places the groups again once an island has measured its content.
    private func observe(_ island: Island) {
        island.measurement.changed = { [weak self] in self?.placeGroups() }
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
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        // Search sits at the window's trailing edge, as the toolbar's own
        // field does, and fades out over a thread pane as it opens and back
        // as it leaves or widens.
        let searchAlpha = searchVisibility(geometry)
        _ = searchItemView
        // Items stop before the field while it shows, or will once a pane
        // leaves; they never pass it to come back.
        let searchMinX = showsSearch || searchAlpha > 0 ? searchFieldMinX : nil
        let searchLimit = (searchMinX ?? bounds.maxX + inset) - inset
        for id in order {
            guard let views = groups[id] else { continue }
            // In window coordinates.
            let span: ClosedRange<CGFloat>
            var visibleMaxX: CGFloat
            var widening: CGFloat = 0
            var endsAtSearch = true
            if id == WorkspaceTitlebar.conversationID {
                guard let conversation = geometry.conversation else { continue }
                span = conversation
                visibleMaxX = min(span.upperBound, fullWidth?.minX ?? .infinity)
            } else {
                guard let column = geometry.columns.first(where: { $0.id == id }) else { continue }
                span = column.minX ... column.maxX
                visibleMaxX = span.upperBound
                if column.isFullWidth { widening = column.widening }
                endsAtSearch = column.isFullWidth
            }
            // Clear of the window's controls and the sidebar button, which
            // the column reaches when the sidebar is hidden.
            let minX = max(convert(CGPoint(x: span.lowerBound, y: 0), from: nil).x, leadingLimit)
            var maxX = min(convert(CGPoint(x: span.upperBound, y: 0), from: nil).x, bounds.maxX)
            visibleMaxX = min(convert(CGPoint(x: visibleMaxX, y: 0), from: nil).x, bounds.maxX)
            // The conversation's items, and a full-width side chat's, end
            // before the search field; a pane's own actions stay at its edge.
            let searchInset = endsAtSearch ? max(0, maxX - searchLimit) : 0
            if id == WorkspaceTitlebar.conversationID { maxX -= searchInset }
            let clipX = minX.rounded(.down)
            views.clip.frame = CGRect(x: clipX, y: 0, width: max(0, visibleMaxX - clipX), height: bounds.height)
            place(
                views,
                width: maxX - clipX,
                widening: widening,
                fullWidthInset: id == WorkspaceTitlebar.conversationID ? 0 : searchInset,
                fills: id != WorkspaceTitlebar.conversationID
            )
        }
        fadeSearch(searchAlpha)
    }

    /// How much of the search field shows: none beside a thread pane, which
    /// hides it, and in between while the pane moves or widens.
    private func searchVisibility(_ geometry: WorkspaceColumnsGeometry) -> CGFloat {
        guard showsSearch || WorkspaceLayoutMotion.isMoving else { return 0 }
        let windowMaxX = convert(CGPoint(x: bounds.maxX, y: 0), to: nil).x
        var covered: CGFloat = 0
        for column in geometry.columns where column.id.hasPrefix("side-thread") {
            let width = max(1, column.maxX - column.minX)
            let shown = column.isFullWidth
                ? 1 - column.widening
                : min(1, max(0, (windowMaxX - column.minX) / width))
            covered = max(covered, shown)
        }
        return 1 - covered
    }

    private var showsSearch = false
    private weak var searchField: NSSearchField?

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

    /// The toolbar's search field, with the glass the toolbar draws for it.
    private var searchItemView: NSView? {
        guard let window else { return nil }
        if searchField?.window !== window {
            searchField = ToolbarSearchFieldLocator.searchField(in: window)
        }
        guard let searchField, searchField.window === window else { return nil }
        // The field's own item in the toolbar, which also draws its glass.
        var view: NSView? = searchField
        while let candidate = view, !String(describing: type(of: candidate)).contains("ItemViewer") {
            view = candidate.superview
        }
        return view ?? searchField
    }

    /// Where the toolbar's search field starts in this view, if the toolbar
    /// has it, shown or faded out.
    private var searchFieldMinX: CGFloat? {
        guard let searchField, searchField.window === window else { return nil }
        return convert(searchField.bounds, from: searchField).minX
    }

    private func fadeSearch(_ alpha: CGFloat) {
        guard let view = searchItemView, view.alphaValue != alpha else { return }
        view.alphaValue = alpha
        view.isHidden = alpha < 0.01
    }

    /// Places a group's title at its column's leading edge and its actions
    /// at the trailing edge, within its clip view.
    /// - Parameter fullWidthInset: How far before the trailing edge a
    ///   full-width side chat's actions end, at the search field.
    private func place(_ views: GroupViews, width: CGFloat, widening: CGFloat, fullWidthInset: CGFloat, fills: Bool) {
        let inset = ChatChromeMetrics.toolbarItemEdgeInset
        let height = bounds.height
        let actionsWidth = views.actions.size.width * (1 - widening)
            + ((views.fullWidthActions?.size.width ?? 0) + fullWidthInset) * widening
        let unmeasured = CGSize(width: 1, height: height)
        for (island, alpha, trailing) in [
            (views.actions, 1 - widening, 0),
            (views.fullWidthActions, widening, fullWidthInset),
        ] {
            guard let island else { continue }
            // Whole points wide, so its edges rest on whole points too.
            let size = island.size == .zero
                ? unmeasured : CGSize(width: island.size.width.rounded(.up), height: island.size.height)
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
        let titleSize = views.title.size == .zero ? unmeasured : views.title.size
        let natural = min(titleSize.width, available)
        let titleWidth = fills ? available * (1 - widening) + natural * widening : natural
        setFrame(of: views.title.host.view, CGRect(
            x: inset,
            y: ((height - titleSize.height) / 2).rounded(),
            width: titleWidth,
            height: titleSize.height
        ))
    }

    /// On whole points, so items rest on the same pixels whatever their
    /// column's edge, and never land between pixels as they move.
    private func setFrame(of view: NSView, _ frame: CGRect) {
        var frame = frame
        frame.origin.x = frame.origin.x.rounded()
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

/// An island's ideal size, which its layout reports as it lays out, so it is
/// never laid out at a measuring size in view.
nonisolated private final class IslandMeasurement: @unchecked Sendable {
    var size = CGSize.zero
    /// Called on the main thread after the size changes.
    var changed: (@MainActor () -> Void)?
}

/// Lays its content out in whatever frame it is given and reports the
/// content's ideal size, so a title that fills its frame still measures
/// only as wide as its text.
nonisolated private struct IdealSizeLayout: Layout {
    let measurement: IslandMeasurement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: subviews.first?.sizeThatFits(.unspecified) ?? .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let content = subviews.first else { return }
        content.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        let ideal = content.sizeThatFits(.unspecified)
        guard ideal != measurement.size else { return }
        measurement.size = ideal
        let measurement = measurement
        DispatchQueue.main.async { MainActor.assumeIsolated { measurement.changed?() } }
    }
}
