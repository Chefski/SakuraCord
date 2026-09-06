import CoreGraphics
import Foundation
import ImageIO

/// Avatar-derived profile colours use the same five-colour, five-bit median
/// cut palette as Discord. Explicit profile colours remain separate metadata.
public enum ProfileImagePalette {
    public static func colors(in data: Data) throws -> [UInt32] {
        if let colors = try ProfileWebPPalette.colors(in: data) { return colors }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw ProfileImageProcessingError.invalidImage }
        let (pixelCount, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow else { throw ProfileImageProcessingError.invalidImage }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw ProfileImageProcessingError.invalidImage }
        return bytes.withUnsafeBufferPointer { quantize($0) }
    }

    private static func quantize(_ bytes: UnsafeBufferPointer<UInt8>) -> [UInt32] {
        var pixels: [UInt32] = []
        pixels.reserveCapacity(bytes.count / 40 + 1)
        for offset in stride(from: 0, to: bytes.count, by: 40) {
            let alpha = Int(bytes[offset + 3])
            guard alpha >= 125 else { continue }
            // Canvas getImageData returns straight-alpha sRGB bytes.
            let red = min(255, (Int(bytes[offset]) * 255 + alpha / 2) / alpha)
            let green = min(255, (Int(bytes[offset + 1]) * 255 + alpha / 2) / alpha)
            let blue = min(255, (Int(bytes[offset + 2]) * 255 + alpha / 2) / alpha)
            guard !(red > 250 && green > 250 && blue > 250) else { continue }
            pixels.append(UInt32(red << 16 | green << 8 | blue))
        }
        return ProfileMedianCut.palette(pixels: pixels)
    }
}
