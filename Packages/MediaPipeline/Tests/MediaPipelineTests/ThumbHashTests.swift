import Foundation
import Testing
@testable import MediaPipeline

struct ThumbHashTests {
    // Placeholders arrive from the network and are decoded while rows draw, so
    // a short or truncated hash must yield nil instead of trapping, and a
    // valid one must match the reference decoder's output.
    @Test(arguments: [
        ("XwgSNJqAeIeEh4iIiHd/gAj4hw==", [18, 32, 66, 54, 44, 255]),
        ("msiJJRApUHljeIh4d41QF/WKj4iHiHeIeA==", [32, 32, 32, 44, 42, 243]),
        ("3/cBAYBre22nt2NfTycDdUU=", [5, 32, 122, 126, 128, 255]),
        ("", []),
        ("XwgS", []),
        ("XwgSNJqAeIeEh4iI", []),
        ("msiJJRApUHljeIh4d41Q", []),
        ("not base64!", []),
        ("XwgSMJqAeIeEh4iIiHd/gAj4hw==", []),
        ("XwgSMBqAeIeEh4iIiHd/gAj4hw==", [])
    ] as [(String, [Int])])
    func decodesReferenceOutputAndRejectsMalformedHashes(base64: String, expected: [Int]) {
        let bitmap = Data(base64Encoded: base64).flatMap { ThumbHash.bitmap(hash: [UInt8]($0)) }
        #expect(bitmap.map { [$0.height, $0.width] + $0.pixels.prefix(4).map(Int.init) } == (expected.isEmpty ? nil : expected))
        #expect((ThumbHash.image(base64: base64) != nil) == !expected.isEmpty)
    }
}
