import AVFoundation
import Foundation
import ImageIO
import SakuraCordModels
import UniformTypeIdentifiers

/// Prepares a private upload copy without changing the source or reducing media quality.
public enum UploadMetadataRemover {
    @concurrent
    public static func prepare(_ source: URL) async throws -> PreparedUploadFile {
        try Task.checkCancellation()
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let candidate = CGImageSourceCreateWithURL(source as CFURL, nil)
        // ImageIO can also open PDF pages; document decoding does not make a file an image.
        let image = candidate.flatMap { source -> CGImageSource? in
            guard let identifier = CGImageSourceGetType(source),
                  UTType(identifier as String)?.conforms(to: .image) == true else { return nil }
            return source
        }
        let declaredType = UTType(filenameExtension: source.pathExtension)
        let asset = AVURLAsset(url: source)
        let isVideo = if image == nil { (try? await asset.loadTracks(withMediaType: .video).isEmpty) == false } else { false }
        try Task.checkCancellation()
        guard image != nil || isVideo else {
            // Do not silently bypass privacy for corrupt/unsupported media.
            if declaredType?.conforms(to: .image) == true || declaredType?.conforms(to: .movie) == true {
                throw UploadMetadataError.unsupportedMedia
            }
            return PreparedUploadFile(url: source)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SakuraCord-PrivateUpload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(source.lastPathComponent)
        do {
            if let image {
                try removeImageMetadata(image, source: source, output: output)
            } else {
                try await removeVideoMetadata(asset, output: output)
            }
            try Task.checkCancellation()
            return PreparedUploadFile(url: output, temporaryDirectory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            if error is CancellationError { throw error }
            throw UploadMetadataError.removalFailed(source.lastPathComponent)
        }
    }

    private static func removeImageMetadata(_ image: CGImageSource, source: URL, output: URL) throws {
        guard let identifier = CGImageSourceGetType(image) else { throw UploadMetadataError.unsupportedMedia }
        let type = UTType(identifier as String)
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        switch type {
        case .png, .gif, .webP, .heic, .heif, UTType("public.avif"):
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            let cleaned = try ImageMetadataContainers.remove(from: data, type: type, orientation: orientation)
            try cleaned.write(to: output)
        case .tiff:
            try repackageTIFF(image, output: output)
        case .jpeg:
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, identifier, CGImageSourceGetCount(image), nil) else {
                throw UploadMetadataError.unsupportedMedia
            }
            let metadata = CGImageMetadataCreateMutable()
            CGImageMetadataSetValueWithPath(metadata, nil, "tiff:Orientation" as CFString, orientation as CFNumber)
            let options: [CFString: Any] = [
                kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false,
                kCGImageMetadataShouldExcludeGPS: true, kCGImageMetadataShouldExcludeXMP: true
            ]
            guard CGImageDestinationCopyImageSource(destination, image, options as CFDictionary, nil) else {
                throw UploadMetadataError.unsupportedMedia
            }
        default:
            throw UploadMetadataError.unsupportedMedia
        }
        guard let result = CGImageSourceCreateWithURL(output as CFURL, nil),
              CGImageSourceGetCount(result) == CGImageSourceGetCount(image)
        else { throw UploadMetadataError.unsupportedMedia }
    }

    private static func repackageTIFF(_ source: CGImageSource, output: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.tiff.identifier as CFString, CGImageSourceGetCount(source), nil) else {
            throw UploadMetadataError.unsupportedMedia
        }
        // ImageIO's TIFF metadata-copy API leaves unreferenced private bytes behind.
        // Rebuild losslessly from full-depth pixels rather than copying the old IFDs.
        for index in 0 ..< CGImageSourceGetCount(source) {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldAllowFloat: true] as CFDictionary) else {
                throw UploadMetadataError.unsupportedMedia
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyOrientation: properties?[kCGImagePropertyOrientation] as? Int ?? 1,
                // LZW keeps the rebuilt pixels lossless without expanding compressed
                // source TIFFs into uncompressed upload copies.
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw UploadMetadataError.unsupportedMedia }
    }

    private static func removeVideoMetadata(_ asset: AVURLAsset, output: URL) async throws {
        // Movie editing preserves alternate groups, defaults, languages and edits.
        // Rebuilding a composition would instead mix alternate audio tracks together.
        let movie = AVMutableMovie(url: asset.url, options: nil)
        movie.metadata = []
        let contentTypes: Set<AVMediaType> = [.video, .audio, .subtitle, .text, .closedCaption]
        for track in movie.tracks {
            if contentTypes.contains(track.mediaType) {
                track.metadata = []
            } else {
                // Timed metadata tracks can contain GPS telemetry.
                movie.removeTrack(track)
            }
        }
        guard let session = AVAssetExportSession(asset: movie, presetName: AVAssetExportPresetPassthrough) else {
            throw UploadMetadataError.unsupportedMedia
        }
        session.metadata = []
        session.metadataItemFilter = .forSharing()
        let type: AVFileType = output.pathExtension.lowercased() == "mov" ? .mov : .mp4
        try await session.export(to: output, as: type)
    }
}

public enum UploadMetadataError: Error, LocalizedError {
    case unsupportedMedia
    case removalFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedMedia: "Metadata could not be safely removed from this media format."
        case let .removalFailed(name): "Metadata could not be safely removed from \(name). The file was not uploaded."
        }
    }
}
