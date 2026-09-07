import AppKit

/// Keeps unedited RGB stops intact, including palettes with differing saturation
/// and value. Each shared slider replaces that component across all stops.
struct ColorPickerPalette {
    var stops: [Stop]
    private var removedStops: [Stop] = []
    var saturation: Double
    var value: Double

    init(colors: [UInt32], count: ClosedRange<Int>) {
        var colors = Array(colors.prefix(count.upperBound))
        while colors.count < count.lowerBound { colors.append(colors.last ?? 0xFFFFFF) }
        stops = colors.map(Stop.init)
        saturation = stops.reduce(0) { $0 + $1.saturation } / Double(stops.count)
        value = stops.reduce(0) { $0 + $1.value } / Double(stops.count)
    }

    var colors: [UInt32] { stops.map(\.hex) }

    mutating func setHue(_ hue: Double, at index: Int) {
        stops[index].hue = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
    }

    mutating func setSaturation(_ saturation: Double) {
        self.saturation = min(max(saturation, 0), 1)
        for index in stops.indices { stops[index].saturation = self.saturation }
        for index in removedStops.indices { removedStops[index].saturation = self.saturation }
    }

    mutating func setValue(_ value: Double) {
        self.value = min(max(value, 0), 1)
        for index in stops.indices { stops[index].value = self.value }
        for index in removedStops.indices { removedStops[index].value = self.value }
    }

    mutating func apply(_ color: UInt32, at index: Int) {
        let stop = Stop(color)
        setHue(stop.hue, at: index)
        setSaturation(stop.saturation)
        setValue(stop.value)
    }

    mutating func add() {
        let existingHues = stops.map(\.hue)
        let suggestedHue = Self.hueInLargestGap(between: existingHues)
        var stop: Stop
        if let restored = removedStops.popLast() {
            stop = restored
            if existingHues.contains(where: {
                SakuraCordGradientTheme.circularHueDistance($0, stop.hue) < SakuraCordGradientTheme.minimumHueSpacing
            }) { stop.hue = suggestedHue }
        } else {
            stop = stops[0]
            stop.hue = suggestedHue
            stop.saturation = saturation
            stop.value = value
        }
        stops.append(stop)
    }

    mutating func remove(at index: Int) {
        removedStops.append(stops.remove(at: index))
    }

    // Preserve the designer's largest-gap placement for newly added colors.
    private static func hueInLargestGap<S: Sequence>(between hues: S) -> Double
        where S.Element == Double
    {
        let sortedHues = hues.sorted()
        guard !sortedHues.isEmpty else { return 0 }

        var largestGapStart = sortedHues[0]
        var largestGap = 0.0
        for index in sortedHues.indices {
            let start = sortedHues[index]
            let end = index == sortedHues.index(before: sortedHues.endIndex)
                ? sortedHues[0] + 1
                : sortedHues[sortedHues.index(after: index)]
            let gap = end - start
            if gap > largestGap {
                largestGap = gap
                largestGapStart = start
            }
        }
        return (largestGapStart + largestGap / 2).truncatingRemainder(dividingBy: 1)
    }

    func interpolated(to target: Self, progress: Double) -> Self {
        var result = target
        result.saturation = saturation + (target.saturation - saturation) * progress
        result.value = value + (target.value - value) * progress
        for index in stops.indices {
            let source = stops[index]
            let end = target.stops[index]
            var delta = end.hue - source.hue
            if delta > 0.5 { delta -= 1 }
            if delta < -0.5 { delta += 1 }
            result.setHue(source.hue + delta * progress, at: index)
            result.stops[index].saturation = source.saturation + (end.saturation - source.saturation) * progress
            result.stops[index].value = source.value + (end.value - source.value) * progress
        }
        return result
    }

    static func parseHex(_ text: String) -> UInt32? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard [3, 6].contains(digits.utf8.count),
              digits.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) })
        else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        return UInt32(digits, radix: 16)
    }

    struct Stop {
        var hue: Double
        var saturation: Double
        var value: Double

        init(_ hex: UInt32) {
            let color = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                                green: CGFloat((hex >> 8) & 255) / 255,
                                blue: CGFloat(hex & 255) / 255, alpha: 1)
            hue = color.hueComponent
            saturation = color.saturationComponent
            value = color.brightnessComponent
        }

        var hex: UInt32 {
            let color = NSColor(hue: hue, saturation: saturation, brightness: value, alpha: 1)
                .usingColorSpace(.sRGB) ?? .black
            return UInt32((color.redComponent * 255).rounded()) << 16
                | UInt32((color.greenComponent * 255).rounded()) << 8
                | UInt32((color.blueComponent * 255).rounded())
        }
    }
}
