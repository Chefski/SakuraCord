import AppKit

/// The official name renderer adjusts HSL lightness in bounded steps, then
/// derives its stroke/highlight colors from that adjusted foreground.
struct ProfileNameEffectColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    struct HSL {
        let hue: CGFloat
        let saturation: CGFloat
        let lightness: CGFloat
    }

    private init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        red = CGFloat((hex >> 16) & 255) / 255
        green = CGFloat((hex >> 8) & 255) / 255
        blue = CGFloat(hex & 255) / 255
    }

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        red = rgb.redComponent
        green = rgb.greenComponent
        blue = rgb.blueComponent
    }

    init(hue: CGFloat, saturation: CGFloat, lightness: CGFloat) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let section = hue * 6
        let intermediate = chroma * (1 - abs(section.truncatingRemainder(dividingBy: 2) - 1))
        let offset = lightness - chroma / 2
        let components: Self
        switch section {
        case ..<1: components = Self(red: chroma, green: intermediate, blue: 0)
        case ..<2: components = Self(red: intermediate, green: chroma, blue: 0)
        case ..<3: components = Self(red: 0, green: chroma, blue: intermediate)
        case ..<4: components = Self(red: 0, green: intermediate, blue: chroma)
        case ..<5: components = Self(red: intermediate, green: 0, blue: chroma)
        default: components = Self(red: chroma, green: 0, blue: intermediate)
        }
        red = components.red + offset
        green = components.green + offset
        blue = components.blue + offset
    }

    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var hsl: HSL {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0 else { return HSL(hue: 0, saturation: 0, lightness: lightness) }
        let hue: CGFloat
        switch maximum {
        case red: hue = ((green - blue) / delta + (green < blue ? 6 : 0)) / 6
        case green: hue = ((blue - red) / delta + 2) / 6
        default: hue = ((red - green) / delta + 4) / 6
        }
        return HSL(hue: hue, saturation: delta / (1 - abs(2 * lightness - 1)), lightness: lightness)
    }

    var luminance: CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func lightness(_ value: CGFloat, saturation: CGFloat? = nil) -> Self {
        let values = hsl
        return Self(hue: values.hue, saturation: saturation ?? values.saturation, lightness: min(1, max(0, value)))
    }

    func adjusted(against background: Self, ratio: CGFloat, saturation: CGFloat = 1) -> Self {
        var foreground = lightness(hsl.lightness, saturation: hsl.saturation * saturation)
        let background = background.lightness(background.hsl.lightness, saturation: background.hsl.saturation * saturation)
        let isDark = background.luminance <= 0.5
        for _ in 0 ..< 10 {
            let contrast = (max(foreground.luminance, background.luminance) + 0.05)
                / (min(foreground.luminance, background.luminance) + 0.05)
            guard contrast < ratio else { break }
            let lightness = foreground.hsl.lightness
            guard isDark ? lightness < 0.95 : lightness > 0.05 else { break }
            foreground = foreground.lightness(lightness + (isDark ? 0.05 : -0.05))
        }
        return foreground
    }

    var light1: NSColor { lightness(min(1, 1.2 * hsl.lightness)).color }
    var light2: NSColor { lightness(min(1, 1.6 * hsl.lightness)).color }
    var dark2: NSColor { lightness(0.2 * hsl.lightness).color }
    var toonStroke: NSColor { lightness(max(0.12, 0.4 * hsl.lightness)).color }
    var neonStroke: NSColor {
        lightness(min(0.6, hsl.lightness + 0.1), saturation: min(1, 1.2 * hsl.saturation)).color
    }
}
