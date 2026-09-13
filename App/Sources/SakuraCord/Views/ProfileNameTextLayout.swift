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

    init(name: String, font: NSFont, tracking: CGFloat, gummy: Bool, maximumWidth: CGFloat? = nil, characterOffset: Int = 0) {
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
        var styledIndex = characterOffset
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

    static func wrappedLines(name: String, font: NSFont, tracking: CGFloat, gummy: Bool, width: CGFloat) -> [Self] {
        let source = name as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(
            string: name, attributes: [.font: font, .kern: tracking, .ligature: gummy ? 0 : 1]
        ))
        var offset = 0
        var lines: [Self] = []
        var characterOffset = 0
        while offset < source.length {
            let suggested = CTTypesetterSuggestLineBreak(typesetter, offset, Double(max(1, width)))
            var length = max(source.rangeOfComposedCharacterSequence(at: offset).length, suggested)
            var text = source.substring(with: NSRange(location: offset, length: min(length, source.length - offset)))
            var line = Self(name: text, font: font, tracking: tracking, gummy: gummy, characterOffset: characterOffset)
            // A name may be one unbroken word. Break at a complete grapheme
            // instead of letting the word extend beyond the profile's bounds.
            while line.width > width, text.count > 1 {
                text.removeLast()
                length = text.utf16.count
                line = Self(name: text, font: font, tracking: tracking, gummy: gummy, characterOffset: characterOffset)
            }
            lines.append(line)
            characterOffset += text.filter { character in
                !character.isWhitespace && !character.unicodeScalars.contains {
                    $0.properties.isEmojiPresentation || $0.value == 0xFE0F
                }
            }.count
            offset += length
        }
        return lines
    }
}
