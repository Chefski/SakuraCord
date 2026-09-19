import SwiftUI

/// Match the first column of the populated four-column grid exactly, including
/// its height. A row widget uses the same 88 x 116 cover as its populated row.
struct ProfileWidgetEmptyGameLayout: Layout {
    let isGrid: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        let tile = tileSize(width: width)
        let text = subviews[1].sizeThatFits(ProposedViewSize(width: max(0, width - tile.width - 16), height: nil))
        return CGSize(width: width, height: max(tile.height, text.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let tile = tileSize(width: bounds.width)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(tile))
        subviews[1].place(at: CGPoint(x: bounds.minX + tile.width + 16, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: max(0, bounds.width - tile.width - 16), height: bounds.height))
    }

    private func tileSize(width: CGFloat) -> CGSize {
        isGrid ? CGSize(width: max(0, (width - 48) / 4), height: max(0, (width - 48) / 3)) : CGSize(width: 88, height: 116)
    }
}
