import SwiftUI

/// A side chat's title in the window toolbar. It fills a fixed width from the
/// pane's leading inset, truncating within it, so title changes never move it.
struct SideConversationToolbarTitle: View {
    let label: SideConversationLabel
    /// Nil until the toolbar has laid the item out once.
    let width: CGFloat?

    var body: some View {
        ConversationToolbarLabel(
            title: label.title,
            systemImage: label.systemImage,
            subtitle: nil,
            textSize: InterfaceTypographyMetrics.interfaceTextSize
        )
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: Capsule())
        // Flexible below its ideal width, so a stale width compresses the
        // title instead of overflowing the pane's actions while it updates.
        .frame(idealWidth: width, maxWidth: width, alignment: .leading)
        .opacity(width == nil ? 0 : 1)
    }
}
