import SakuraCordModels
import SwiftUI

struct ComposerAttachmentTray: View {
    static var thumbnailCornerRadius: CGFloat { InterfaceScale.metric(16) }
    static var tileSize: CGFloat { InterfaceScale.metric(230) }
    static var filenameRowHeight: CGFloat { InterfaceScale.metric(38) }

    @AppStorage(PrivacySafetySettingsStore.anonymiseFileNamesKey, store: PRBuildProfile.defaults) private var anonymisesFileNames = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let attachments: [ForumPostAttachment]
    /// Files still being checked; they show at once but cannot be sent yet.
    var checkingIDs: Set<UUID> = []
    var sendTransitionAnchor: ComposerSendTransitionAnchor?
    let open: (UUID) -> Void
    let toggleSpoiler: (UUID) -> Void
    let update: (ForumPostAttachment) -> Void
    let remove: (UUID) -> Void
    @State private var editingTarget: ComposerAttachmentEditorTarget?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: InterfaceScale.metric(12)) {
                    ForEach(attachments) { attachment in
                        ComposerAttachmentTile(
                            attachment: attachment,
                            isChecking: checkingIDs.contains(attachment.id),
                            anonymisesFileNames: anonymisesFileNames,
                            sendTransitionAnchor: sendTransitionAnchor,
                            open: open,
                            toggleSpoiler: toggleSpoiler,
                            toggleFilenamePrivacy: toggleFilenamePrivacy,
                            edit: { editingTarget = ComposerAttachmentEditorTarget(id: $0) },
                            remove: remove
                        )
                        .id(attachment.id)
                        .transition(reduceMotion ? .opacity : Self.tileTransition)
                    }
                }
                .padding(.horizontal, InterfaceScale.metric(14))
                .padding(.vertical, InterfaceScale.metric(14))
                // Tiles settle on their own spring inside the composer's
                // resize, which carries the tray itself.
                .animation(reduceMotion ? .smooth(duration: 0.2) : ComposerResizeMotion.tile, value: attachments.map(\.id))
            }
            .scrollIndicators(.hidden)
            .onChange(of: attachments.map(\.id)) { previous, current in
                // Bring a newly added file into view as it arrives.
                guard let added = current.last(where: { !previous.contains($0) }) else { return }
                withAnimation(reduceMotion ? nil : ComposerResizeMotion.tile) {
                    proxy.scrollTo(added, anchor: .trailing)
                }
            }
        }
        .frame(height: Self.tileSize + InterfaceScale.metric(28))
        .accessibilityLabel("Message attachments")
        .onChange(of: anonymisesFileNames) { _, enabled in
            for var attachment in attachments {
                attachment.setFilenameAnonymised(enabled)
                update(attachment)
            }
        }
        .sheet(item: $editingTarget) { target in
            if let attachment = attachments.first(where: { $0.id == target.id }) {
                ForumAttachmentEditor(
                    attachment: attachment,
                    cancel: { editingTarget = nil },
                    save: {
                        update($0)
                        editingTarget = nil
                    }
                )
            }
        }
    }

    /// A file drops into place and pops back out when removed.
    private static var tileTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.82, anchor: .bottom)
                .combined(with: .opacity)
                .combined(with: .offset(y: InterfaceScale.metric(10))),
            removal: .scale(scale: 0.86).combined(with: .opacity)
        )
    }

    private func toggleFilenamePrivacy(_ attachment: ForumPostAttachment) {
        var updated = attachment
        updated.setFilenameAnonymised(!attachment.isFilenameAnonymised)
        update(updated)
    }
}

private struct ComposerAttachmentTile: View {
    let attachment: ForumPostAttachment
    let isChecking: Bool
    let anonymisesFileNames: Bool
    let sendTransitionAnchor: ComposerSendTransitionAnchor?
    let open: (UUID) -> Void
    let toggleSpoiler: (UUID) -> Void
    let toggleFilenamePrivacy: (ForumPostAttachment) -> Void
    let edit: (UUID) -> Void
    let remove: (UUID) -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tileSize: CGFloat { ComposerAttachmentTray.tileSize }
    private var filenameRowHeight: CGFloat { ComposerAttachmentTray.filenameRowHeight }
    private var shape: ConcentricRectangle {
        ConcentricRectangle(cornerRadius: InterfaceScale.metric(16), style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
            filenameRow
        }
        .frame(width: tileSize, height: tileSize, alignment: .topLeading)
        .background(.primary.opacity(isHovered ? 0.06 : 0.035))
        .clipShape(shape)
        .overlay {
            shape.stroke(isHovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.separator), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 10 : 0, y: isHovered ? 4 : 0)
        .contentShape(ConcentricRectangle(cornerRadius: InterfaceScale.metric(14), style: .continuous))
        .onModalHover { hovering in
            withAnimation(ComposerResizeMotion.hover) { isHovered = hovering }
        }
        .help(attachment.filename)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attachment.filename)
        .accessibilityValue(isChecking ? Text("Preparing") : Text(""))
        .accessibilityAction(named: "Open attachment") {
            guard isViewableImage else { return }
            open(attachment.id)
        }
        .accessibilityAction(
            named: attachment.isSpoiler ? "Remove spoiler" : "Mark as spoiler"
        ) {
            toggleSpoiler(attachment.id)
        }
        .accessibilityActions {
            if anonymisesFileNames {
                Button(attachment.isFilenameAnonymised ? "Restore file name" : "Randomise file name") {
                    toggleFilenamePrivacy(attachment)
                }
            }
        }
        .accessibilityAction(named: "Edit attachment") {
            edit(attachment.id)
        }
        .accessibilityAction(named: "Delete attachment") {
            remove(attachment.id)
        }
    }

    private var filenameRow: some View {
        HStack(spacing: InterfaceScale.metric(8)) {
            Text(attachment.filename)
                .font(.interface(.callout).weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isChecking ? .secondary : .primary)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if isChecking {
                ProgressView()
                    .controlSize(.mini)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, InterfaceScale.metric(14))
        .frame(width: tileSize, height: filenameRowHeight)
        .animation(.smooth(duration: 0.25), value: isChecking)
        .animation(.smooth(duration: 0.25), value: attachment.filename)
    }

    private var preview: some View {
        ZStack {
            LocalAttachmentThumbnail(
                url: attachment.url,
                maximumPixelDimension: 480,
                preservesImageAspectRatio: true,
                imageCornerRadius: ComposerAttachmentTray.thumbnailCornerRadius,
                onImageLoaded: { [sendTransitionAnchor, id = attachment.id] image in
                    sendTransitionAnchor?.recordAttachmentThumbnail(image, for: id)
                }
            )
            .background {
                ComposerSendTransitionAttachmentReader(anchor: sendTransitionAnchor, id: attachment.id)
            }
            .padding(.horizontal, InterfaceScale.metric(10))
            .padding(.vertical, InterfaceScale.metric(8))

            if attachment.isSpoiler {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.58))
                    VStack(spacing: InterfaceScale.metric(5)) {
                        Image(systemName: "eye.slash")
                        Text("SPOILER")
                            .font(.interface(.caption2).weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.22), value: attachment.isSpoiler)
        .frame(width: tileSize, height: tileSize - filenameRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isViewableImage else { return }
            open(attachment.id)
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                actions
                    .padding(InterfaceScale.metric(7))
                    .transition(
                        reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .topTrailing)
                            .combined(with: .opacity)
                    )
            }
        }
    }

    private var actions: some View {
        HoverActionPill(
            glass: .regular.interactive(),
            spacing: 1,
            padding: 3
        ) {
            HoverActionButton(
                systemImage: attachment.isSpoiler ? "eye.slash" : "eye",
                help: attachment.isSpoiler ? "Remove spoiler" : "Mark as spoiler",
                isSelected: attachment.isSpoiler,
                diameter: InterfaceScale.metric(22),
                iconFont: .interface(.caption2).weight(.semibold)
            ) {
                toggleSpoiler(attachment.id)
            }
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            if anonymisesFileNames {
                HoverActionButton(
                    systemImage: "shuffle",
                    help: attachment.isFilenameAnonymised ? "Restore file name" : "Randomise file name",
                    isSelected: attachment.isFilenameAnonymised,
                    diameter: InterfaceScale.metric(22),
                    iconFont: .interface(.caption2).weight(.semibold)
                ) {
                    toggleFilenamePrivacy(attachment)
                }
            }
            HoverActionButton(
                systemImage: "pencil",
                help: "Edit attachment",
                diameter: InterfaceScale.metric(22),
                iconFont: .interface(.caption2).weight(.semibold)
            ) {
                edit(attachment.id)
            }
            HoverActionButton(
                systemImage: "trash",
                help: "Delete attachment",
                role: .destructive,
                diameter: InterfaceScale.metric(22),
                iconFont: .interface(.caption2).weight(.semibold)
            ) {
                remove(attachment.id)
            }
        }
    }

    private var isViewableImage: Bool {
        let kind = OptimisticAttachmentPresentation.attachment(
            for: attachment.url,
            index: 0
        ).mediaKind
        return kind == .image || kind == .animatedImage
    }
}
