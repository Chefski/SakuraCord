import AppKit
import SwiftUI

/// Animates the workspace layout changes the reader asks for (opening,
/// closing or widening a side chat, toggling the member list) with the member
/// list's spring. Navigation changes the layout without it and appears at once.
///
/// A change commits its final layout in one frame and nothing is laid out
/// again until the motion settles: a trailing column slides in or out as an
/// offset over the conversation, which keeps its width meanwhile, is clipped
/// at the column's edge, and narrows once the column has arrived. Relaying
/// out the workspace on every frame cost about 50 ms per frame on an 8 GB
/// Mac. Work that would block the main thread for several frames (a pane's
/// content, a thread's first page, a timeline's full reflow, toolbar item
/// changes) waits for the motion to settle so the motion keeps every frame.
@MainActor
enum WorkspaceLayoutMotion {
    /// Lets the motion benchmark reach each layout's static reference.
    static var isSuppressedForBenchmark = false

    /// Posted on the main thread as a motion begins and once it settles.
    static let didBegin = Notification.Name("SakuraCordWorkspaceMotionDidBegin")
    static let didSettle = Notification.Name("SakuraCordWorkspaceMotionDidSettle")

    /// When the running motion settles.
    private(set) static var settlesAt: ContinuousClock.Instant?
    /// Reflow crossfades started so far; the motion benchmark records it.
    private(set) static var reflowCrossfadeCount = 0

    static var animation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || isSuppressedForBenchmark
            ? nil : .spring(ChatChromeMetrics.sidebarSpring)
    }

    static var isMoving: Bool {
        settlesAt.map { ContinuousClock.now < $0 } ?? false
    }

    /// Whether a conversation that changes width now should crossfade its
    /// reflow: during a motion and as the conversation narrows after it.
    static var crossfadesReflow: Bool {
        settlesAt.map { ContinuousClock.now < $0 + .milliseconds(300) } ?? false
    }

    /// Until the spring is within a thousandth of its target. SwiftUI keeps
    /// animating past `Spring.settlingDuration`, which is shorter.
    private static var settling: Duration {
        .seconds(9.3 * ChatChromeMetrics.sidebarSpring.duration / (2 * .pi))
    }

    /// Opens, closes or swaps the workspace's trailing column.
    static func perform(in model: AppModel, _ change: () -> Void) {
        guard let animation else {
            withAnimation(nil, change)
            return
        }
        let before = model.workspacePresentation
        beginMotion(freezing: before)
        let phase = WorkspaceMotionPhase.shared
        let leaving = WorkspaceTrailingColumn(before)
        crossfadeWorkspace()
        withAnimation(nil, change)
        let arriving = WorkspaceTrailingColumn(model.workspacePresentation)
        guard leaving?.id != arriving?.id else { return }
        // Each write to the phase invalidates its observers, so write once.
        var departing = phase.departing.filter { $0.id != leaving?.id && $0.id != arriving?.id }
        if let leaving {
            // The column that leaves stays until it is out of view, beneath
            // any column that arrives.
            departing.append(leaving)
        }
        if departing != phase.departing { phase.departing = departing }
        if let arriving, phase.reveal[arriving.id] == nil {
            phase.reveal[arriving.id] = 0
        }
        // Columns move from the frame that commits the change: an arriving
        // column from beyond the trailing edge, or from wherever it is if it
        // was still leaving.
        afterCommit(animation) {
            if let leaving { phase.reveal[leaving.id] = 0 }
            if let arriving { phase.reveal[arriving.id] = 1 }
        }
    }

    /// Moves the open side chat from the pane to full width. The layout
    /// changes at once; the side chat then slides from the pane's edge over
    /// the conversation, which stays beneath it until it is covered.
    static func widen(in model: AppModel, _ change: () -> Void) {
        let before = model.workspacePresentation
        guard let animation, case .channel(let channel) = before.primary else {
            withAnimation(nil, change)
            return
        }
        beginMotion(freezing: before)
        let phase = WorkspaceMotionPhase.shared
        withAnimation(nil) {
            phase.widening = .init(channel: channel, hasArrived: false)
            change()
        }
        afterCommit(animation) { phase.widening?.hasArrived = true }
    }

    /// Animates `change` once the frame that commits the layout has been
    /// laid out, which can take a while; the motion settles a spring's
    /// duration after that.
    private static func afterCommit(_ animation: Animation, _ change: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                settlesAt = .now + settling
                withAnimation(animation, change)
            }
        }
    }

    /// Returns once no motion is running.
    /// Returns early if the waiting task is cancelled.
    static func untilSettled() async {
        while let settlesAt, ContinuousClock.now < settlesAt {
            do {
                try await Task.sleep(until: settlesAt)
            } catch {
                return
            }
        }
    }

    /// A render-server crossfade from a layer tree's current rendering to the
    /// next one, so a reflow at a new width blends in instead of jumping.
    static func reflowTransition() -> CATransition {
        reflowCrossfadeCount &+= 1
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.18
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return transition
    }

    /// Crossfades the workspace window from its current rendering to the
    /// next commit, on the render server: the conversation reflowing at a
    /// new width, a pane's content appearing or leaving, toolbar items.
    private static func crossfadeWorkspace() {
        let window = NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
        window?.contentView?.layer?.add(reflowTransition(), forKey: "workspaceMotion")
    }

    private static func beginMotion(freezing presentation: WorkspacePresentation) {
        let phase = WorkspaceMotionPhase.shared
        settlesAt = .now + settling
        if phase.toolbarPresentation == nil { phase.toolbarPresentation = presentation }
        if !phase.isMoving {
            phase.isMoving = true
            NotificationCenter.default.post(name: didBegin, object: nil)
        }
        phase.settleTask?.cancel()
        phase.settleTask = Task {
            await untilSettled()
            guard !Task.isCancelled else { return }
            // The conversation's new width, the pane's content and the
            // toolbar's items arrive together; blend them in.
            crossfadeWorkspace()
            // Each write invalidates the phase's readers, so skip no-ops.
            withAnimation(nil) {
                phase.isMoving = false
                if phase.widening != nil { phase.widening = nil }
                if phase.toolbarPresentation != nil { phase.toolbarPresentation = nil }
                if !phase.departing.isEmpty { phase.departing.removeAll() }
                if !phase.reveal.isEmpty { phase.reveal.removeAll() }
            }
            NotificationCenter.default.post(name: didSettle, object: nil)
        }
    }
}

/// A column that slides in at the workspace's trailing edge: a side chat
/// pane or the inspector (member list or search results).
struct WorkspaceTrailingColumn: Identifiable, Equatable {
    enum Content: Equatable {
        case sideConversation(SideConversation)
        case inspector(SupplementaryPane)
    }

    let content: Content
    /// Which content the column shows, ignoring changes to it.
    let id: String

    /// The column at the trailing edge of a workspace, if any. A full-width
    /// thread is not one; the inspector beside it is.
    init?(_ presentation: WorkspacePresentation) {
        switch presentation.supplementaryPane {
        case .sideConversation(let conversation)?: self.init(.sideConversation(conversation))
        case let pane?: self.init(.inspector(pane))
        case nil: return nil
        }
    }

    init(_ content: Content) {
        self.content = content
        id = switch content {
        case .sideConversation(let conversation): "side-\(conversation.motionIdentity)"
        case .inspector(.memberInspector): "members"
        case .inspector: "search"
        }
    }
}

extension SideConversation {
    /// Which side chat this is, ignoring whether it is in the pane or at
    /// full width.
    var motionIdentity: String {
        switch self {
        case .thread(let thread, _): "thread-\(thread.id)"
        case .threadCreation: "thread-creation"
        case .voiceChat(let channelID): "voice-\(channelID)"
        case .guideResource(_, let channelID): "resource-\(channelID)"
        case .channelPreview(let channelID, _): "preview-\(channelID)"
        }
    }
}

/// Workspace state that exists only while a motion runs.
@MainActor
@Observable
final class WorkspaceMotionPhase {
    struct Widening {
        /// The conversation kept beneath the widening side chat.
        let channel: WorkspacePresentation.ChannelContent
        /// Whether the side chat is sliding to the leading edge yet.
        var hasArrived: Bool
    }

    static let shared = WorkspaceMotionPhase()

    /// Whether a motion runs. The conversation keeps its width meanwhile and
    /// narrows once a column has arrived over it.
    var isMoving = false
    var widening: Widening?
    /// The workspace the toolbar shows until the motion settles.
    var toolbarPresentation: WorkspacePresentation?
    /// Columns that have left the workspace but are still sliding away.
    var departing: [WorkspaceTrailingColumn] = []
    /// How far each moving column has come in, from 0 (beyond the trailing
    /// edge) to 1 (in place). Columns at rest are absent.
    var reveal: [String: CGFloat] = [:]
    @ObservationIgnored fileprivate var settleTask: Task<Void, Never>?

    private init() {}

    func reveal(of id: String) -> CGFloat {
        reveal[id] ?? 1
    }
}
