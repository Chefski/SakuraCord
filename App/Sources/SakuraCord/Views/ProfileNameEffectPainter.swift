import AppKit
import CoreText
import SakuraCordModels

enum ProfileNameEffectPainter {
    static func draw(
        _ layout: ProfileNameTextLayout, in context: CGContext, fontSize: CGFloat,
        effect: ProfileNameEffect, colors: [ProfileNameEffectColor], elapsed: Double,
        looping: Bool
    ) {
        let main = colors.first ?? ProfileNameEffectColor(.labelColor)
        let duration = effect == .prism ? 2.0 : 4.0
        let progress = looping ? elapsed.truncatingRemainder(dividingBy: duration) / duration : min(1, elapsed / duration)
        let path = layout.path
        let box = CGRect(x: 0, y: -layout.descent, width: layout.width, height: layout.ascent + layout.descent)
        switch effect {
        case .solid:
            fill(path, color: main.color, in: context)
        case .gradient:
            let stops = colors.enumerated().map { index, color in
                (color.color, colors.count == 1 ? CGFloat(0) : 0.1 + 0.8 * CGFloat(index) / CGFloat(colors.count - 1))
            }
            gradient(path, stops: stops, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), in: context)
        case .prism:
            let palette = colors.isEmpty ? [main] : colors
            let cycle = max(layout.width, 38)
            let shift = CGFloat(progress) * cycle
            var stops: [(NSColor, CGFloat)] = []
            for index in 0 ... palette.count * 2 {
                stops.append((palette[index % palette.count].color, CGFloat(index) / CGFloat(palette.count * 2)))
            }
            gradient(path, stops: stops, start: CGPoint(x: -shift, y: 0), end: CGPoint(x: cycle * 2 - shift, y: 0), in: context)
        case .neon:
            context.saveGState()
            context.setShadow(offset: .zero, blur: 4 + fontSize * 0.12, color: main.color.cgColor)
            stroke(path, color: main.neonStroke, width: 1 + fontSize * 0.04, in: context)
            let intensity = ProfileNameEffectTiming.value(progress, stops: [
                (0, 0), (0.15, 0), (0.16, 1), (0.18, 0), (0.20, 0), (0.22, 1),
                (0.23, 0), (0.25, 0), (0.28, 1), (0.50, 0), (1, 0),
            ], control: ((0.24, 0.31), (0.36, 0.93)))
            let flicker = main.lightness(0.85, saturation: min(1, min(1, main.hsl.saturation * 100) * (main.hsl.saturation * 1.1 + 0.1))).color
            fill(path, color: NSColor.white.blended(withFraction: intensity, of: flicker) ?? .white, in: context)
            context.restoreGState()
        case .toon:
            stroke(path, color: main.toonStroke, width: 1.6 + fontSize * 0.04, in: context)
            let shift = CGFloat(ProfileNameEffectTiming.value(progress, stops: [(0, 0), (0.05, 0), (0.55, 1), (1, 1)]))
            gradient(path, stops: [
                (.white, 0), (main.light2, 0.08), (main.light1, 0.15), (main.color, 0.25),
                (main.light2, 0.45), (main.color, 0.55), (.white, 0.75),
                (main.light2, 0.83), (main.light1, 0.90), (main.color, 1),
            ], start: CGPoint(x: 0, y: box.maxY + box.height * 3 * shift),
            end: CGPoint(x: 0, y: box.maxY + box.height * 3 * shift - box.height * 4), in: context)
        case .pop:
            let front = ProfileNameEffectTiming.value(progress, stops: [(0, 0), (0.18, -0.05), (0.35, 0.08), (0.5, 0), (1, 0)])
            let back = ProfileNameEffectTiming.value(progress, stops: [(0, 0.08), (0.18, 0.13), (0.35, 0), (0.5, 0.08), (1, 0.08)])
            context.saveGState()
            context.translateBy(x: 0, y: -CGFloat(back) * fontSize)
            stroke(path, color: main.color, width: 1.2 + fontSize * 0.04, in: context)
            let sweep = CGFloat(ProfileNameEffectTiming.value(progress, stops: [(0, 0), (0.5, 1), (1, 1)]))
            gradient(path, stops: [
                (main.light1, 0), (main.light1, 0.06), (main.color, 0.20), (main.color, 0.50),
                (main.light1, 0.56), (main.color, 0.70), (main.color, 1),
            ], start: CGPoint(x: box.maxX + box.width * sweep, y: box.maxY + box.height * sweep),
            end: CGPoint(x: -box.width + box.width * sweep, y: box.minY - box.height + box.height * sweep), in: context)
            context.restoreGState()
            context.saveGState()
            context.translateBy(x: 0, y: -CGFloat(front) * fontSize)
            stroke(path, color: main.dark2, width: 1.2 + fontSize * 0.04, in: context)
            fill(path, color: .white, in: context)
            context.restoreGState()
        case .gummy:
            for outline in layout.outlines {
                let localElapsed = max(0, elapsed - Double(outline.characterIndex) * 0.05)
                let localProgress = looping ? localElapsed.truncatingRemainder(dividingBy: 4) / 4 : min(1, localElapsed / 4)
                let scale = ProfileNameEffectTiming.value(localProgress, stops: [
                    (0, 1), (0.07, 1.28), (0.14, 0.82), (0.21, 1.1), (0.28, 0.96), (0.35, 1), (1, 1),
                ])
                let bounds = outline.path.boundingBoxOfPath
                context.saveGState()
                context.translateBy(x: bounds.midX, y: bounds.midY)
                context.scaleBy(x: scale, y: 2 - scale)
                context.translateBy(x: -bounds.midX, y: -bounds.midY)
                let color = colors.isEmpty ? main : colors[outline.characterIndex % colors.count]
                fill(outline.path, color: color.color, in: context)
                context.restoreGState()
            }
        }
        context.textPosition = .zero
        for run in layout.bitmapRuns { CTRunDraw(run, context, CFRange()) }
    }

    private static func fill(_ path: CGPath, color: NSColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    private static func stroke(_ path: CGPath, color: NSColor, width: CGFloat, in context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
    }

    private static func gradient(
        _ path: CGPath, stops: [(NSColor, CGFloat)], start: CGPoint, end: CGPoint, in context: CGContext
    ) {
        guard !stops.isEmpty else { return }
        let stops = stops.count == 1 ? [(stops[0].0, CGFloat(0)), (stops[0].0, CGFloat(1))] : stops
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map { $0.0.cgColor } as CFArray, locations: stops.map(\.1)
        ) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
