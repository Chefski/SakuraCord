import AppKit
import OSLog
import QuartzCore
import SakuraCordModels
import SwiftUI

/// Offline side chat motion benchmark: opens, closes and widens fixture
/// threads and toggles the member list while recording every display-link
/// frame with the geometry of the workspace columns, the toolbar and the
/// timelines. `script/motion_benchmark_analyze.py` turns the recording into
/// frame pacing, hitch and geometry-continuity metrics. Read-only against
/// the offline fixture.
@MainActor
enum SideChatMotionBenchmark {
    static let logger = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "SideChatMotionBenchmark")
    /// Brackets each action so Instruments captures can be split per action.
    static let signposter = OSSignposter(subsystem: "dev.sakuracord.SakuraCord", category: .pointsOfInterest)

    struct Options {
        var cycles = 6
        var historyDelayMilliseconds = 0
        var threadMessageCount = 150
        var settleSeconds = 1.2

        init(arguments: [String]) {
            func value(_ name: String) -> Int? {
                arguments.lazy.compactMap { argument -> Int? in
                    guard argument.hasPrefix("\(name)=") else { return nil }
                    return Int(argument.dropFirst(name.count + 1))
                }.first
            }
            cycles = value("--motion-cycles") ?? cycles
            historyDelayMilliseconds = value("--motion-history-delay-ms") ?? historyDelayMilliseconds
            threadMessageCount = value("--motion-thread-messages") ?? threadMessageCount
        }
    }

    static func run(model: AppModel, options: Options) async {
        NSApp.activate(ignoringOtherApps: true)
        model.selectedChannelID = ChannelID(rawValue: 210)
        guard let threads = await motionThreads(model: model, count: options.cycles + 1),
              let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let contentView = window.contentView
        else {
            logger.error("Side chat motion benchmark could not find its fixture threads")
            return
        }
        model.showInspector = false
        try? await Task.sleep(for: .seconds(2))

        let recorder = SideChatMotionRecorder(window: window, options: options)
        recorder.start(on: contentView)
        await recorder.idle(seconds: 4, label: "panels-hidden")

        // Static layouts for each state, reached without animation.
        let referenceThread = threads[options.cycles]
        WorkspaceLayoutMotion.isSuppressedForBenchmark = true
        for step in cycleSteps(thread: referenceThread, variant: "reference") {
            step.perform(model)
            try? await Task.sleep(for: .seconds(options.settleSeconds))
            recorder.captureReference(for: step.name)
        }
        WorkspaceLayoutMotion.isSuppressedForBenchmark = false
        await recorder.idle(seconds: 1, label: nil)

        logger.notice("SIDE_CHAT_MOTION_CYCLES_BEGIN")
        for cycle in 0 ..< options.cycles {
            for step in cycleSteps(thread: threads[cycle], variant: nil) {
                recorder.recordAction(step, cycle: cycle)
                let interval = signposter.beginInterval(
                    "SideChatMotionAction", id: signposter.makeSignpostID(),
                    "\(step.name, privacy: .public) \(step.variant ?? "-", privacy: .public) \(cycle, privacy: .public)"
                )
                step.perform(model)
                try? await Task.sleep(for: .seconds(options.settleSeconds))
                signposter.endInterval("SideChatMotionAction", interval)
            }
        }

        let membersOpen = Step(name: "members-open", variant: "idle", movingProbe: "members", edge: "minX") {
            $0.toggleMemberInspector()
        }
        recorder.recordAction(membersOpen, cycle: options.cycles)
        membersOpen.perform(model)
        try? await Task.sleep(for: .seconds(options.settleSeconds))
        await recorder.idle(seconds: 4, label: "members-shown")
        model.toggleMemberInspector()
        try? await Task.sleep(for: .seconds(options.settleSeconds))

        recorder.stop()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakuracord-motion-benchmark.json")
        do {
            try recorder.encoded().write(to: url, options: .atomic)
            logger.notice("SIDE_CHAT_MOTION_BENCHMARK_DONE \(url.path, privacy: .public)")
        } catch {
            logger.error("SIDE_CHAT_MOTION_BENCHMARK_FAILED \(error.localizedDescription, privacy: .public)")
        }
    }

    struct Step {
        let name: String
        let variant: String?
        let movingProbe: String?
        let edge: String?
        let perform: (AppModel) -> Void
    }

    /// One cycle: the member list as the reference motion, a cold and a warm
    /// pane open, the pane close, widening and leaving full width.
    private static func cycleSteps(thread: MessageThreadSummary, variant: String?) -> [Step] {
        [
            Step(name: "members-open", variant: variant, movingProbe: "members", edge: "minX") {
                $0.toggleMemberInspector()
            },
            Step(name: "members-close", variant: variant, movingProbe: "members", edge: "minX") {
                $0.toggleMemberInspector()
            },
            Step(name: "pane-open", variant: variant ?? "cold", movingProbe: "pane", edge: "minX") {
                $0.open(thread)
            },
            Step(name: "pane-close", variant: variant, movingProbe: "pane", edge: "minX") {
                $0.closeSideConversation()
            },
            Step(name: "pane-open", variant: variant ?? "warm", movingProbe: "pane", edge: "minX") {
                $0.open(thread)
            },
            Step(name: "full-width", variant: variant, movingProbe: "pane", edge: "minX") {
                $0.presentOpenThreadFullWidth()
            },
            Step(name: "full-width-close", variant: variant, movingProbe: nil, edge: nil) {
                $0.closeSideConversation()
            },
        ]
    }

    /// The fixture's motion threads, once their starters reached the channel.
    private static func motionThreads(model: AppModel, count: Int) async -> [MessageThreadSummary]? {
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            var seen = Set<ChannelID>()
            let threads = model.messages
                .compactMap(\.thread)
                .filter { $0.name.hasPrefix("Motion thread") && seen.insert($0.id).inserted }
            if threads.count >= count { return Array(threads.prefix(count)) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

/// Records each display-link frame and the main thread's busy periods.
@MainActor
private final class SideChatMotionRecorder: NSObject {
    struct Frame: Encodable {
        let time: Double
        let target: Double
        let callback: Double
        let probes: [String: [Double]]
        let timelines: [WorkspaceMotionProbes.TimelineSample]
        let toolbar: Int
        let crossfades: Int
    }

    struct Action: Encodable {
        let id: Int
        let name: String
        let cycle: Int
        let time: Double
        let variant: String?
        let movingProbe: String?
        let edge: String?
    }

    struct Busy: Encodable {
        let start: Double
        let durationMS: Double
    }

    struct Idle: Encodable {
        let start: Double
        let end: Double
        let label: String
    }

    struct Reference: Encodable {
        let probes: [String: [Double]]
    }

    struct Recording: Encodable {
        let schema = "sakuracord-motion-benchmark/1"
        let configuration: String
        let refreshIntervalMS: Double
        let scenario: [String: Double]
        let spring: [String: Double]
        let window: [String: Double]
        let actions: [Action]
        let frames: [Frame]
        let toolbarSignatures: [String]
        let mainThreadBusy: [Busy]
        let idle: [Idle]
        let references: [String: Reference]
    }

    private let window: NSWindow
    private let options: SideChatMotionBenchmark.Options
    private var displayLink: CADisplayLink?
    private var observer: CFRunLoopObserver?
    private var busyStart: Double?
    private var refreshInterval: Double = 1.0 / 60
    private var frames: [Frame] = []
    private var actions: [Action] = []
    private var busy: [Busy] = []
    private var idleWindows: [Idle] = []
    private var references: [String: Reference] = [:]
    private var toolbarSignatures: [String] = []
    private var toolbarSignatureIndex: [String: Int] = [:]

    init(window: NSWindow, options: SideChatMotionBenchmark.Options) {
        self.window = window
        self.options = options
    }

    func start(on view: NSView) {
        frames.reserveCapacity(8_000)
        let link = view.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { [weak self] _, activity in
            let now = CACurrentMediaTime()
            MainActor.assumeIsolated {
                self?.noteRunLoop(CFRunLoopActivity(rawValue: activity), at: now)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil
    }

    func idle(seconds: Double, label: String?) async {
        let start = CACurrentMediaTime()
        try? await Task.sleep(for: .seconds(seconds))
        if let label {
            idleWindows.append(Idle(start: start, end: CACurrentMediaTime(), label: label))
        }
    }

    func recordAction(_ step: SideChatMotionBenchmark.Step, cycle: Int) {
        actions.append(
            Action(
                id: actions.count,
                name: step.name,
                cycle: cycle,
                time: CACurrentMediaTime(),
                variant: step.variant,
                movingProbe: step.movingProbe,
                edge: step.edge
            )
        )
    }

    func captureReference(for name: String) {
        references[name] = Reference(probes: WorkspaceMotionProbes.shared.probeFrames(in: window))
    }

    func encoded() throws -> Data {
        #if DEBUG
            let configuration = "debug"
        #else
            let configuration = "release"
        #endif
        let recording = Recording(
            configuration: configuration,
            refreshIntervalMS: refreshInterval * 1_000,
            scenario: [
                "cycles": Double(options.cycles),
                "historyDelayMS": Double(options.historyDelayMilliseconds),
                "threadMessageCount": Double(options.threadMessageCount),
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0,
            ],
            spring: [
                "durationS": ChatChromeMetrics.sidebarSpring.duration,
                "bounce": ChatChromeMetrics.sidebarSpring.bounce,
            ],
            window: ["width": window.frame.width, "height": window.frame.height],
            actions: actions,
            frames: frames,
            toolbarSignatures: toolbarSignatures,
            mainThreadBusy: busy,
            idle: idleWindows,
            references: references
        )
        return try JSONEncoder().encode(recording)
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        let callback = CACurrentMediaTime()
        let duration = link.targetTimestamp - link.timestamp
        if duration > 0 { refreshInterval = duration }
        frames.append(
            Frame(
                time: link.timestamp,
                target: link.targetTimestamp,
                callback: callback,
                probes: WorkspaceMotionProbes.shared.probeFrames(in: window),
                timelines: WorkspaceMotionProbes.shared.timelineSamples(in: window),
                toolbar: toolbarSignature(),
                crossfades: WorkspaceLayoutMotion.reflowCrossfadeCount
            )
        )
    }

    private func toolbarSignature() -> Int {
        let signature = (window.toolbar?.visibleItems ?? [])
            .map(\.itemIdentifier.rawValue)
            .joined(separator: ",")
        if let index = toolbarSignatureIndex[signature] { return index }
        toolbarSignatures.append(signature)
        toolbarSignatureIndex[signature] = toolbarSignatures.count - 1
        return toolbarSignatures.count - 1
    }

    private func noteRunLoop(_ activity: CFRunLoopActivity, at now: Double) {
        if activity == .afterWaiting {
            busyStart = now
        } else if let start = busyStart {
            busyStart = nil
            let duration = (now - start) * 1_000
            if duration >= 4 { busy.append(Busy(start: start, durationMS: duration)) }
        }
    }
}
