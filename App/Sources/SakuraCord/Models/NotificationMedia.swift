import Foundation
import ImageIO
import SakuraCordModels
import UniformTypeIdentifiers

nonisolated enum NotificationMedia {
    static func imageAttachment(in message: Message, style: NotificationPreviewStyle) -> Attachment? {
        guard style == .full else { return nil }
        return message.attachments.first {
            !$0.isSpoiler && $0.size <= 10 * 1_024 * 1_024
                && ($0.mediaKind == .image || $0.mediaKind == .animatedImage)
        }
    }

    /// Media must never hold up the alert indefinitely. The shared loader cancels
    /// this waiter on timeout while retaining any unrelated visible-image waiters.
    static func previewImage(at url: URL?, maximumDimension: Int) async -> Data? {
        guard let url, url.isFileURL || url.scheme == "https" else { return nil }
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                guard let data = try? await SharedMediaDataLoader.shared.data(for: url),
                      !Task.isCancelled, data.count <= 20 * 1_024 * 1_024
                else { return nil }
                return pngThumbnail(data, maximumDimension: maximumDimension)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func pngThumbnail(_ data: Data, maximumDimension: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
              ] as CFDictionary)
        else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            result, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? result as Data : nil
    }
}
