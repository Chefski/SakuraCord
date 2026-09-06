import Foundation
import libwebp

public struct ProfilePixelCrop: Hashable, Sendable {
    public var originX: Int
    public var originY: Int
    public var width: Int
    public var height: Int
    public var quarterTurns: Int
    public var flipsHorizontally: Bool

    public init(originX: Int, originY: Int, width: Int, height: Int, quarterTurns: Int = 0, flipsHorizontally: Bool = false) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.quarterTurns = quarterTurns
        self.flipsHorizontally = flipsHorizontally
    }
}

public enum ProfileImageProcessingError: Error, LocalizedError {
    case invalidImage
    case invalidCrop
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage: "This image could not be decoded."
        case .invalidCrop: "The crop is outside the image."
        case .encodingFailed: "The cropped image could not be exported."
        }
    }
}

/// Mirrors Discord's animated WebP worker: RGBA crop, flip, quarter rotation,
/// quality 75/method 4, minimize-size encoding, and its final 100 ms frame marker.
/// Frames are processed one at a time rather than retaining every decoded frame.
public enum ProfileWebPCropper {
    public static func crop(_ data: Data, region: ProfilePixelCrop) throws -> Data {
        try data.withUnsafeBytes { input in
            guard let bytes = input.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw ProfileImageProcessingError.invalidImage
            }
            var source = WebPData(bytes: bytes, size: data.count)
            var decoderOptions = WebPAnimDecoderOptions()
            guard WebPAnimDecoderOptionsInit(&decoderOptions) != 0 else { throw ProfileImageProcessingError.invalidImage }
            decoderOptions.color_mode = MODE_RGBA
            guard let decoder = WebPAnimDecoderNew(&source, &decoderOptions) else { throw ProfileImageProcessingError.invalidImage }
            defer { WebPAnimDecoderDelete(decoder) }
            var info = WebPAnimInfo()
            guard WebPAnimDecoderGetInfo(decoder, &info) != 0,
                  region.originX >= 0, region.originY >= 0, region.width > 0, region.height > 0,
                  region.originX <= Int(info.canvas_width), region.originY <= Int(info.canvas_height),
                  region.width <= Int(info.canvas_width) - region.originX,
                  region.height <= Int(info.canvas_height) - region.originY
            else { throw ProfileImageProcessingError.invalidCrop }
            let turns = (region.quarterTurns % 4 + 4) % 4
            let outputWidth = turns % 2 == 0 ? region.width : region.height
            let outputHeight = turns % 2 == 0 ? region.height : region.width
            var options = WebPAnimEncoderOptions()
            guard WebPAnimEncoderOptionsInit(&options) != 0 else { throw ProfileImageProcessingError.encodingFailed }
            options.minimize_size = 1
            options.allow_mixed = 0
            guard let encoder = WebPAnimEncoderNew(Int32(outputWidth), Int32(outputHeight), &options) else {
                throw ProfileImageProcessingError.encodingFailed
            }
            defer { WebPAnimEncoderDelete(encoder) }
            var config = WebPConfig()
            guard WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, 75) != 0 else { throw ProfileImageProcessingError.encodingFailed }
            config.method = 4
            var timestamp: Int32 = 0
            var count = 0
            while WebPAnimDecoderHasMoreFrames(decoder) != 0 {
                try Task.checkCancellation()
                var rgba: UnsafeMutablePointer<UInt8>?
                guard WebPAnimDecoderGetNext(decoder, &rgba, &timestamp) != 0, let rgba else {
                    throw ProfileImageProcessingError.invalidImage
                }
                let pixels = try transform(rgba, sourceWidth: Int(info.canvas_width), region: region, turns: turns)
                try add(pixels, width: outputWidth, height: outputHeight, timestamp: timestamp, config: &config, encoder: encoder)
                count += 1
            }
            guard count == info.frame_count, count > 0, timestamp <= Int32.max - 100,
                  WebPAnimEncoderAdd(encoder, nil, timestamp + 100, nil) != 0
            else { throw ProfileImageProcessingError.encodingFailed }
            var output = WebPData()
            guard WebPAnimEncoderAssemble(encoder, &output) != 0, let outputBytes = output.bytes else {
                throw ProfileImageProcessingError.encodingFailed
            }
            defer { WebPDataClear(&output) }
            return Data(bytes: outputBytes, count: output.size)
        }
    }

    private static func add(_ pixels: [UInt8], width: Int, height: Int, timestamp: Int32,
                            config: inout WebPConfig, encoder: OpaquePointer) throws {
        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw ProfileImageProcessingError.encodingFailed }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(width)
        picture.height = Int32(height)
        picture.use_argb = 1
        let imported = pixels.withUnsafeBufferPointer { WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(width * 4)) }
        guard imported != 0, WebPAnimEncoderAdd(encoder, &picture, timestamp, &config) != 0 else {
            throw ProfileImageProcessingError.encodingFailed
        }
    }

    private static func transform(_ source: UnsafePointer<UInt8>, sourceWidth: Int,
                                  region: ProfilePixelCrop, turns: Int) throws -> [UInt8] {
        let width = region.width
        let height = region.height
        let outputWidth = turns % 2 == 0 ? width : height
        var output = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            try Task.checkCancellation()
            for column in 0 ..< width {
                let sourceIndex = ((region.originY + row) * sourceWidth + region.originX + column) * 4
                let flippedX = region.flipsHorizontally ? width - 1 - column : column
                let destination: (Int, Int)
                switch turns {
                case 1: destination = (height - 1 - row, flippedX)
                case 2: destination = (width - 1 - flippedX, height - 1 - row)
                case 3: destination = (row, width - 1 - flippedX)
                default: destination = (flippedX, row)
                }
                let destinationIndex = (destination.1 * outputWidth + destination.0) * 4
                output[destinationIndex] = source[sourceIndex]
                output[destinationIndex + 1] = source[sourceIndex + 1]
                output[destinationIndex + 2] = source[sourceIndex + 2]
                output[destinationIndex + 3] = source[sourceIndex + 3]
            }
        }
        return output
    }
}
