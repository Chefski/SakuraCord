import AppKit
import SwiftUI

/// The workspace's conversation, side chat and inspector, each in its own
/// SwiftUI hosting view inside one AppKit container that moves them.
///
/// Why this layer exists: a side chat or the member list slides in while the
/// conversation beside it resizes live. Driven by SwiftUI, every frame of
/// that motion re-ran the window's view graph, moved hundreds of layers and
/// relaid out the workspace: about 30 ms of main-thread work per frame on an
/// 8 GB Mac in Release, so fewer than a third of the motion's frames reached
/// the screen. Here a display link sets the islands' frames directly. The
/// window's SwiftUI graph does nothing per frame; only the conversation's
/// island lays out at its new width, and a sliding column moves as one view.
///
/// The columns follow `WorkspaceMotionPhase`: each column's reveal and the
/// widening are targets this view springs toward with the workspace spring,
/// or jumps to when the update that sets them is not animated.
///
/// Setting `SakuraCordSwiftUIWorkspaceColumns` switches back to the SwiftUI
/// layout (`WorkspaceColumnsLayout`) for comparison.
struct WorkspaceColumnsHost: NSViewRepresentable {
    struct Column {
        let id: String
        let isSideConversation: Bool
        let isFullWidth: Bool
        /// Leaving: its width is no longer measured.
        let isDeparting: Bool
        let content: AnyView
    }

    enum Widening {
        /// A full-width side chat starts from the pane's width…
        case starting
        /// …and grows to fill the workspace.
        case arriving
    }

    static let isEnabled = !UserDefaults.standard.bool(forKey: "SakuraCordSwiftUIWorkspaceColumns")

    let conversation: AnyView
    /// Back to front: departing columns first, so an arriving one covers them.
    let columns: [Column]
    let widening: Widening?
    let isMoving: Bool
    /// Receives the frame the columns report with
    /// `SupplementaryPaneFramePreferenceKey`, where the column rests, in
    /// the window's SwiftUI global coordinates. Preferences do not leave a
    /// hosting view, so this carries them out.
    let supplementaryPaneFrameChanged: (CGRect) -> Void

    func makeNSView(context _: Context) -> WorkspaceColumnsView {
        WorkspaceColumnsView()
    }

    func updateNSView(_ view: WorkspaceColumnsView, context: Context) {
        let transaction = context.transaction
        view.apply(
            self,
            environment: context.environment,
            animates: transaction.animation != nil && !transaction.disablesAnimations
        )
    }

    static func dismantleNSView(_ view: WorkspaceColumnsView, coordinator _: ()) {
        view.stopMotion()
    }
}

/// A value that follows the workspace spring toward a target and can be
/// retargeted mid-flight, keeping its velocity.
private struct SpringTrack {
    private(set) var target: CGFloat
    private var origin: CGFloat
    /// When the motion started, or nil until its first frame. A column's
    /// first frame can take a while to lay out; the motion starts after it
    /// rather than jumping ahead by however long it took.
    private var start: CFTimeInterval?
    private var initialVelocity: CGFloat = 0

    init(at value: CGFloat) {
        target = value
        origin = value
    }

    private static var spring: Spring { ChatChromeMetrics.sidebarSpring }

    func value(at time: CFTimeInterval) -> CGFloat {
        guard origin != target else { return target }
        guard let start else { return origin }
        let progress = Self.spring.value(
            target: 1.0,
            initialVelocity: Double(initialVelocity / (target - origin)),
            time: max(0, time - start)
        )
        return origin + (target - origin) * CGFloat(progress)
    }

    private func velocity(at time: CFTimeInterval) -> CGFloat {
        guard origin != target else { return 0 }
        guard let start else { return initialVelocity }
        let velocity = Self.spring.velocity(
            target: 1.0,
            initialVelocity: Double(initialVelocity / (target - origin)),
            time: max(0, time - start)
        )
        return (target - origin) * CGFloat(velocity)
    }

    func isSettled(at time: CFTimeInterval) -> Bool {
        origin == target || start != nil && abs(value(at: time) - target) < 0.0005 && abs(velocity(at: time)) < 0.005
    }

    /// Starts a motion that is waiting for its first frame.
    /// - Returns: Whether it started.
    mutating func startIfNeeded(at time: CFTimeInterval) -> Bool {
        guard start == nil, origin != target else { return false }
        start = time
        return true
    }

    mutating func move(to newTarget: CGFloat, at time: CFTimeInterval, animated: Bool) {
        // Later updates that keep the target leave a running motion alone.
        guard newTarget != target else { return }
        guard animated else {
            self = SpringTrack(at: newTarget)
            return
        }
        let current = value(at: time)
        initialVelocity = velocity(at: time)
        origin = current
        target = newTarget
        start = nil
    }
}

final class WorkspaceColumnsView: NSView {
    private struct Island {
        let host: ColumnHostingView
        var view: NSView { host }
        var column: WorkspaceColumnsHost.Column
        var reveal: SpringTrack
        /// What the column reports with `SupplementaryPaneFramePreferenceKey`,
        /// in its hosting view.
        var paneFrame = CGRect.zero
    }

    private var conversation: NSHostingController<AnyView>?
    /// A side chat pane kept for the next one to open (`apply`).
    private var pooledPane: ColumnHostingView?
    /// Back to front.
    private var islands: [Island] = []
    private var widening: SpringTrack?
    private var isMoving = false
    private var supplementaryPaneFrameChanged: (CGRect) -> Void = { _ in }
    private var reportedPaneFrame = CGRect.zero
    private var displayLink: CADisplayLink?

    /// Column widths, measured when the columns change rather than on every
    /// frame of a motion.
    private var paneWidth: CGFloat = 0
    private var inspectorWidth: CGFloat = 0
    private var conversationMinimum: CGFloat = 0
    /// Whether the conversation's minimum width needs measuring again.
    private var needsMeasurement = true

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(revealDidChange(_:)),
            name: WorkspaceLayoutMotion.revealDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(columnsWillChange),
            name: WorkspaceLayoutMotion.willChangeColumns,
            object: nil
        )
    }

    /// Marks the trailing column leaving before a change that may close it,
    /// so it keeps what it shows: a closed column's content is gone by the
    /// time it starts to leave.
    @objc private func columnsWillChange() {
        for island in islands where !island.column.isFullWidth {
            island.host.setContent(island.host.content, isLeaving: true)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Moves the columns toward their reveals. This bypasses the view graph:
    /// updating it to start a motion cost several frames.
    @objc private func revealDidChange(_ notification: Notification) {
        let animates = notification.userInfo?[WorkspaceLayoutMotion.animatesKey] as? Bool ?? false
        let reveal = WorkspaceMotionPhase.shared.unobservedReveal
        let now = CACurrentMediaTime()
        for index in islands.indices {
            let target = reveal[islands[index].column.id] ?? 1
            islands[index].reveal.move(to: target, at: now, animated: animates)
            let host = islands[index].host
            if animates, target == 1, host.isLeaving { host.setContent(host.content, isLeaving: false) }
        }
        layoutColumns(at: now)
        if isAnimating(at: now) { startMotion() }
    }

    func apply(_ spec: WorkspaceColumnsHost, environment: EnvironmentValues, animates: Bool) {
        let now = CACurrentMediaTime()
        supplementaryPaneFrameChanged = spec.supplementaryPaneFrameChanged
        if isMoving != spec.isMoving {
            isMoving = spec.isMoving
            needsMeasurement = true
        }

        let conversationRoot = AnyView(spec.conversation.environment(\.self, environment))
        if let conversation {
            conversation.rootView = conversationRoot
        } else {
            let host = Self.makeHost(conversationRoot)
            addSubview(host.view, positioned: .below, relativeTo: nil)
            conversation = host
        }

        var updated: [Island] = []
        for column in spec.columns {
            let root = AnyView(
                column.content
                    .environment(\.self, environment)
                    .onPreferenceChange(SupplementaryPaneFramePreferenceKey.self) { [weak self] frame in
                        MainActor.assumeIsolated { self?.columnReported(frame, id: column.id) }
                    }
            )
            if var island = islands.first(where: { $0.column.id == column.id }) {
                // A column marked leaving before the change stays so until
                // it comes back in or the motion settles: updates within the
                // change can run before the column is listed as departing.
                let isLeaving = column.isDeparting || island.host.isLeaving && WorkspaceLayoutMotion.isMoving
                island.host.setContent(root, isLeaving: isLeaving)
                if island.column.isDeparting != column.isDeparting
                    || island.column.isFullWidth != column.isFullWidth
                {
                    needsMeasurement = true
                }
                island.column = column
                updated.append(island)
            } else {
                let reveal = WorkspaceMotionPhase.shared.unobservedReveal[column.id] ?? 1
                updated.append(Island(host: makeHost(for: column, root), column: column, reveal: SpringTrack(at: reveal)))
                needsMeasurement = true
            }
        }
        for island in islands where !updated.contains(where: { $0.view === island.view }) {
            // The last side chat pane stays, hidden, for the next one: a pane
            // built from nothing costs most of a motion's first frame.
            if island.column.isSideConversation, !island.column.isFullWidth, pooledPane == nil {
                island.host.isHidden = true
                pooledPane = island.host
            } else {
                island.view.removeFromSuperview()
            }
        }
        islands = updated
        var below: NSView? = conversation?.view
        for island in islands {
            let view = island.view
            if view.superview !== self
                || subviews.firstIndex(of: view)! < below.flatMap { subviews.firstIndex(of: $0) } ?? 0
            {
                addSubview(view, positioned: .above, relativeTo: below)
            }
            below = view
        }

        switch spec.widening {
        case nil: widening = nil
        case .starting: widening = SpringTrack(at: 0)
        case .arriving:
            var track = widening ?? SpringTrack(at: 0)
            track.move(to: 1, at: now, animated: animates)
            widening = track
        }

        layoutColumns(at: now)
        // A column that arrives builds and measures its content now, out of
        // view, rather than on the motion's first frame.
        let arriving = islands.filter { !$0.host.extent.isMeasured }
        if !arriving.isEmpty {
            for island in arriving { island.host.layoutSubtreeIfNeeded() }
            needsMeasurement = true
            layoutColumns(at: now)
        }
        if isAnimating(at: now) { startMotion() }
    }

    /// A hosting view for a column that arrives: the pooled pane, for a
    /// side chat pane, or a new one.
    private func makeHost(for column: WorkspaceColumnsHost.Column, _ root: AnyView) -> ColumnHostingView {
        guard column.isSideConversation, !column.isFullWidth, let pooled = pooledPane else {
            return ColumnHostingView(content: root, sharesExtent: column.isSideConversation)
        }
        pooledPane = nil
        pooled.isHidden = false
        pooled.setContent(root, isLeaving: false)
        return pooled
    }

    func stopMotion() {
        displayLink?.invalidate()
        displayLink = nil
    }

    override func layout() {
        super.layout()
        layoutColumns(at: CACurrentMediaTime())
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { needsMeasurement = true }
        super.setFrameSize(newSize)
    }

    private static func makeHost(_ root: AnyView) -> NSHostingController<AnyView> {
        let host = NSHostingController(rootView: root)
        // This view sets every frame; the hosting view never asks for one.
        host.sizingOptions = []
        host.view.translatesAutoresizingMaskIntoConstraints = true
        return host
    }

    private func startMotion() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        var started = widening?.startIfNeeded(at: link.timestamp) ?? false
        for index in islands.indices where islands[index].reveal.startIfNeeded(at: link.timestamp) {
            started = true
        }
        // Columns leave once the motion settles, which must not come before
        // they are out of view.
        if started { WorkspaceLayoutMotion.extendSettling() }
        // Placed for the moment the frame reaches the screen.
        let time = link.targetTimestamp
        layoutColumns(at: time)
        if !isAnimating(at: time) { stopMotion() }
    }

    private func isAnimating(at time: CFTimeInterval) -> Bool {
        islands.contains { !$0.reveal.isSettled(at: time) } || widening.map { !$0.isSettled(at: time) } ?? false
    }

    /// Reads the columns' widths from their last layout.
    private func measureColumns() {
        let height = bounds.height
        let inspector = islands.last { !$0.column.isSideConversation && !$0.column.isDeparting }?.host.extent
        if let inspector, inspector.isMeasured {
            inspectorWidth = inspector.ideal
        }
        guard let pane = islands.last(where: {
            $0.column.isSideConversation && !$0.column.isFullWidth && !$0.column.isDeparting
        })?.host.extent, pane.isMeasured, bounds.width > 0 else { return }
        if needsMeasurement {
            needsMeasurement = false
            conversationMinimum = conversation?.sizeThatFits(in: CGSize(width: 0, height: height)).width ?? 0
        }
        // As an HStack does, give the pane its widest size the
        // conversation's minimum width leaves room for.
        let available = max(0, bounds.width - (inspector == nil ? 0 : inspectorWidth) - conversationMinimum)
        paneWidth = min(max(available, pane.minimum), pane.maximum)
    }

    private func width(of column: WorkspaceColumnsHost.Column) -> CGFloat {
        column.isSideConversation
            ? max(paneWidth, InterfaceScale.metric(340))
            : max(inspectorWidth, ChatChromeMetrics.memberListWidth)
    }

    /// Places every island where the motion has it at `time`.
    private func layoutColumns(at time: CFTimeInterval) {
        measureColumns()
        let bounds = bounds
        // How much of the trailing edge the columns cover, which the
        // conversation gives up, and how much of it inspectors cover, which
        // a full-width side chat gives up.
        var covered: CGFloat = 0
        var inspectorCovered: CGFloat = 0
        for island in islands where !island.column.isFullWidth {
            let width = width(of: island.column)
            let shown = width * island.reveal.value(at: time)
            covered = max(covered, shown)
            if !island.column.isSideConversation { inspectorCovered = max(inspectorCovered, shown) }
            setFrame(of: island.view, CGRect(x: bounds.maxX - shown, y: 0, width: width, height: bounds.height))
        }
        if let fullWidth = islands.last(where: \.column.isFullWidth) {
            let paneWidth = max(paneWidth, InterfaceScale.metric(340))
            let trailingEdge = bounds.maxX - inspectorCovered
            let width = widening.map { paneWidth + (trailingEdge - paneWidth) * $0.value(at: time) } ?? trailingEdge
            setFrame(of: fullWidth.view, CGRect(x: trailingEdge - width, y: 0, width: width, height: bounds.height))
            // The conversation keeps the width it had beside the pane while
            // the side chat widens over it.
            covered = paneWidth
        }
        setFrame(of: conversation?.view, CGRect(x: 0, y: 0, width: max(0, bounds.width - covered), height: bounds.height))
        reportPaneFrame()
        publishGeometry(at: time)
    }

    /// Tells the toolbar where the columns are, so their items move with
    /// them in the same frame.
    private func publishGeometry(at time: CFTimeInterval) {
        guard window != nil else { return }
        let conversationFrame = conversation.map { convert($0.view.frame, to: nil) }
        let widening = widening?.value(at: time) ?? 1
        WorkspaceColumnsGeometry.shared.update(
            conversation: conversationFrame.map { $0.minX ... $0.maxX },
            columns: islands.map { island in
                let frame = convert(island.view.frame, to: nil)
                return WorkspaceColumnsGeometry.Column(
                    id: island.column.id,
                    minX: frame.minX,
                    maxX: frame.maxX,
                    isFullWidth: island.column.isFullWidth,
                    widening: island.column.isFullWidth ? widening : 0
                )
            }
        )
    }

    private func setFrame(of view: NSView?, _ frame: CGRect) {
        guard let view, view.frame != frame else { return }
        view.frame = frame
    }

    private func columnReported(_ frame: CGRect, id: String) {
        guard let index = islands.firstIndex(where: { $0.column.id == id }) else { return }
        // Global coordinates are the window's, so they follow the island as
        // it slides; keep the frame relative to the island.
        let origin = rootOrigin(of: islands[index].view.frame.origin) ?? .zero
        islands[index].paneFrame = frame == .zero ? .zero : frame.offsetBy(dx: -origin.x, dy: -origin.y)
        reportPaneFrame()
    }

    /// A point in this view in the window's SwiftUI global coordinates.
    private func rootOrigin(of point: CGPoint) -> CGPoint? {
        guard let root = window?.contentView else { return nil }
        var origin = convert(point, to: root)
        if !root.isFlipped { origin.y = root.bounds.height - origin.y }
        return origin
    }

    /// Reports the frontmost column's pane frame where its column rests, as
    /// the SwiftUI layout did, so the toolbar does not follow the motion.
    private func reportPaneFrame() {
        var frame = CGRect.zero
        if let island = islands.last(where: { $0.paneFrame != .zero }),
           let origin = rootOrigin(of: CGPoint(
               x: island.column.isFullWidth ? 0 : bounds.maxX - width(of: island.column),
               y: 0
           ))
        {
            // On the pixel grid: the frame picks up rounding error as the
            // column moves, and the toolbar lays out again for any change.
            let scale = window?.backingScaleFactor ?? 2
            let resting = island.paneFrame.offsetBy(dx: origin.x, dy: origin.y)
            frame = CGRect(
                x: (resting.minX * scale).rounded() / scale,
                y: (resting.minY * scale).rounded() / scale,
                width: (resting.width * scale).rounded() / scale,
                height: (resting.height * scale).rounded() / scale
            )
        }
        guard frame != reportedPaneFrame else { return }
        reportedPaneFrame = frame
        // Reports can come in the middle of a SwiftUI update.
        DispatchQueue.main.async { [weak self] in
            guard let self, reportedPaneFrame == frame else { return }
            supplementaryPaneFrameChanged(frame)
        }
    }
}

/// A column's hosting view.
private final class ColumnHostingView: NSHostingView<AnyView> {
    /// The widths the column's content takes, measured as it lays out.
    let extent = ColumnExtent()
    /// The column's content, without how this view presents it.
    private(set) var content = AnyView(EmptyView())
    /// Whether the column is leaving: it shows what it showed when it began
    /// to (`isLeavingWorkspace`) and takes no events.
    private(set) var isLeaving = false

    /// - Parameter sharesExtent: Whether its widths are the same for every
    ///   column of its kind, as a side chat pane's are, so a new one reuses
    ///   the last one's instead of measuring its content again.
    convenience init(content: AnyView, sharesExtent: Bool) {
        self.init(rootView: AnyView(EmptyView()))
        extent.isShared = sharesExtent
        // This view's frame is set from outside; it never asks for one.
        sizingOptions = []
        translatesAutoresizingMaskIntoConstraints = true
        setContent(content, isLeaving: false)
    }

    func setContent(_ content: AnyView, isLeaving: Bool) {
        self.content = content
        self.isLeaving = isLeaving
        rootView = AnyView(
            ColumnMeasuringLayout(extent: extent) {
                content.environment(\.isLeavingWorkspace, isLeaving)
            }
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isLeaving ? nil : super.hitTest(point)
    }
}

/// How wide a column's content can be: at least `minimum`, ideally `ideal`
/// and at most `maximum`.
nonisolated private final class ColumnExtent: @unchecked Sendable {
    var minimum: CGFloat = 0
    var ideal: CGFloat = 0
    var maximum: CGFloat = 0
    var height: CGFloat = 0
    var isMeasured = false
    var isShared = false

    /// The last shared measurement, which takes laying out a whole pane.
    nonisolated(unsafe) private static var shared: ColumnExtent?

    /// Takes the shared measurement for this height, if there is one.
    func adoptShared(height: CGFloat) -> Bool {
        guard isShared, let shared = Self.shared, shared.height == height else { return false }
        minimum = shared.minimum
        ideal = shared.ideal
        maximum = shared.maximum
        self.height = height
        isMeasured = true
        return true
    }

    func share() {
        guard isShared else { return }
        Self.shared = self
    }
}

/// Fills its bounds with its content and records the content's widths, so
/// the column's width is known without measuring it separately.
nonisolated private struct ColumnMeasuringLayout: Layout {
    let extent: ColumnExtent

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let content = subviews.first else { return }
        content.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        // Once per height: the widths come from the column's frame, not
        // from what it shows.
        let height = bounds.height
        guard !extent.isMeasured || extent.height != height else { return }
        if extent.adoptShared(height: height) { return }
        extent.minimum = content.sizeThatFits(ProposedViewSize(width: 0, height: height)).width
        extent.ideal = content.sizeThatFits(ProposedViewSize(width: nil, height: height)).width
        extent.maximum = content.sizeThatFits(ProposedViewSize(width: .infinity, height: height)).width
        extent.height = height
        extent.isMeasured = true
        extent.share()
    }
}

extension EnvironmentValues {
    /// Whether this view is in a workspace column that is sliding away
    /// (`WorkspaceColumnsHost`). Until it is out of view it keeps showing
    /// what it showed, though the model has closed it.
    @Entry var isLeavingWorkspace = false
}
