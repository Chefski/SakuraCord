import AppKit
import CoreText

@MainActor
enum KeyboardShortcutLabel {
    private enum Keycap {
        case symbol(String)
        case text(String)
    }

    static func draw(
        _ shortcut: KeyboardShortcutChord?, placeholder: String,
        recordingModifiers: KeyboardShortcutModifiers = [],
        in bounds: NSRect, font: NSFont
    ) {
        let foreground = NSColor.labelColor.withAlphaComponent(1)
        guard shortcut != nil || !recordingModifiers.isEmpty else {
            draw(.text(placeholder), in: bounds, font: font, foreground: foreground)
            return
        }
        let modifiers: [(KeyboardShortcutModifiers, String)] = [
            (.control, "control"), (.option, "option"),
            (.shift, "shift"), (.command, "command"),
        ]
        var keys: [Keycap] = modifiers.compactMap { modifier, name in
            (shortcut?.modifiers ?? recordingModifiers).contains(modifier) ? .symbol(name) : nil
        }
        if let shortcut {
            if let name = keySymbol(shortcut.key) {
                keys.append(.symbol(name))
            } else {
                let text = KeyboardShortcutChord(key: shortcut.key, modifiers: [])?.displayName ?? shortcut.key.uppercased()
                keys.append(.text(text))
            }
        }
        let side: CGFloat = 18
        let gap: CGFloat = 3
        let totalWidth = side * CGFloat(keys.count) + gap * CGFloat(keys.count - 1)
        var originX = bounds.midX - totalWidth / 2
        let background = NSColor.unemphasizedSelectedContentBackgroundColor
        for key in keys {
            let rect = NSRect(x: originX, y: bounds.midY - side / 2, width: side, height: side)
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            background.setFill()
            box.fill()
            NSColor.separatorColor.setStroke()
            box.lineWidth = 1
            box.stroke()
            draw(key, in: rect, font: font, foreground: foreground)
            originX += side + gap
        }
    }

    private static func draw(_ key: Keycap, in rect: NSRect, font: NSFont, foreground: NSColor) {
        switch key {
        case let .symbol(name):
            let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [foreground]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            let contentBounds = rect.insetBy(dx: 3, dy: 3)
            let scale = min(
                contentBounds.width / image.size.width,
                min(contentBounds.height, font.capHeight + 1) / image.size.height
            )
            let height = image.size.height * scale
            let width = image.size.width * scale
            image.draw(
                in: NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
        case let .text(text):
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: foreground]
            ))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let scale = min(1, (rect.width - 4) / max(ink.width, 1))
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: rect.midX, y: rect.midY)
            if NSGraphicsContext.current?.isFlipped == true { context.scaleBy(x: 1, y: -1) }
            context.scaleBy(x: scale, y: scale)
            context.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private static func keySymbol(_ key: String) -> String? {
        switch key.unicodeScalars.first?.value {
        case 27: "escape"
        case 13, NSEvent.SpecialKey.enter.unicodeScalar.value: "return"
        case 9: "arrow.right.to.line"
        case 32: "space"
        case 127: "delete.left"
        case NSEvent.SpecialKey.deleteForward.unicodeScalar.value: "delete.right"
        case NSEvent.SpecialKey.upArrow.unicodeScalar.value: "arrow.up"
        case NSEvent.SpecialKey.downArrow.unicodeScalar.value: "arrow.down"
        case NSEvent.SpecialKey.leftArrow.unicodeScalar.value: "arrow.left"
        case NSEvent.SpecialKey.rightArrow.unicodeScalar.value: "arrow.right"
        case NSEvent.SpecialKey.home.unicodeScalar.value: "arrow.up.left"
        case NSEvent.SpecialKey.end.unicodeScalar.value: "arrow.down.right"
        case NSEvent.SpecialKey.pageUp.unicodeScalar.value: "arrow.up.to.line"
        case NSEvent.SpecialKey.pageDown.unicodeScalar.value: "arrow.down.to.line"
        default: nil
        }
    }
}
