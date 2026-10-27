import AppKit
import MediaPipeline

/// A Discord `placeholder` hash the timeline can preview while the real media loads.
struct NativeTimelineMediaPlaceholder: Hashable {
    let hash: String

    init?(hash: String?, version: Int?) {
        guard version == ThumbHash.supportedVersion, let hash, !hash.isEmpty else { return nil }
        self.hash = hash
    }
}

extension NativeTimelineRowPainter {
    /// Rows draw on every redraw, so each hash is decoded once. A hash that
    /// fails to decode caches an empty image to avoid retrying every frame.
    private static let placeholderImages: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func mediaPlaceholderImage(for placeholder: NativeTimelineMediaPlaceholder) -> NSImage? {
        let key = placeholder.hash as NSString
        let image = placeholderImages.object(forKey: key) ?? {
            let decoded = ThumbHash.image(base64: placeholder.hash).map {
                NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height))
            } ?? NSImage()
            placeholderImages.setObject(decoded, forKey: key)
            return decoded
        }()
        return image.size.width > 0 ? image : nil
    }
}
