import AppKit
import Darwin
import OSLog
import SwiftUI

extension EnvironmentValues {
    @Entry var sakuraCordWindowIsFullScreen = false
}

struct SakuraCordWindowBackground: ViewModifier {
    let opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isFullScreen = false

    func body(content: Content) -> some View {
        let usesBlur = !reduceTransparency && SakuraCordWindowBlur.isAvailable
        let themeOpacity = usesBlur && !isFullScreen
            ? 0.35 + 0.65 * AppearanceSettingsSnapshot.normalizedWindowOpacity(opacity)
            : 1
        content
            .environment(\.sakuraCordWindowIsFullScreen, isFullScreen)
            .background {
                // Composite the complete gradient before applying opacity so
                // every stop keeps its position and relative color intensity.
                SakuraCordThemeBackground()
                    .compositingGroup()
                    .opacity(themeOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                // Keep the backdrop stable across slider updates. WindowServer
                // blur changes are not committed with SwiftUI's opacity frame,
                // so disabling blur at 100% can briefly expose the desktop.
                // The fully opaque theme covers the blur at that endpoint.
                WindowBlurBridge(isEnabled: usesBlur, isFullScreen: $isFullScreen)
                    .accessibilityHidden(true)
            }
            .containerBackground(.clear, for: .window)
    }
}

private struct WindowBlurBridge: NSViewRepresentable {
    let isEnabled: Bool
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> BackingView { BackingView() }

    func updateNSView(_ nsView: BackingView, context: Context) {
        nsView.isBlurEnabled = isEnabled
        nsView.fullScreenChanged = { isFullScreen = $0 }
        nsView.updateWindow()
    }

    static func dismantleNSView(_ nsView: BackingView, coordinator: ()) {
        nsView.detach()
    }

    final class BackingView: NSView {
        var isBlurEnabled = false
        var fullScreenChanged: ((Bool) -> Void)?
        private weak var configuredWindow: NSWindow?
        private var appliedRadius: UInt?
        private var observers: [NotificationCenter.ObservationToken] = []
        private var reportTask: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            if let window {
                let center = NotificationCenter.default
                observers = [
                    center.addObserver(of: window, for: NSWindow.DidEnterFullScreenMessage.self) { [weak self] _ in
                        self?.windowModeDidChange()
                    },
                    center.addObserver(of: window, for: NSWindow.DidExitFullScreenMessage.self) { [weak self] _ in
                        self?.windowModeDidChange()
                    },
                ]
            }
            windowModeDidChange()
        }

        private func windowModeDidChange() {
            updateWindow()
            reportTask?.cancel()
            // Attachment can occur during a SwiftUI update. Read the current
            // window on the next actor turn before updating the theme opacity.
            reportTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self else { return }
                fullScreenChanged?(window?.styleMask.contains(.fullScreen) == true)
            }
        }

        func detach() {
            reportTask?.cancel()
            reportTask = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            configuredWindow = nil
            appliedRadius = nil
        }

        func updateWindow() {
            guard let window else { return }
            // WindowServer background blur interferes with repeated scroll
            // gestures in fullscreen. Use the opaque theme in that mode and
            // restore the configured translucent backdrop on returning.
            let radius: UInt = isBlurEnabled && !window.styleMask.contains(.fullScreen) ? 64 : 0
            guard configuredWindow !== window || appliedRadius != radius else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            if SakuraCordWindowBlur.apply(radius: radius, to: window) {
                configuredWindow = window
                appliedRadius = radius
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// Like Warp, use the WindowServer blur rather than an NSVisualEffectView
// material: the latter adds its own tint and does not expose a blur radius.
// These private macOS symbols are resolved at runtime, never linked directly.
@MainActor
enum SakuraCordWindowBlur {
    private typealias ConnectionFunction = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias BlurFunction = @convention(c) (UnsafeMutableRawPointer, Int32, UInt) -> Int32
    private static let logger = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "WindowBlur")
    private static let functions: (connection: ConnectionFunction, blur: BlurFunction)? = {
        guard let library = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY | RTLD_LOCAL
        ) else { return nil }
        guard let connection = dlsym(library, "CGSDefaultConnectionForThread"),
              let blur = dlsym(library, "CGSSetWindowBackgroundBlurRadius")
        else {
            dlclose(library)
            return nil
        }
        // Keep the library loaded for the lifetime of these function pointers.
        return (
            unsafeBitCast(connection, to: ConnectionFunction.self),
            unsafeBitCast(blur, to: BlurFunction.self)
        )
    }()

    static var isAvailable: Bool { functions != nil }

    static func apply(radius: UInt, to window: NSWindow) -> Bool {
        guard let functions, let connection = functions.connection() else { return false }
        let result = functions.blur(connection, Int32(window.windowNumber), radius)
        if result != 0 {
            logger.error("Unable to set window blur radius: \(result)")
        }
        return result == 0
    }
}
