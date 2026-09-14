import AppKit
import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileDisplayName: View {
    let name: String
    let style: DisplayNameStyle?
    var size: CGFloat = 22
    var showsEffects = true
    var loops = false
    var animationIsActive: Bool?
    var background: Color = Color(nsColor: .controlBackgroundColor)
    var plainColor: Color = .primary
    var wraps = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadedFont: NSFont?
    @State private var fontError: String?
    @State private var animationStart: Date?
    @State private var animationFinished = false

    private var definition: ProfileNameFont? {
        ProfileNameFontCache.customDefinition(for: style?.fontID)
    }

    private var duration: Double {
        style?.effectID == ProfileNameEffect.prism.rawValue ? 2 : 4 + Double(name.count) * 0.05
    }

    var body: some View {
        Group {
            if let style {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || animationStart == nil || animationFinished)) { timeline in
                    ProfileNameNativeText(
                        name: name, font: loadedFont ?? .systemFont(ofSize: size, weight: .bold),
                        tracking: CGFloat(definition?.letterSpacing ?? 0) * size,
                        style: style, showsEffects: showsEffects,
                        background: NSColor(background),
                        plainColor: NSColor(plainColor),
                        elapsed: reduceMotion ? 0 : animationStart.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0,
                        loops: loops, wraps: wraps
                    )
                    .padding(-max(4 + size * 0.12, size * 0.2))
                }
            } else {
                Text(name).font(.system(size: size, weight: .bold)).lineLimit(wraps ? nil : 1)
                    .textSelection(.enabled)
            }
        }
        .accessibilityLabel(name)
        .help(fontError ?? name)
        .task(id: FontRequest(definition: definition, size: size)) {
            loadedFont = nil
            fontError = nil
            guard let definition else { return }
            do {
                loadedFont = try await ProfileNameFontLoader.shared.font(definition, size: size)
            } catch is CancellationError {
                return
            } catch {
                fontError = String(localized: "The display-name font could not be loaded.")
            }
        }
        .onModalHover { hovering in
            guard !loops, animationIsActive == nil else { return }
            animationFinished = false
            animationStart = hovering ? .now : nil
        }
        .onChange(of: style, initial: true) {
            animationFinished = false
            animationStart = loops || animationIsActive == true ? .now : nil
        }
        .onChange(of: animationIsActive) {
            animationFinished = false
            animationStart = loops || animationIsActive == true ? .now : nil
        }
        .task(id: animationStart) {
            guard animationStart != nil, !loops else { return }
            do {
                try await Task.sleep(for: .seconds(duration))
                animationFinished = true
            } catch { return }
        }
    }

    private struct FontRequest: Equatable {
        let definition: ProfileNameFont?
        let size: CGFloat
    }
}

private struct ProfileNameNativeText: NSViewRepresentable {
    let name: String
    let font: NSFont
    let tracking: CGFloat
    let style: DisplayNameStyle
    let showsEffects: Bool
    let background: NSColor
    let plainColor: NSColor
    let elapsed: Double
    let loops: Bool
    let wraps: Bool

    func makeNSView(context: Context) -> ProfileNameTextView { ProfileNameTextView() }

    func updateNSView(_ view: ProfileNameTextView, context: Context) {
        view.configure(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProfileNameTextView, context: Context) -> CGSize? {
        nsView.size(for: proposal.width)
    }
}

private final class ProfileNameTextView: NSView {
    private var name = ""
    private var font = NSFont.systemFont(ofSize: 22, weight: .bold)
    private var tracking: CGFloat = 0
    private var style = DisplayNameStyle()
    private var showsEffects = true
    private var background = NSColor.controlBackgroundColor
    private var plainColor = NSColor.labelColor
    private var elapsed: Double = 0
    private var loops = false
    private var wraps = false
    private var naturalLayout: ProfileNameTextLayout?
    private var fittedLayouts: [ProfileNameTextLayout] = []
    private var fittedWidth: CGFloat?

    private var padding: CGFloat { max(4 + font.pointSize * 0.12, font.pointSize * 0.2) }

    override var intrinsicContentSize: NSSize {
        guard let layout = naturalLayout else { return .zero }
        return CGSize(width: ceil(layout.width + padding * 2), height: ceil(layout.ascent + layout.descent + padding * 2))
    }

    func configure(_ configuration: ProfileNameNativeText) {
        let layoutChanged = name != configuration.name || font != configuration.font || tracking != configuration.tracking || wraps != configuration.wraps
            || (style.effectID == ProfileNameEffect.gummy.rawValue) != (configuration.style.effectID == ProfileNameEffect.gummy.rawValue)
        self.name = configuration.name
        self.font = configuration.font
        self.tracking = configuration.tracking
        self.style = configuration.style
        self.showsEffects = configuration.showsEffects
        self.background = configuration.background
        self.plainColor = configuration.plainColor
        self.elapsed = configuration.elapsed
        self.loops = configuration.loops
        self.wraps = configuration.wraps
        if layoutChanged || naturalLayout == nil {
            naturalLayout = ProfileNameTextLayout(name: name, font: font, tracking: tracking, gummy: style.effectID == 8)
            fittedLayouts = []
            fittedWidth = nil
            invalidateIntrinsicContentSize()
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(name)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let naturalLayout else { return }
        let width = max(0, bounds.width - padding * 2)
        fit(to: width, natural: naturalLayout)
        let effect = showsEffects ? ProfileNameEffect(rawValue: style.effectID) ?? .solid : .solid
        let backdrop = ProfileNameEffectColor(effect == .toon ? NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1) : background)
        let colors = showsEffects ? style.colors.map {
            ProfileNameEffectColor(hex: $0).adjusted(against: backdrop, ratio: effect == .gradient || effect == .prism ? 2.5 : 3)
        } : [ProfileNameEffectColor(plainColor)]
        var top = bounds.height - padding
        for layout in fittedLayouts {
            context.saveGState()
            context.translateBy(x: padding, y: top - layout.ascent)
            ProfileNameEffectPainter.draw(layout, in: context, fontSize: font.pointSize, effect: effect,
                                          colors: colors, elapsed: elapsed, looping: loops)
            context.restoreGState()
            top -= ceil(layout.ascent + layout.descent) + 2
        }
    }

    func size(for proposedWidth: CGFloat?) -> CGSize {
        guard let naturalLayout else { return .zero }
        let width = min(proposedWidth ?? intrinsicContentSize.width, intrinsicContentSize.width)
        fit(to: max(0, width - padding * 2), natural: naturalLayout)
        let height = fittedLayouts.reduce(CGFloat(0)) { $0 + ceil($1.ascent + $1.descent) }
            + CGFloat(max(0, fittedLayouts.count - 1)) * 2 + padding * 2
        return CGSize(width: width, height: height)
    }

    private func fit(to width: CGFloat, natural: ProfileNameTextLayout) {
        guard fittedWidth != width else { return }
        if wraps, natural.width > width, width > 0 {
            fittedLayouts = ProfileNameTextLayout.wrappedLines(name: name, font: font, tracking: tracking, gummy: style.effectID == 8, width: width)
        } else {
            fittedLayouts = [natural.width <= width ? natural : ProfileNameTextLayout(
                name: name, font: font, tracking: tracking, gummy: style.effectID == 8, maximumWidth: width
            )]
        }
        fittedWidth = width
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: String(localized: "Copy Display Name"), action: #selector(copyName), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func copyName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
    }
}
