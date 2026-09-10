import AppKit
import CoreText
import Metal

/// A petal owns one occupied tile of the wordmark. At rest those tiles exactly
/// reconstruct the same antialiased text mask, including counters and edges.
struct SakuraCordWelcomePetalAtlas {
    struct Petal {
        var placement: SIMD4<Float>
        var variation: SIMD4<Float>
    }

    static let fontSize: CGFloat = 148
    static let cellSize = 4
    let size: SIMD2<Float>
    let mask: any MTLTexture
    let petals: any MTLBuffer
    let count: Int

    static func displayHeight(for width: CGFloat) -> CGFloat {
        min(fontSize, width * 0.112)
    }

    init?(device: any MTLDevice) {
        let font = NSFont.systemFont(ofSize: Self.fontSize, weight: .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "SakuraCord", attributes: [.font: font, .kern: -6]
        ))
        let outline = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for index in 0 ..< count {
                var transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                if let path = CTFontCreatePathForGlyph(font, glyphs[index], &transform) {
                    outline.addPath(path)
                }
            }
        }
        let bounds = outline.boundingBoxOfPath
        let cell = Self.cellSize
        let width = (Int(ceil(bounds.width)) / cell + 2) * cell
        let height = (Int(ceil(bounds.height)) / cell + 2) * cell
        let resolution = 3
        let pixelWidth = width * resolution
        let pixelHeight = height * resolution
        guard let bitmap = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
            bytesPerRow: pixelWidth, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let bytes = bitmap.data else { return nil }
        bitmap.scaleBy(x: CGFloat(resolution), y: CGFloat(resolution))
        var transform = CGAffineTransform(
            a: 1, b: 0, c: 0, d: 1,
            tx: (CGFloat(width) - bounds.width) / 2 - bounds.minX,
            ty: (CGFloat(height) - bounds.height) / 2 - bounds.minY
        )
        if let path = outline.copy(using: &transform) { bitmap.addPath(path) }
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.fillPath()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let mask = device.makeTexture(descriptor: descriptor) else { return nil }
        mask.replace(
            region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0,
            withBytes: bytes, bytesPerRow: pixelWidth
        )

        var petals: [Petal] = []
        var seed: UInt64 = 0x53414B555241
        func random() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24)
        }
        let coverage = bytes.assumingMemoryBound(to: UInt8.self)
        for row in stride(from: 0, to: height, by: cell) {
            for column in stride(from: 0, to: width, by: cell) {
                let occupied = (row * resolution ..< (row + cell) * resolution).contains { pixelY in
                    (column * resolution ..< (column + cell) * resolution).contains { pixelX in
                        coverage[pixelY * pixelWidth + pixelX] > 0
                    }
                }
                guard occupied else { continue }
                petals.append(Petal(
                    placement: SIMD4(Float(column) + Float(cell) / 2, Float(row) + Float(cell) / 2, random(), random()),
                    variation: SIMD4(random(), random(), random(), random())
                ))
            }
        }
        guard !petals.isEmpty, let buffer = device.makeBuffer(
            bytes: petals, length: MemoryLayout<Petal>.stride * petals.count, options: .storageModeShared
        ) else { return nil }
        size = SIMD2(Float(width), Float(height))
        self.mask = mask
        self.petals = buffer
        count = petals.count
    }
}
