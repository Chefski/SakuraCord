import CoreGraphics
import Foundation
import ImageIO
@testable import SakuraCord
import Testing

@Test(arguments: [false, true])
func `compressed animation storage preserves pixels color and row stride under concurrent reads`(usesP3: Bool) throws {
    let space = try #require(CGColorSpace(name: usesP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: 137, height: 91, bitsPerComponent: 8,
        bytesPerRow: 640, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(try #require(CGColor(colorSpace: space, components: [0.2, 0.8, 0.4, 0.6])))
    context.fill(CGRect(x: 9, y: 7, width: 115, height: 71))
    let original = try #require(context.makeImage())
    let expected = try #require(original.dataProvider?.data) as Data
    let stored = CompressedAnimatedFrame.store(original)
    #expect(stored.storedByteCount < expected.count)
    #expect(stored.image.width == original.width)
    #expect(stored.image.height == original.height)
    #expect(stored.image.bytesPerRow == original.bytesPerRow)
    #expect(stored.image.bitmapInfo == original.bitmapInfo)
    #expect(stored.image.colorSpace == original.colorSpace)
    let presented = CompressedAnimatedFrame.transientImage(stored.image)
    #expect(presented !== stored.image)
    #expect(presented.dataProvider?.data as Data? == expected)
    DispatchQueue.concurrentPerform(iterations: 16) { _ in
        let bytes = stored.image.dataProvider?.data as Data?
        #expect(bytes == expected)
    }
    func render(_ image: CGImage) throws -> Data {
        let rendered = try #require(CGContext(
            data: nil, width: 137, height: 91, bitsPerComponent: 8,
            bytesPerRow: 640, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        rendered.draw(image, in: CGRect(x: 0, y: 0, width: 137, height: 91))
        return try #require(rendered.makeImage()?.dataProvider?.data) as Data
    }
    let expectedRendering = try render(original)
    let output = try render(stored.image)
    for row in 0 ..< 91 {
        let pixels = row * 640 ..< row * 640 + 137 * 4
        #expect(output[pixels] == expectedRendering[pixels])
    }
    let animation = DecodedAnimatedImage(
        frames: [original, stored.image], frameDurations: [0.1, 0.2], playCount: 2,
        compressedFrameData: [nil, stored.compressedData]
    )
    let archived = try #require(PreparedAnimatedImage.encode(animation))
    let restored = try PreparedAnimatedImage.decode(archived)
    #expect(restored.frameDurations == animation.frameDurations)
    #expect(restored.playCount == 2)
    #expect(restored.frames[1].dataProvider?.data as Data? == expected)
    let restoredRendering = try render(restored.frames[1])
    for row in 0 ..< 91 {
        let pixels = row * 640 ..< row * 640 + 137 * 4
        #expect(restoredRendering[pixels] == expectedRendering[pixels])
    }
}

@Test(arguments: ["public.png", "com.compuserve.gif"])
func `compressed animation frames match ImageIO including transparent frame composition`(format: String) throws {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: nil, width: 137, height: 91, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, format as CFString, 3, nil))
    for index in 0 ..< 3 {
        context.clear(CGRect(x: 0, y: 0, width: 137, height: 91))
        context.setFillColor(CGColor(red: CGFloat(index) / 3, green: 0.7, blue: 0.4, alpha: 0.6))
        context.fill(CGRect(x: index * 20, y: 10, width: 80, height: 70))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1],
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1],
        ] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    let decoded = try DecodedAnimatedImage(data: data as Data, maximumPixelDimension: nil)
    #expect(decoded.frames.count == 3)
    #expect(decoded.storedByteCount < decoded.estimatedByteCount)
    let source = try #require(CGImageSourceCreateWithData(data, nil))
    let archive = try #require(PreparedAnimatedImage.encode(decoded))
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try archive.write(to: file, options: .atomic)
    let mapped = try Data(contentsOf: file, options: .alwaysMapped)
    let restored = try PreparedAnimatedImage.decode(mapped)
    // Clearing or evicting a cache file cannot invalidate a mounted image.
    try FileManager.default.removeItem(at: file)
    #expect(restored.frameDurations == decoded.frameDurations)
    #expect(restored.estimatedByteCount == decoded.estimatedByteCount)
    for index in decoded.frames.indices {
        #expect(restored.frames[index].dataProvider?.data as Data? == decoded.frames[index].dataProvider?.data as Data?)
    }
    var corrupt = archive
    corrupt[corrupt.count - 33] ^= 0xFF
    #expect(throws: CocoaError.self) { try PreparedAnimatedImage.decode(corrupt) }
    #expect(throws: CocoaError.self) { try PreparedAnimatedImage.decode(Data(archive.dropLast())) }
    var oversizedHeader = archive
    oversizedHeader.replaceSubrange(8 ..< 12, with: [0xFF, 0xFF, 0xFF, 0xFF])
    #expect(throws: CocoaError.self) { try PreparedAnimatedImage.decode(oversizedHeader) }
    for index in 1 ..< 3 {
        let expected = try #require(CGImageSourceCreateImageAtIndex(source, index, [
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary))
        #expect(decoded.frames[index].dataProvider?.data as Data? == expected.dataProvider?.data as Data?)
    }
}
