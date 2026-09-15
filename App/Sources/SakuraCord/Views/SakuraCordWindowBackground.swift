import AppKit
import Darwin
import OSLog
import SwiftUI

struct SakuraCordWindowBackground: ViewModifier {
    let opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let usesBlur = !reduceTransparency && SakuraCordWindowBlur.isAvailable
        let themeOpacity = usesBlur
            ? 0.35 + 0.65 * AppearanceSettingsSnapshot.normalizedWindowOpacity(opacity)
            : 1
        content
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
                WindowBlurBridge(isEnabled: usesBlur)
                    .accessibilityHidden(true)
            }
            .containerBackground(.clear, for: .window)
    }
}

private struct WindowBlurBridge: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> BackingView { BackingView() }

    func updateNSView(_ nsView: BackingView, context: Context) {
        nsView.isBlurEnabled = isEnabled
        nsView.updateWindow()
    }

    final class BackingView: NSView {
        var isBlurEnabled = false
        private weak var configuredWindow: NSWindow?
        private var appliedRadius: UInt?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindow()
        }

        func updateWindow() {
            guard let window else { return }
            let radius: UInt = isBlurEnabled ? 64 : 0
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
