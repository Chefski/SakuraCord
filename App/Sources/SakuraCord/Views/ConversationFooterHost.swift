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
        // The host reaches above this view's top edge (`placeHost`).
        clipsToBounds = false
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
                // Held to the bottom of a host that stays put, so the footer
                // grows and shrinks from its top edge on its own animation.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        )
        measured = nil
        needsLayout = true
    }

    /// The footer's height in a conversation `width` wide, at the width a
    /// sliding column leaves it.
    func fittingHeight(width proposed: CGFloat) -> CGFloat {
        let width = max(0, proposed - WorkspaceConversationCover.shared.trailingInset)
        // A resizing conversation asks on every frame; the composer is
        // measured again only at a new width or after its content changed.
        if let measured, abs(measured.width - width) < 0.5 {
            reportedHeight = measured.height
            return measured.height
        }
        // No height to spare: the aligning frame fills whatever it is
        // offered, so it reports only the content's own.
        let height = host.sizeThatFits(in: CGSize(width: width, height: 0)).height
        measured = (width, height)
        reportedHeight = height
        return height
    }

    /// The last measurement, for the width it was made at.
    private var measured: (width: CGFloat, height: CGFloat)?

    override func layout() {
        super.layout()
        placeHost()
    }

    /// Taller than any footer. The host keeps this height on this view's
    /// bottom edge: had it followed the footer's new height, its top would
    /// jump at once, a frame after the content began animating from it.
    private static let hostHeight: CGFloat = 4096

    /// Clear of a column sliding over the conversation, in the frame that
    /// moves it.
    private func placeHost() {
        let inset = WorkspaceConversationCover.shared.trailingInset
        let height = max(bounds.height, Self.hostHeight)
        let frame = CGRect(
            x: 0, y: bounds.height - height, width: max(0, bounds.width - inset), height: height
        )
        guard host.view.frame != frame else { return }
        host.view.frame = frame
        // A line that wraps differently at the new width reports the
        // footer's new height (`contentHeightDidChange`).
        host.view.layoutSubtreeIfNeeded()
    }

    /// A new height goes to the enclosing layout, under a sliding column
    /// too: the timeline above keeps clear of a draft that wraps a line.
    private func contentHeightDidChange(_ height: CGFloat) {
        // Laid out at its own width, the content's height is its measure.
        measured = (host.view.frame.width, height)
        guard let reportedHeight, abs(height - reportedHeight) >= 0.5 else { return }
        self.reportedHeight = height
        heightDidChange()
    }
}
