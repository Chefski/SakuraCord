import Compression
import CoreGraphics
import Darwin
import Foundation

/// Keeps an animation's raster bytes losslessly compressed between Core Graphics
/// reads. The provider's lease callbacks bound the lifetime of expanded pixels;
/// frame identity, color space, geometry, and Core Animation timing stay intact.
nonisolated enum CompressedAnimatedFrame {
    struct Result {
        let image: CGImage
        let storedByteCount: Int
        let compressedData: Data?

        init(image: CGImage, storedByteCount: Int, compressedData: Data? = nil) {
            self.image = image
            self.storedByteCount = storedByteCount
            self.compressedData = compressedData
        }
    }

    /// Give the compositor a presentation-owned image identity. Retaining the
    /// compressed source frame must not also pin its uploaded raster in CA's
    /// image cache after that frame is replaced on the layer.
    static func transientImage(_ image: CGImage) -> CGImage {
        guard canReconstruct(image), let colorSpace = image.colorSpace, let provider = image.dataProvider else { return image }
        return CGImage(
            width: image.width, height: image.height,
            bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow, space: colorSpace,
            bitmapInfo: image.bitmapInfo, provider: provider,
            decode: image.decode, shouldInterpolate: image.shouldInterpolate,
            intent: image.renderingIntent
        ) ?? image
    }

    static func canReconstruct(_ image: CGImage) -> Bool {
        !image.isMask && image.contentHeadroom <= 1 && !image.containsImageSpecificToneMappingMetadata
    }

    static func store(_ image: CGImage) -> Result {
        let (byteCount, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow else { return Result(image: image, storedByteCount: .max) }
        let unchanged = Result(image: image, storedByteCount: byteCount)
        guard byteCount >= 16 * 1_024, canReconstruct(image),
              let colorSpace = image.colorSpace,
              let original = image.dataProvider?.data,
              CFDataGetLength(original) >= byteCount,
              let source = CFDataGetBytePtr(original)
        else { return unchanged }

        guard let destination = allocateRaster(byteCount) else { return unchanged }
        defer { munmap(destination, byteCount) }
        let count = withExtendedLifetime(original) {
            compression_encode_buffer(destination, byteCount, source, byteCount, nil, COMPRESSION_LZFSE)
        }
        // Avoid adding decompression work when the raster is not compressible.
        guard count > 0, count < byteCount - byteCount / 6 else { return unchanged }
        let compressed = Data(bytes: destination, count: count)
        guard let stored = Self.image(
            compressed: compressed, byteCount: byteCount,
            format: Format(
                width: image.width, height: image.height,
                bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
                bytesPerRow: image.bytesPerRow, colorSpace: colorSpace,
                bitmapInfo: image.bitmapInfo, shouldInterpolate: image.shouldInterpolate,
                intent: image.renderingIntent
            ), decode: image.decode
        ) else { return unchanged }
        return Result(image: stored, storedByteCount: count, compressedData: compressed)
    }

    struct Format {
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let bitsPerPixel: Int
        let bytesPerRow: Int
        let colorSpace: CGColorSpace
        let bitmapInfo: CGBitmapInfo
        let shouldInterpolate: Bool
        let intent: CGColorRenderingIntent
    }

    static func image(
        compressed: Data, byteCount: Int, format: Format,
        decode: UnsafePointer<CGFloat>?
    ) -> CGImage? {
        let storage = Storage(compressed: compressed, byteCount: byteCount)
        let info = Unmanaged.passRetained(storage).toOpaque()
        var callbacks = CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: { info in
                guard let info else { return nil }
                return Unmanaged<Storage>.fromOpaque(info).takeUnretainedValue().acquire()
            },
            releaseBytePointer: { info, _ in
                guard let info else { return }
                Unmanaged<Storage>.fromOpaque(info).takeUnretainedValue().release()
            },
            getBytesAtPosition: nil,
            releaseInfo: { info in
                guard let info else { return }
                Unmanaged<Storage>.fromOpaque(info).release()
            }
        )
        guard let provider = CGDataProvider(directInfo: info, size: off_t(byteCount), callbacks: &callbacks) else {
            Unmanaged<Storage>.fromOpaque(info).release()
            return nil
        }
        return CGImage(
            width: format.width, height: format.height,
            bitsPerComponent: format.bitsPerComponent, bitsPerPixel: format.bitsPerPixel,
            bytesPerRow: format.bytesPerRow, space: format.colorSpace,
            bitmapInfo: format.bitmapInfo, provider: provider,
            decode: decode, shouldInterpolate: format.shouldInterpolate,
            intent: format.intent
        )
    }

    /// Pixel leases are short-lived and much larger than their compressed
    /// owners. Returning their pages directly avoids leaving raster-sized holes
    /// in allocator arenas shared with long-lived model and view objects.
    private static func allocateRaster(_ byteCount: Int) -> UnsafeMutablePointer<UInt8>? {
        let memory = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard let memory, memory != MAP_FAILED else { return nil }
        return memory.bindMemory(to: UInt8.self, capacity: byteCount)
    }

    nonisolated private final class Storage: @unchecked Sendable {
        let compressed: Data
        let byteCount: Int
        private let lock = NSLock()
        private var expanded: UnsafeMutablePointer<UInt8>?
        private var readers = 0

        init(compressed: Data, byteCount: Int) {
            self.compressed = compressed
            self.byteCount = byteCount
        }

        deinit {
            if let expanded { munmap(expanded, byteCount) }
        }

        func acquire() -> UnsafeRawPointer? {
            lock.lock()
            defer { lock.unlock() }
            if expanded == nil {
                guard let buffer = CompressedAnimatedFrame.allocateRaster(byteCount) else { return nil }
                let decoded = compressed.withUnsafeBytes { bytes in
                    guard let source = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(
                        buffer, byteCount, source,
                        bytes.count, nil, COMPRESSION_LZFSE
                    )
                }
                guard decoded == byteCount else {
                    munmap(buffer, byteCount)
                    return nil
                }
                expanded = buffer
            }
            readers += 1
            return expanded.map(UnsafeRawPointer.init)
        }

        func release() {
            lock.lock()
            defer { lock.unlock() }
            precondition(readers > 0)
            readers -= 1
            if readers == 0 {
                if let expanded { munmap(expanded, byteCount) }
                expanded = nil
            }
        }
    }
}
