import SwiftUI

/// Profile editors use the same window host, dimming and closing animation as
/// Forward. A stable context lets nested editors dismiss only their own layer.
@MainActor
final class ProfileEditorModalContext {
    let animationState: WindowModalAnimationState
    let depth: Int

    init(animationState: WindowModalAnimationState, depth: Int) {
        self.animationState = animationState
        self.depth = depth
    }

    func callAsFunction(allowsDisabled: Bool = false) {
        if allowsDisabled { animationState.preventsDismissal = false }
        animationState.dismiss(committingPresentation: true)
    }
}

extension EnvironmentValues {
    @Entry var profileEditorModal: ProfileEditorModalContext?
    @Entry var profileEditorModalAvailableSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    @Entry var profileAnimationsPaused = false
}

extension View {
    func profileEditorOverlay<Item: Identifiable, Modal: View>(
        item: Binding<Item?>,
        title: LocalizedStringResource? = nil,
        @ViewBuilder content: @escaping (Item) -> Modal
    ) -> some View {
        modifier(ProfileEditorOverlayModifier(item: item, title: title, modal: content))
    }

    func profileEditorOverlay<Modal: View>(
        isPresented: Binding<Bool>,
        title: LocalizedStringResource? = nil,
        @ViewBuilder content: @escaping () -> Modal
    ) -> some View {
        profileEditorOverlay(item: Binding(
            get: { isPresented.wrappedValue ? ProfileEditorBooleanPresentation() : nil },
            set: { isPresented.wrappedValue = $0 != nil }
        ), title: title) { _ in content() }
    }

    func profileEditorModalSize(width: CGFloat, height: CGFloat? = nil) -> some View {
        modifier(ProfileEditorModalSize(width: width, height: height))
    }

    func profileEditorDismissDisabled(_ disabled: Bool) -> some View {
        modifier(ProfileEditorDismissGuard(disabled: disabled))
    }
}

private struct ProfileEditorBooleanPresentation: Identifiable { let id = "presented" }

private struct ProfileEditorOverlayModifier<Item: Identifiable, Modal: View>: ViewModifier {
    @Binding var item: Item?
    let title: LocalizedStringResource?
    @ViewBuilder let modal: (Item) -> Modal
    @Environment(\.profileEditorModal) private var parent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let depth = (parent?.depth ?? 0) + 1
        content.background {
            WindowModalOverlay(presentation: item, zPosition: CGFloat(100_100 + depth * 10), dismiss: { item = nil }, content: { item, animationState in
                ProfileEditorOverlaySurface(animationState: animationState, depth: depth, title: title) { modal(item) }
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.locale, locale)
            })
        }
    }
}

private struct ProfileEditorOverlaySurface<Content: View>: View {
    let animationState: WindowModalAnimationState
    let title: LocalizedStringResource?
    @ViewBuilder let content: () -> Content
    @State private var context: ProfileEditorModalContext

    init(animationState: WindowModalAnimationState, depth: Int, title: LocalizedStringResource?, @ViewBuilder content: @escaping () -> Content) {
        self.animationState = animationState
        self.title = title
        self.content = content
        _context = State(initialValue: ProfileEditorModalContext(animationState: animationState, depth: depth))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(WindowModalVisualStyle.menuBackgroundDimmingOpacity)
                    .ignoresSafeArea().contentShape(Rectangle()).onTapGesture { context() }
                GlassEffectContainer(spacing: 0) {
                    VStack(spacing: 0) {
                        if let title {
                            HStack {
                                Text(title).font(.headline)
                                Spacer()
                                HoverCloseButton(help: "Close", accessibilityIdentifier: "profile-editor-close") { context() }
                            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
                        }
                        content()
                    }
                    .fixedSize()
                    .background(Color(nsColor: .windowBackgroundColor), in: ConcentricRectangle(cornerRadius: 16, style: .continuous))
                    .clipShape(ConcentricRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .overlay { ConcentricRectangle(cornerRadius: 16, style: .continuous).stroke(.separator, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
                    .scaleEffect(animationState.isVisible ? 1 : 0.965)
                    .padding(24)
                    .environment(\.profileEditorModal, context)
                    .environment(\.profileEditorModalAvailableSize, CGSize(width: max(0, geometry.size.width - 48), height: max(0, geometry.size.height - 48 - (title == nil ? 0 : 56))))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .focusable().focusEffectDisabled().accessibilityAddTraits(.isModal)
        .animation(.easeOut(duration: WindowModalAnimationTiming.openingSeconds), value: animationState.isVisible)
        .onExitCommand { context() }
    }
}

private struct ProfileEditorModalSize: ViewModifier {
    let width: CGFloat
    let height: CGFloat?
    @Environment(\.profileEditorModalAvailableSize) private var available
    func body(content: Content) -> some View {
        content.frame(width: min(width, available.width), height: height.map { min($0, available.height) })
    }
}

private struct ProfileEditorDismissGuard: ViewModifier {
    let disabled: Bool
    @Environment(\.profileEditorModal) private var context
    func body(content: Content) -> some View {
        content.onChange(of: disabled, initial: true) { _, disabled in context?.animationState.preventsDismissal = disabled }
    }
}
