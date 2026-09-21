import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AttachmentPhotoProcessor {
    /// Downsamples still images, using JPEG for opaque images and PNG for transparency.
    /// Animated images retain their original bytes.
    public static func prepare(_ sourceURL: URL, in directory: URL, options: AttachmentCompactionOptions = .init()) throws -> URL {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
            let identifier = CGImageSourceGetType(source),
            let sourceType = UTType(identifier as String)
        else { throw CocoaError(.fileReadCorruptFile) }

        if CGImageSourceGetCount(source) > 1,
           sourceType == .gif || sourceType == .png || sourceType == .webP
        {
            let url = directory.appendingPathComponent(sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: url)
            return url
        }

        let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: options.quality.maximumImageDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
        guard let image = decoded else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = properties?[kCGImagePropertyHasAlpha] as? Bool == true
        let outputType: UTType = hasAlpha ? .png : .jpeg
        let url = directory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(outputType == .jpeg ? "jpg" : (outputType.preferredFilenameExtension ?? "png"))
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, outputType.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        let outputProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: options.quality.imageQuality
        ]
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try Task.checkCancellation()
        return url
    }
}
