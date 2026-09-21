import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct AttachmentCompactor: AttachmentCompacting {
    public init() {}

    @concurrent
    public func compact(_ source: URL, in directory: URL, options: AttachmentCompactionOptions) async throws -> URL {
        try Task.checkCancellation()
        let type = UTType(filenameExtension: source.pathExtension)
        if type?.conforms(to: .image) == true,
           let image = CGImageSourceCreateWithURL(source as CFURL, nil),
           CGImageSourceGetCount(image) == 1
        {
            return try AttachmentPhotoProcessor.prepare(source, in: directory, options: options)
        }
        if type?.conforms(to: .movie) == true {
            return try await compactVideo(source, in: directory, options: options)
        }
        throw AttachmentCompactionError.unsupportedType
    }

    private func compactVideo(_ source: URL, in directory: URL, options: AttachmentCompactionOptions) async throws -> URL {
        let preset = switch options.quality {
        case .high: AVAssetExportPreset1920x1080
        case .balanced: AVAssetExportPreset1280x720
        case .small: AVAssetExportPreset640x480
        }
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CocoaError(.fileReadUnknown)
        }
        let output = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension("mp4")
        try await session.export(to: output, as: .mp4)
        try Task.checkCancellation()
        return output
    }

}

public enum AttachmentCompactionError: Error {
    case unsupportedType
}
