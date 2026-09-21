import AVFoundation
import Foundation
import ImageIO
import SakuraCordModels
import Testing
import UniformTypeIdentifiers
import libwebp
@testable import MediaPipeline

struct UploadMetadataTests {
    @Test(arguments: [UTType.jpeg, .png, .heic, .tiff, .gif, .webP, UTType("public.avif")!])
    func removesPersonalMetadataWithoutChangingPixelsOrAnimation(type: UTType) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A renamed image still needs scrubbing; type detection must inspect content.
        let sourceURL = directory.appendingPathComponent("photo.bin")
        let original = try fixture(type)
        try original.write(to: sourceURL)
        let prepared = try await UploadMetadataRemover.prepare(sourceURL)
        defer { prepared.discard() }
        let cleaned = try Data(contentsOf: prepared.url)
        #expect(cleaned.range(of: Data("Secret Camera Owner".utf8)) == nil)
        #expect(cleaned.range(of: Data("Secret GPS Location".utf8)) == nil)
        #expect(try Data(contentsOf: sourceURL) == original)
        let input = try #require(CGImageSourceCreateWithData(original as CFData, nil))
        let output = try #require(CGImageSourceCreateWithData(cleaned as CFData, nil))
        #expect(CGImageSourceGetType(output) == CGImageSourceGetType(input))
        #expect(CGImageSourceGetCount(output) == CGImageSourceGetCount(input))
        for index in 0 ..< CGImageSourceGetCount(input) {
            let before = try #require(CGImageSourceCreateImageAtIndex(input, index, nil))
            let after = try #require(CGImageSourceCreateImageAtIndex(output, index, nil))
            #expect(try pixels(before) == pixels(after))
            let beforeProperties = try #require(CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [String: Any])
            let afterProperties = try #require(CGImageSourceCopyPropertiesAtIndex(output, index, nil) as? [String: Any])
            #expect(afterProperties[kCGImagePropertyGPSDictionary as String] == nil)
            #expect(afterProperties[kCGImagePropertyOrientation as String] as? Int ?? 1 == beforeProperties[kCGImagePropertyOrientation as String] as? Int ?? 1)
            let beforeGIF = beforeProperties[kCGImagePropertyGIFDictionary as String] as? NSDictionary
            let afterGIF = afterProperties[kCGImagePropertyGIFDictionary as String] as? NSDictionary
            if type == .gif { #expect(beforeGIF == afterGIF) }
        }
        prepared.discard()
        #expect(!FileManager.default.fileExists(atPath: prepared.url.path))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func keepsDocumentsAndRejectsUnreadableMedia() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("notes.txt")
        let bytes = Data("Secret GPS Location".utf8)
        try bytes.write(to: source)
        let prepared = try await UploadMetadataRemover.prepare(source)
        #expect(prepared.url == source)
        prepared.discard()
        #expect(try Data(contentsOf: source) == bytes)
        let pdf = directory.appendingPathComponent("document.pdf")
        var page = CGRect(x: 0, y: 0, width: 64, height: 64)
        let document = try #require(CGContext(pdf as CFURL, mediaBox: &page, nil))
        document.beginPDFPage(nil)
        document.fill(page)
        document.endPDFPage()
        document.closePDF()
        let originalPDF = try Data(contentsOf: pdf)
        let preparedPDF = try await UploadMetadataRemover.prepare(pdf)
        #expect(preparedPDF.url == pdf)
        preparedPDF.discard()
        #expect(try Data(contentsOf: pdf) == originalPDF)
        let broken = directory.appendingPathComponent("broken.jpg")
        try bytes.write(to: broken)
        await #expect(throws: UploadMetadataError.self) { try await UploadMetadataRemover.prepare(broken) }
    }

    @Test(arguments: ["uuid", "udta", "meta"])
    func rejectsUnrecognizedHEIFMetadataContainers(boxType: String) throws {
        let original = try fixture(.heic) + box(boxType, payload: Data("Unrecognized private metadata".utf8))
        #expect(throws: UploadMetadataError.self) {
            try HEIFMetadataRemover.remove(original, orientation: 6)
        }
    }

    private func fixture(_ type: UTType) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let data = NSMutableData()
        let animated = type == .gif || type == .webP
        let destination = try #require(CGImageDestinationCreateWithData(data, (type == .webP ? UTType.gif : type).identifier as CFString, animated ? 2 : 1, nil))
        for _ in 0 ..< (animated ? 2 : 1) {
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), [
                kCGImagePropertyOrientation: animated ? 1 : 6,
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 50.123, kCGImagePropertyGPSLatitudeRef: "N",
                                                kCGImagePropertyGPSLongitude: 30.456, kCGImagePropertyGPSLongitudeRef: "E"],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Secret Camera Owner"],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Secret GPS Location", kCGImagePropertyExifMakerNote: Data("Secret GPS Location".utf8)],
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2],
                kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "Secret GPS Location"]
            ] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        if type == .webP {
            var encodedBytes: UnsafeMutablePointer<UInt8>?
            let rgba = try pixels(#require(context.makeImage()))
            let count = rgba.withUnsafeBytes { WebPEncodeLosslessRGBA($0.bindMemory(to: UInt8.self).baseAddress, 64, 32, 256, &encodedBytes) }
            let pointer = try #require(encodedBytes)
            defer { WebPFree(pointer) }
            let encoded = Data(bytes: pointer, count: count)
            return try encoded.withUnsafeBytes { bytes in
                var input = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: encoded.count)
                let mux = try #require(WebPMuxCreate(&input, 1))
                defer { WebPMuxDelete(mux) }
                let xmp = Data("Secret GPS Location".utf8)
                xmp.withUnsafeBytes { bytes in
                    var chunk = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: xmp.count)
                    _ = WebPMuxSetChunk(mux, "XMP ", &chunk, 1)
                }
                var output = WebPData()
                #expect(WebPMuxAssemble(mux, &output) == WEBP_MUX_OK)
                defer { WebPDataClear(&output) }
                return Data(bytes: try #require(output.bytes), count: output.size)
            }
        }
        if type == .jpeg {
            var bytes = data as Data
            let comment = Data("Secret GPS Location".utf8)
            bytes.insert(contentsOf: Data([0xFF, 0xFE, 0, UInt8(comment.count + 2)]) + comment, at: 2)
            return bytes
        }
        if type == .gif {
            var bytes = data as Data
            let comment = Data("Secret GPS Location".utf8)
            bytes.insert(contentsOf: Data([0x21, 0xFE, UInt8(comment.count)]) + comment + Data([0]), at: bytes.count - 1)
            return bytes
        }
        if type == .heic || type == UTType("public.avif") {
            let uuid = Data([0xBE, 0x7A, 0xCF, 0xCB, 0x97, 0xA9, 0x42, 0xE8, 0x9C, 0x71, 0x99, 0x94, 0x91, 0xE3, 0xAF, 0xAC])
            let xmp = Data("""
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:exif="http://ns.adobe.com/exif/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"
            exif:GPSLatitude="50,7.404N" dc:description="Secret GPS Location"/></rdf:RDF></x:xmpmeta>
            """.utf8)
            // Standard XMP outside the item table, plus stale private padding.
            return data as Data + box("uuid", payload: uuid + xmp)
                + box("free", payload: Data("Secret Camera Owner".utf8))
        }
        return data as Data
    }

    private func box(_ type: String, payload: Data) -> Data {
        var size = UInt32(payload.count + 8).bigEndian
        return Data(bytes: &size, count: 4) + Data(type.utf8) + payload
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }
}
