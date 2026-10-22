import AppKit
import SwiftUI

/// Hosts the conversation's footer (the composer) in a view graph of its
/// own, so a column sliding over the conversation narrows it on every frame
/// without laying the conversation out again.
///
/// While the member list or search results slide over the conversation,
/// the conversation keeps its wider width (`WorkspaceColumnsView`). The
/// footer's own hosting view follows the column's edge
/// (`WorkspaceConversationCover`): its trailing controls move with the edge
/// and its text wraps for the width it has, from frame to frame. Laying
/// the footer out inside the conversation's graph cost most of each frame.
struct ConversationFooterHost<Content: View>: View {
    @ViewBuilder let content: Content
    /// Advances when the footer's own height changes, so the enclosing
    /// layout measures it again.
    @State private var heightRevision = 0

    var body: some View {
        ConversationFooterRepresentable(content: content, heightRevision: heightRevision) {
            heightRevision &+= 1
        }
    }
}

private struct ConversationFooterRepresentable<Content: View>: NSViewRepresentable {
    let content: Content
    let heightRevision: Int
    let heightDidChange: () -> Void

    func makeNSView(context _: Context) -> ConversationFooterContainerView {
        ConversationFooterContainerView()
    }

    func updateNSView(_ view: ConversationFooterContainerView, context: Context) {
        view.heightDidChange = heightDidChange
        view.setContent(AnyView(content.environment(\.self, context.environment)))
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView view: ConversationFooterContainerView, context _: Context
    ) -> CGSize? {
        let width = proposal.width ?? view.bounds.width
        return CGSize(width: width, height: view.fittingHeight(width: width))
    }
}

final class ConversationFooterContainerView: NSView {
    private let host = NSHostingController(rootView: AnyView(EmptyView()))
    private var coverObservation: NSObjectProtocol?
    /// The height last reported to the enclosing layout.
    private var reportedHeight: CGFloat?
    var heightDidChange: () -> Void = {}

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        // This view sets the hosting view's frame; it never asks for one.
        host.sizingOptions = []
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        coverObservation = NotificationCenter.default.addObserver(
            forName: WorkspaceConversationCover.didChange, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeHost() }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let coverObservation { NotificationCenter.default.removeObserver(coverObservation) }
    }

    func setContent(_ content: AnyView) {
        host.rootView = AnyView(
            content
                // Its own height, whatever height it is given, reported as it
                // changes: a line wrapping, a reply bar.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] height in
                    self?.contentHeightDidChange(height)
                }
        )
        needsLayout = true
    }

    func fittingHeight(width: CGFloat) -> CGFloat {
        let height = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        reportedHeight = height
        return height
    }

    override func layout() {
        super.layout()
        placeHost()
    }

    /// Clear of a column sliding over the conversation, in the frame that
    /// moves it.
    private func placeHost() {
        let inset = WorkspaceConversationCover.shared.trailingInset
        let frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - inset), height: bounds.height)
        guard host.view.frame != frame else { return }
        let wasCovered = host.view.frame.width < bounds.width
        host.view.frame = frame
        host.view.layoutSubtreeIfNeeded()
        // Uncovered again: a line that wrapped differently under the column
        // may have changed the footer's height.
        if inset == 0, wasCovered, let reportedHeight,
           abs(fittingHeight(width: bounds.width) - reportedHeight) >= 0.5
        {
            heightDidChange()
        }
    }

    /// Once nothing covers the footer, a new height goes to the enclosing
    /// layout. Under a sliding column it waits for the column to settle.
    private func contentHeightDidChange(_ height: CGFloat) {
        guard WorkspaceConversationCover.shared.trailingInset == 0,
              let reportedHeight, abs(height - reportedHeight) >= 0.5
        else { return }
        self.reportedHeight = height
        heightDidChange()
    }
}
