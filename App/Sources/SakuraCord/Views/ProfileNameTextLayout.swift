import AppKit
import CoreText

/// One shaped line, shared by the static and animated painters. CoreText keeps
/// fallback emoji and non-Latin glyphs intact while custom effects use outlines.
struct ProfileNameTextLayout {
    struct GlyphOutline {
        let path: CGPath
        let characterIndex: Int
    }

    let line: CTLine
    let outlines: [GlyphOutline]
    let bitmapRuns: [CTRun]
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let leading: CGFloat

    init(name: String, font: NSFont, tracking: CGFloat, gummy: Bool, maximumWidth: CGFloat? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .kern: tracking, .ligature: gummy ? 0 : 1,
            .foregroundColor: NSColor.labelColor,
        ]
        let original = CTLineCreateWithAttributedString(NSAttributedString(string: name, attributes: attributes))
        let originalWidth = CGFloat(CTLineGetTypographicBounds(original, nil, nil, nil))
        if let maximumWidth, maximumWidth < originalWidth {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(original, max(0, maximumWidth), .end, token) ?? token
        } else {
            line = original
        }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        self.ascent = ascent
        self.descent = descent
        self.leading = leading

        var characterByOffset: [Int: Int] = [:]
        var offset = 0
        var styledIndex = 0
        for character in name {
            let isEmoji = character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || character.unicodeScalars.contains { $0.value == 0xFE0F }
            for scalarOffset in 0 ..< character.utf16.count {
                characterByOffset[offset + scalarOffset] = styledIndex
            }
            offset += character.utf16.count
            if !isEmoji, !character.isWhitespace { styledIndex += 1 }
        }
        var outlines: [GlyphOutline] = []
        var bitmapRuns: [CTRun] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] as? NSFont else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indexes = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetStringIndices(run, CFRange(), &indexes)
            if CTFontGetSymbolicTraits(runFont).contains(.traitColorGlyphs) {
                bitmapRuns.append(run)
                continue
            }
            for index in 0 ..< count {
                var transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                if let path = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) {
                    outlines.append(GlyphOutline(path: path, characterIndex: characterByOffset[indexes[index]] ?? 0))
                }
            }
        }
        self.outlines = outlines
        self.bitmapRuns = bitmapRuns
    }

    var path: CGPath {
        let path = CGMutablePath()
        for outline in outlines { path.addPath(outline.path) }
        return path
    }
}
