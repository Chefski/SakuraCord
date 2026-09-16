import CoreGraphics
import CryptoKit
import Foundation

/// Immutable prepared raster bytes in the existing bounded media disk cache.
/// The small JSON header is decoded normally; frame payloads remain slices of
/// the mapped file, so retaining an animation does not copy them into the heap.
nonisolated enum PreparedAnimatedImage {
    private static let magic = Data("SCANI001".utf8)
    private static let maximumBytes = 32 * 1_024 * 1_024

    private struct Header: Codable {
        let durations: [Double]
        let playCount: Int?
        let colorSpaces: [Data]
        let frames: [Frame]
    }

    private struct Frame: Codable {
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let bitsPerPixel: Int
        let bytesPerRow: Int
        let bitmapInfo: UInt32
        let colorSpace: Int
        let intent: Int32
        let interpolates: Bool
        let decode: [CGFloat]?
        let compressed: Bool
        let offset: Int
        let count: Int
    }

    static func key(source: Data, maximumPixelDimension: Int?) -> URL? {
        let digest = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        return URL(string: "sakuracord-prepared://animation/v1/\(maximumPixelDimension ?? 0)/\(digest)")
    }

    static func restore(_ data: Data) async -> DecodedAnimatedImage? {
        let work = Task.detached(priority: .utility) { try? decode(data) }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    static func archive(_ image: DecodedAnimatedImage) async -> Data? {
        let work = Task.detached(priority: .utility) { encode(image) }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    static func encode(_ image: DecodedAnimatedImage) -> Data? {
        guard image.frames.count > 1,
              image.frames.count <= 10_000,
              image.storedByteCount >= 32 * 1_024,
              image.storedByteCount < maximumBytes
        else { return nil }
        var frames: [Frame] = []
        var spaces: [Data] = []
        var spaceIndexes: [Data: Int] = [:]
        var payload = Data()
        payload.reserveCapacity(image.storedByteCount)
        for (index, frame) in image.frames.enumerated() {
            guard !Task.isCancelled else { return nil }
            guard CompressedAnimatedFrame.canReconstruct(frame), frame.bitsPerComponent == 8,
                  let space = frame.colorSpace,
                  let icc = space.copyICCData() as Data?
            else { return nil }
            let spaceIndex: Int
            if let cached = spaceIndexes[icc] {
                spaceIndex = cached
            } else {
                spaceIndex = spaces.count
                spaceIndexes[icc] = spaceIndex
                spaces.append(icc)
            }
            let compressed = image.compressedFrameData[index]
            guard let bytes = compressed ?? (frame.dataProvider?.data as Data?) else { return nil }
            let count = compressed?.count ?? frame.bytesPerRow * frame.height
            guard count <= bytes.count, payload.count <= maximumBytes - count else { return nil }
            frames.append(Frame(
                width: frame.width, height: frame.height,
                bitsPerComponent: frame.bitsPerComponent, bitsPerPixel: frame.bitsPerPixel,
                bytesPerRow: frame.bytesPerRow, bitmapInfo: frame.bitmapInfo.rawValue,
                colorSpace: spaceIndex, intent: frame.renderingIntent.rawValue,
                interpolates: frame.shouldInterpolate,
                decode: frame.decode.map { Array(UnsafeBufferPointer(start: $0, count: space.numberOfComponents * 2)) },
                compressed: compressed != nil, offset: payload.count, count: count
            ))
            payload.append(bytes.prefix(count))
        }
        let header = Header(durations: image.frameDurations, playCount: image.playCount, colorSpaces: spaces, frames: frames)
        guard let encoded = try? JSONEncoder().encode(header), encoded.count <= 1_024 * 1_024 else { return nil }
        var result = magic
        withUnsafeBytes(of: UInt32(encoded.count).littleEndian) { result.append(contentsOf: $0) }
        result.append(encoded)
        result.append(payload)
        guard result.count <= maximumBytes - 32 else { return nil }
        result.append(contentsOf: SHA256.hash(data: result))
        return result
    }

    static func decode(_ data: Data) throws -> DecodedAnimatedImage {
        let invalid = CocoaError(.fileReadCorruptFile)
        guard data.count >= 44, data.count <= maximumBytes, data.prefix(8) == magic else { throw invalid }
        let headerCount = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian) }
        let payloadStart = 12 + headerCount
        guard headerCount <= 1_024 * 1_024, payloadStart <= data.count - 32,
              SHA256.hash(data: data.dropLast(32)).elementsEqual(data.suffix(32))
        else { throw invalid }
        let header = try JSONDecoder().decode(Header.self, from: data[(data.startIndex + 12) ..< (data.startIndex + payloadStart)])
        guard !header.frames.isEmpty, header.frames.count <= 10_000,
              header.frames.count == header.durations.count,
              header.durations.allSatisfy({ $0.isFinite && $0 > 0 }),
              !header.colorSpaces.isEmpty, header.colorSpaces.count <= header.frames.count
        else { throw invalid }
        let spaces = try header.colorSpaces.map { bytes in
            guard bytes.count <= 1_024 * 1_024, let space = CGColorSpace(iccData: bytes as CFData) else { throw invalid }
            return space
        }
        let payloadCount = data.count - payloadStart - 32
        var cursor = 0
        var frames: [CGImage] = []
        var compressed: [Data?] = []
        for frame in header.frames {
            try Task.checkCancellation()
            let (byteCount, overflow) = frame.bytesPerRow.multipliedReportingOverflow(by: frame.height)
            guard !overflow, byteCount > 0, byteCount <= 256 * 1_024 * 1_024,
                  frame.width > 0, frame.width <= 16_384, frame.height > 0, frame.height <= 16_384,
                  frame.bitsPerComponent == 8, [8, 16, 24, 32].contains(frame.bitsPerPixel),
                  frame.bytesPerRow >= frame.width * frame.bitsPerPixel / 8,
                  frame.colorSpace >= 0, frame.colorSpace < spaces.count,
                  frame.offset == cursor, frame.count > 0, frame.count <= payloadCount - cursor,
                  frame.compressed ? frame.count < byteCount : frame.count == byteCount,
                  let intent = CGColorRenderingIntent(rawValue: frame.intent)
            else { throw invalid }
            let space = spaces[frame.colorSpace]
            if let decode = frame.decode {
                guard decode.count == space.numberOfComponents * 2, decode.allSatisfy(\.isFinite) else { throw invalid }
            }
            let lower = data.startIndex + payloadStart + cursor
            let bytes = data[lower ..< lower + frame.count]
            func makeImage(_ decode: UnsafePointer<CGFloat>?) -> CGImage? {
                if frame.compressed {
                    return CompressedAnimatedFrame.image(
                        compressed: bytes, byteCount: byteCount,
                        format: CompressedAnimatedFrame.Format(
                            width: frame.width, height: frame.height,
                            bitsPerComponent: frame.bitsPerComponent, bitsPerPixel: frame.bitsPerPixel,
                            bytesPerRow: frame.bytesPerRow, colorSpace: space,
                            bitmapInfo: CGBitmapInfo(rawValue: frame.bitmapInfo),
                            shouldInterpolate: frame.interpolates, intent: intent
                        ), decode: decode
                    )
                }
                guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
                return CGImage(
                    width: frame.width, height: frame.height,
                    bitsPerComponent: frame.bitsPerComponent, bitsPerPixel: frame.bitsPerPixel,
                    bytesPerRow: frame.bytesPerRow, space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: frame.bitmapInfo), provider: provider,
                    decode: decode, shouldInterpolate: frame.interpolates, intent: intent
                )
            }
            let image = frame.decode.map { values in values.withUnsafeBufferPointer { makeImage($0.baseAddress) } }
                ?? makeImage(nil)
            guard let image else { throw invalid }
            frames.append(image)
            compressed.append(frame.compressed ? bytes : nil)
            cursor += frame.count
        }
        guard cursor == payloadCount else { throw invalid }
        return DecodedAnimatedImage(
            frames: frames, frameDurations: header.durations,
            playCount: header.playCount, compressedFrameData: compressed
        )
    }
}
