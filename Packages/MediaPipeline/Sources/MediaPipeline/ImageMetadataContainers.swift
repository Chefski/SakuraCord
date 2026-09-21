import Foundation
import UniformTypeIdentifiers
import libwebp
import zlib

/// Container edits keep compressed pixels, animation timing and colour profiles intact.
/// ImageIO cannot losslessly edit GIF/WebP/AVIF and retains PNG text and HEIF XMP.
enum ImageMetadataContainers {
    static func remove(from data: Data, type: UTType?, orientation: Int) throws -> Data {
        switch type {
        case .png: try png(data, orientation: orientation)
        case .gif: try gif(data)
        case .webP: try webP(data, orientation: orientation)
        case .heic, .heif, UTType("public.avif"): try HEIFMetadataRemover.remove(data, orientation: orientation)
        default: throw UploadMetadataError.unsupportedMedia
        }
    }

    static func orientationTIFF(_ orientation: Int) -> Data {
        // Little-endian TIFF with a single SHORT orientation tag and no next IFD.
        Data([0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0,
              UInt8(clamping: orientation), 0, 0, 0, 0, 0, 0, 0])
    }

    private static func png(_ data: Data, orientation: Int) throws -> Data {
        guard data.count >= 8 else { throw UploadMetadataError.unsupportedMedia }
        var output = Data(data.prefix(8))
        var offset = 8
        var wroteOrientation = false
        // Only retain standard rendering, colour, HDR and animation chunks.
        let retained: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "cHRM", "gAMA", "iCCP", "sBIT", "sRGB", "bKGD", "pHYs", "acTL", "fcTL", "fdAT", "cICP", "mDCV", "cLLI"]
        while offset < data.count {
            try Task.checkCancellation()
            guard data.count - offset >= 12 else { throw UploadMetadataError.unsupportedMedia }
            let size = Int(data[offset ..< offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard size <= data.count - offset - 12 else { throw UploadMetadataError.unsupportedMedia }
            let type = String(bytes: data[offset + 4 ..< offset + 8], encoding: .ascii) ?? ""
            if type == "IDAT", !wroteOrientation, orientation != 1 {
                wroteOrientation = true
                var chunk = Data("eXIf".utf8) + orientationTIFF(orientation)
                var checksum = chunk.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, UInt32(chunk.count))) }.bigEndian
                var length = UInt32(chunk.count - 4).bigEndian
                output.append(Data(bytes: &length, count: 4))
                chunk.append(Data(bytes: &checksum, count: 4))
                output.append(chunk)
            }
            if retained.contains(type) { output.append(data[offset ..< offset + size + 12]) }
            offset += size + 12
            if type == "IEND" { return output }
        }
        throw UploadMetadataError.unsupportedMedia
    }

    private static func gif(_ data: Data) throws -> Data {
        guard data.count >= 13 else { throw UploadMetadataError.unsupportedMedia }
        var offset = 13 + (data[10] & 0x80 == 0 ? 0 : 3 * (1 << (Int(data[10] & 7) + 1)))
        guard offset <= data.count else { throw UploadMetadataError.unsupportedMedia }
        var output = Data(data.prefix(offset))
        while offset < data.count {
            try Task.checkCancellation()
            let start = offset
            let marker = data[offset]
            offset += 1
            if marker == 0x3B { output.append(marker); return output }
            var keep = true
            if marker == 0x2C {
                guard data.count - offset >= 9 else { throw UploadMetadataError.unsupportedMedia }
                let packed = data[offset + 8]
                offset += 9 + (packed & 0x80 == 0 ? 0 : 3 * (1 << (Int(packed & 7) + 1)))
                offset += 1 // LZW minimum code size
            } else if marker == 0x21 {
                guard offset < data.count else { throw UploadMetadataError.unsupportedMedia }
                let label = data[offset]
                offset += 1
                keep = label == 0xF9 || label == 0x01 // Graphic control and rendered plain text.
                if label == 0xFF, data.count - offset >= 12, data[offset] == 11 {
                    let identifier = String(bytes: data[offset + 1 ..< offset + 12], encoding: .ascii) ?? ""
                    keep = ["NETSCAPE2.0", "ANIMEXTS1.0", "ICCRGBG1012"].contains(identifier)
                }
            } else { throw UploadMetadataError.unsupportedMedia }
            repeat {
                guard offset < data.count else { throw UploadMetadataError.unsupportedMedia }
                let length = Int(data[offset])
                offset += 1
                guard length <= data.count - offset else { throw UploadMetadataError.unsupportedMedia }
                offset += length
                if length == 0 { break }
            } while true
            if keep { output.append(data[start ..< offset]) }
        }
        throw UploadMetadataError.unsupportedMedia
    }

    private static func webP(_ data: Data, orientation: Int) throws -> Data {
        try data.withUnsafeBytes { buffer in
            var input = WebPData(bytes: buffer.bindMemory(to: UInt8.self).baseAddress, size: data.count)
            guard let mux = WebPMuxCreate(&input, 1) else { throw UploadMetadataError.unsupportedMedia }
            defer { WebPMuxDelete(mux) }
            for name in ["EXIF", "XMP "] {
                let result = WebPMuxDeleteChunk(mux, name)
                guard result == WEBP_MUX_OK || result == WEBP_MUX_NOT_FOUND else { throw UploadMetadataError.unsupportedMedia }
            }
            if orientation != 1 {
                let exif = orientationTIFF(orientation)
                try exif.withUnsafeBytes { bytes in
                    var chunk = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: exif.count)
                    guard WebPMuxSetChunk(mux, "EXIF", &chunk, 1) == WEBP_MUX_OK else { throw UploadMetadataError.unsupportedMedia }
                }
            }
            var output = WebPData()
            guard WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let bytes = output.bytes else { throw UploadMetadataError.unsupportedMedia }
            defer { WebPDataClear(&output) }
            return Data(bytes: bytes, count: output.size)
        }
    }
}
