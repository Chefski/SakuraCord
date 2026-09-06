import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaPipeline

struct ProfileImagePaletteTests {
    // Golden outputs were produced by upstream quantize.js and independently
    // matched against the clean client's bundled quantizer. Palette order is
    // part of the save contract: its first two entries become theme colours.
    @Test(arguments: [UInt32(1), 17, 42, 99])
    func medianCutMatchesReferenceOrdering(seed: UInt32) {
        var state = seed
        let pixels = (0 ..< 1_000).map { _ -> UInt32 in
            state = state &* 1_664_525 &+ 1_013_904_223
            return state >> 8
        }
        let expected: [UInt32: [UInt32]] = [
            1: [0xBAA2A2, 0x1D8583, 0xA0207A, 0x9F9D22, 0x599EA8],
            17: [0xB6A3A2, 0x1F7C7D, 0x9D217F, 0xA2AB1D, 0x58909C],
            42: [0x859DA1, 0x217F7F, 0xA42281, 0x9FA51F, 0xE89E9E],
            99: [0x48649D, 0xDF847D, 0x60E081, 0x585F1C, 0xA954A4]
        ]
        #expect(ProfileMedianCut.palette(pixels: pixels) == expected[seed])
    }

    @Test func opaqueWebPPreservesFractionalChromaBeforeQuantizing() throws {
        // Synthetic 32×32 gradient, encoded with libwebp 1.6. The reference
        // palette uses fractional YUV interpolation and upstream quantize.js;
        // early chroma rounding changes the first saved theme colour.
        let encoded = """
        UklGRuoAAABXRUJQVlA4IN4AAAAwBwCdASogACAAPpFAm0olo6IhqAgAsBIJbACdMoR0St5bFe8Y/sZ6JJMqnn3ISjIQ9T0Cmr3g
        Sw7doF8AQyLpZwAA/v6/K6fE+Jb3P1vqk7gtS+19KuFqzZOyXHXh1AHtiFjW0wmMSbOdh81Bhqb1/LS9X2sbL4rkWjmg7nn7UBkA
        kZunPT/oRd4Rhp1xWuoZKrcTF2IEaEBr0+Qj8oPeR5WCOvXoA9AyrqkhfN/zNSe4EjHLuh2d7Z+mNfizxJiyf8zyQfSAl/KPIq0e
        v8b828mX0q/3Cfg/cS284AA=
        """
        let data = try #require(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
        #expect(try ProfileImagePalette.colors(in: data) == [0x8C7AAC, 0x266941, 0xCEC126, 0x60324F, 0xE08EC6])
    }

    @Test func imageSamplingIgnoresTransparentAndNearlyWhitePixels() throws {
        // Only the first pixel of each ten-pixel row is sampled. Unsampled
        // yellow pixels would dominate a whole-image average or histogram.
        let rows: [[UInt8]] = [
            [224, 40, 56, 255], [0, 0, 0, 0], [40, 192, 80, 255], [252, 252, 252, 255],
            [32, 64, 224, 255], [0, 0, 0, 0], [224, 40, 56, 255], [0, 0, 0, 0],
            [40, 192, 80, 255], [255, 255, 255, 255]
        ]
        let yellow: [UInt8] = [248, 232, 16, 255]
        let bytes: [UInt8] = rows.flatMap { $0 + Array(repeating: yellow, count: 9).flatMap { $0 } }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(CGImage(width: 10, height: 10, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: 40, space: space,
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(try ProfileImagePalette.colors(in: data as Data) == [0x2CC454, 0x2444E4, 0xE42C3C, 0xB87894, 0x54C86C])
    }
}
