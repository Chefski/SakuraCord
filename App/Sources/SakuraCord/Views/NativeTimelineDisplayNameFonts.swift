import AppKit
import SakuraCordModels

extension NativeMessageTimelineCoordinator {
    /// Font availability changes only identity geometry. Body layout, row heights,
    /// scrolling anchors and hover state retain their existing presentation.
    func refreshDisplayNameFonts(_ ids: Set<Int>) {
        guard let canvas, layoutWidth > 0 else { return }
        var changed = IndexSet()
        for index in items.indices {
            guard let row = items[index].messageRow else { continue }
            let author = parent.model.authorPresentation(for: row.message).user
            let reply = row.replyPreview.map { parent.model.authorPresentation(for: $0).user }
            let users = [author, reply, row.message.interactionMetadata?.user]
            guard users.contains(where: { user in
                user?.displayNameStyle.map { ids.contains($0.fontID) } == true
            }) else { continue }
            layouts[index] = layout(for: items[index], width: layoutWidth)
            rowHeights[index] = layouts[index].height
            canvas.invalidateBitmap(items[index].identifier)
            changed.insert(index)
        }
        canvas.invalidateRows(changed)
    }
}
