import Foundation
import libwebp

/// Chromium rasterizes opaque, unprofiled, lossy WebP from YUV420 planes. Its
/// fractional chroma interpolation precedes RGB rounding. Decoding directly to
/// RGBA rounds chroma early and can change the colours subsequently saved.
enum ProfileWebPPalette {
    static func colors(in data: Data) throws -> [UInt32]? {
        guard data.count >= 12, data.prefix(4) == Data("RIFF".utf8), data[8 ..< 12] == Data("WEBP".utf8) else { return nil }
        return try data.withUnsafeBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { throw ProfileImageProcessingError.invalidImage }
            var features = WebPBitstreamFeatures()
            guard WebPGetFeatures(bytes, buffer.count, &features) == VP8_STATUS_OK else { throw ProfileImageProcessingError.invalidImage }
            guard features.format == 1, features.has_alpha == 0, features.has_animation == 0 else { return nil }
            var source = WebPData(bytes: bytes, size: buffer.count)
            guard let demux = WebPDemux(&source) else { throw ProfileImageProcessingError.invalidImage }
            defer { WebPDemuxDelete(demux) }
            guard WebPDemuxGetI(demux, WEBP_FF_FORMAT_FLAGS) & UInt32(ICCP_FLAG.rawValue) == 0 else { return nil }
            var width: Int32 = 0
            var height: Int32 = 0
            var yStride: Int32 = 0
            var uvStride: Int32 = 0
            var uPlane: UnsafeMutablePointer<UInt8>?
            var vPlane: UnsafeMutablePointer<UInt8>?
            guard let yPlane = WebPDecodeYUV(bytes, buffer.count, &width, &height, &uPlane, &vPlane, &yStride, &uvStride),
                  let uPlane, let vPlane else { throw ProfileImageProcessingError.invalidImage }
            defer { WebPFree(yPlane) }
            let planes = Planes(luma: yPlane, blueChroma: uPlane, redChroma: vPlane, width: Int(width), height: Int(height),
                                yStride: Int(yStride), uvStride: Int(uvStride))
            var pixels: [UInt32] = []
            pixels.reserveCapacity(Int(width) * Int(height) / 10 + 1)
            for index in stride(from: 0, to: Int(width) * Int(height), by: 10) {
                let color = planes.color(at: index)
                guard !(color >> 16 > 250 && color >> 8 & 255 > 250 && color & 255 > 250) else { continue }
                pixels.append(color)
            }
            return ProfileMedianCut.palette(pixels: pixels)
        }
    }

    private struct Planes {
        let luma: UnsafePointer<UInt8>
        let blueChroma: UnsafePointer<UInt8>
        let redChroma: UnsafePointer<UInt8>
        let width: Int
        let height: Int
        let yStride: Int
        let uvStride: Int

        func color(at index: Int) -> UInt32 {
            let column = index % width
            let row = index / width
            let luminance = (Double(luma[row * yStride + column]) - 16) * 255 / 219
            let blueChroma = chroma(self.blueChroma, column: column, row: row) - 128
            let redChroma = chroma(self.redChroma, column: column, row: row) - 128
            // Rec. 601 limited-range YUV, the colour space reported by Blink's
            // WebP decoder. Convert only sampled pixels, without an RGB image.
            let red = luminance + redChroma * (1.402 * 255 / 224)
            let green = luminance - blueChroma * (0.114 * 1.772 / 0.587 * 255 / 224) - redChroma * (0.299 * 1.402 / 0.587 * 255 / 224)
            let blue = luminance + blueChroma * (1.772 * 255 / 224)
            func byte(_ value: Double) -> UInt32 { UInt32(max(0, min(255, value.rounded()))) }
            return byte(red) << 16 | byte(green) << 8 | byte(blue)
        }

        private func chroma(_ plane: UnsafePointer<UInt8>, column: Int, row: Int) -> Double {
            let chromaX = Double(column) / 2 - 0.25
            let chromaY = Double(row) / 2 - 0.25
            let left = Int(floor(chromaX))
            let top = Int(floor(chromaY))
            let fractionX = chromaX - floor(chromaX)
            let fractionY = chromaY - floor(chromaY)
            func read(_ column: Int, _ row: Int) -> Double {
                Double(plane[min(max(row, 0), (height + 1) / 2 - 1) * uvStride + min(max(column, 0), (width + 1) / 2 - 1)])
            }
            let upper = read(left, top) * (1 - fractionX) + read(left + 1, top) * fractionX
            let lower = read(left, top + 1) * (1 - fractionX) + read(left + 1, top + 1) * fractionX
            return upper * (1 - fractionY) + lower * fractionY
        }
    }
}
