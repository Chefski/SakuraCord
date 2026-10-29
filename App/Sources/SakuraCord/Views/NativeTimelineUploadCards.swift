import AppKit
import SakuraCordModels

extension NativeTimelineRowLayout {
    /// One file of a local send while it uploads, or after its upload failed:
    /// the first-party upload card, with its own progress and cancel.
    struct UploadRegion {
        let frame: CGRect
        let attachmentID: String
        let title: String
        let detail: String
        let iconFrame: CGRect
        let titleFrame: CGRect
        let statusFrame: CGRect
        let cancelFrame: CGRect
    }

    /// Discord's in-flight file card, in its CSS pixel metrics.
    enum UploadCardMetrics {
        static var maximumWidth: CGFloat { InterfaceScale.metric(432) }
        static var height: CGFloat { InterfaceScale.metric(74) }
        static var padding: CGFloat { InterfaceScale.metric(17) }
        static var iconSize: CGSize { CGSize(width: InterfaceScale.metric(30), height: InterfaceScale.metric(40)) }
        static var iconSpacing: CGFloat { InterfaceScale.metric(8) }
        static var cancelSize: CGFloat { InterfaceScale.metric(24) }
        static var barHeight: CGFloat { InterfaceScale.metric(8) }
        static var spacing: CGFloat { InterfaceScale.metric(8) }
    }

    static func uploadRegions(
        for attachments: [Attachment],
        origin: CGPoint,
        maximumWidth: CGFloat
    ) -> [UploadRegion] {
        let metrics = UploadCardMetrics.self
        let width = min(metrics.maximumWidth, maximumWidth)
        return attachments.enumerated().map { index, attachment in
            let frame = CGRect(
                x: origin.x,
                y: origin.y + CGFloat(index) * (metrics.height + metrics.spacing),
                width: width,
                height: metrics.height
            )
            let iconFrame = CGRect(
                x: frame.minX + metrics.padding,
                y: frame.midY - metrics.iconSize.height / 2,
                width: metrics.iconSize.width,
                height: metrics.iconSize.height
            )
            let cancelFrame = CGRect(
                x: frame.maxX - metrics.padding - metrics.cancelSize,
                y: frame.midY - metrics.cancelSize / 2,
                width: metrics.cancelSize,
                height: metrics.cancelSize
            )
            let textX = iconFrame.maxX + metrics.iconSpacing
            let textWidth = max(0, cancelFrame.minX - metrics.iconSpacing - textX)
            return UploadRegion(
                frame: frame,
                attachmentID: attachment.id,
                title: attachment.filename,
                detail: ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file),
                iconFrame: iconFrame,
                titleFrame: CGRect(x: textX, y: iconFrame.minY, width: textWidth, height: InterfaceScale.metric(22)),
                statusFrame: CGRect(
                    x: textX,
                    y: iconFrame.minY + InterfaceScale.metric(26),
                    width: textWidth,
                    height: InterfaceScale.metric(14)
                ),
                cancelFrame: cancelFrame
            )
        }
    }
}

extension NativeTimelineRowPainter {
    static func uploadCard(
        _ region: NativeTimelineRowLayout.UploadRegion,
        fraction: Double,
        isFailed: Bool,
        canCancel: Bool,
        isCancelHovered: Bool
    ) {
        componentContainer(region.frame, accentColor: nil)
        systemSymbol("doc.fill", in: region.iconFrame, color: .secondaryLabelColor, inset: 0)
        // The name truncates first so the size always stays readable.
        let font = NSFont.interfacePreferredFont(forTextStyle: .body)
        let detail = " — " + region.detail
        let detailWidth = min(measuredTextWidth(detail, font: font), region.titleFrame.width)
        let titleWidth = min(measuredTextWidth(region.title, font: font), region.titleFrame.width - detailWidth)
        var titleFrame = region.titleFrame
        titleFrame.size.width = titleWidth
        text(region.title, in: titleFrame, font: font, color: .labelColor)
        text(
            detail,
            in: CGRect(x: titleFrame.maxX, y: titleFrame.minY, width: detailWidth, height: titleFrame.height),
            font: font,
            color: .secondaryLabelColor
        )
        if isFailed {
            text(
                String(localized: "Upload failed"),
                in: region.statusFrame,
                font: .interfacePreferredFont(forTextStyle: .caption1),
                color: .systemRed
            )
        } else {
            uploadProgressBar(
                in: CGRect(
                    x: region.statusFrame.minX,
                    y: region.statusFrame.minY + (region.statusFrame.height - NativeTimelineRowLayout.UploadCardMetrics.barHeight) / 2,
                    width: region.statusFrame.width,
                    height: NativeTimelineRowLayout.UploadCardMetrics.barHeight
                ),
                fraction: fraction
            )
        }
        guard canCancel else { return }
        systemSymbol(
            "xmark",
            in: region.cancelFrame.insetBy(dx: InterfaceScale.metric(5), dy: InterfaceScale.metric(5)),
            color: isCancelHovered ? .labelColor : .secondaryLabelColor,
            inset: 0,
            weight: .semibold
        )
    }

    private static func uploadProgressBar(in frame: CGRect, fraction: Double) {
        let radius = frame.height / 2
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        guard fraction > 0 else { return }
        var fill = frame
        fill.size.width = max(frame.height, frame.width * min(1, fraction))
        NSColor.sakuraCordAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

extension NativeTimelineRowPainter {
    static func drawMessageUploads(_ input: NativeTimelineMessageDrawInput) {
        let message = input.row.message
        for region in input.layout.uploadRegions {
            uploadCard(
                region,
                fraction: input.model?.attachmentUploads.fraction(nonce: message.nonce, attachmentID: region.attachmentID) ?? 0,
                isFailed: message.outboxState == .failed,
                canCancel: input.model?.attachmentUploads.canCancel(nonce: message.nonce, attachmentID: region.attachmentID) == true,
                isCancelHovered: input.hoveredDeliveryAction == .cancelUpload(attachmentID: region.attachmentID)
            )
        }
    }
}

extension NativeTimelineCanvasView {
    @objc func attachmentUploadsDidChange(_ notification: Notification) {
        guard let uploads = model?.attachmentUploads, notification.object as AnyObject === uploads else { return }
        // Cached bitmaps outlive navigation, so repaint every cached row that can show progress.
        let identifiers = bitmapCache.compactMap { identifier, cached in
            uploads.tracks(nonce: cached.item.messageRow?.message.nonce) ? identifier : nil
        }
        identifiers.forEach(invalidateBitmap)
        if !identifiers.isEmpty || layouts.contains(where: { !$0.uploadRegions.isEmpty }) {
            setNeedsDisplay(visibleRect)
        }
    }
}
