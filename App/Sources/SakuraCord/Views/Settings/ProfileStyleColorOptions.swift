import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileStyleColorOptions: View {
    @Binding var style: DisplayNameStyle
    let darkAppearance: Bool
    @State private var colorSlot: Int?

    private var effect: ProfileNameEffect { ProfileNameEffect(rawValue: style.effectID) ?? .solid }
    private var defaults: [UInt32] { DiscordProfileNameStyles.defaultColors(for: effect, darkAppearance: darkAppearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 5) {
                Text("Choose Colour", bundle: #bundle).font(.headline)
                Image(systemName: "sparkles").font(.caption).accessibilityLabel("Exclusive to Nitro")
            }
            HStack(alignment: .top, spacing: 10) {
                ProfilePaletteSwatch(colors: defaults, selected: style.colors == defaults) { style.colors = defaults }
                    .frame(width: 50, height: 50)
                    .accessibilityLabel("Default")
                if effect == .gradient || effect == .prism {
                    VStack(spacing: 3) {
                        ForEach(ProfileStyleColorSlot.slots(for: effect)) { slot in
                            customButton(slot: slot.rawValue)
                        }
                    }
                    .frame(width: 50, height: 50)
                } else {
                    customButton(slot: 0).frame(width: 50, height: 50)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: effect == .solid || effect == .neon || effect == .toon || effect == .pop ? 6 : 3), spacing: 8) {
                    ForEach(Self.palettes(for: effect), id: \.self) { colors in
                        ProfilePaletteSwatch(colors: colors, selected: style.colors == colors) { style.colors = colors }
                            .frame(height: 20)
                            .accessibilityLabel(colors.map { String(format: "#%06X", $0) }.joined(separator: ", "))
                    }
                }
            }
        }
    }

    private func customButton(slot: Int) -> some View {
        Button { colorSlot = slot } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: style.colors.indices.contains(slot) ? style.colors[slot] : defaults[slot]))
                .overlay { Image(systemName: "pencil").font(.caption2).foregroundStyle(.white).shadow(radius: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom colour \(slot + 1)")
        .profileEditorOverlay(isPresented: Binding(get: { colorSlot == slot }, set: { if !$0 { colorSlot = nil } }), title: "Choose Colour") {
            ProfileColorPopover(value: Binding(get: {
                if effect == .gummy { return gummyBaseColor }
                return style.colors.indices.contains(slot) ? style.colors[slot] : defaults[slot]
            }, set: { value in
                if effect == .gummy {
                    style.colors = Self.gummyPalette(from: value)
                } else {
                    if style.colors.count != defaults.count { style.colors = defaults }
                    style.colors[slot] = value
                }
            }))
        }
    }

    private var gummyBaseColor: UInt32 {
        let first = ProfileNameEffectColor(hex: style.colors.first ?? defaults[0])
        let hue = (first.hsl.hue + 18.0 / 360).truncatingRemainder(dividingBy: 1)
        return Self.hex(ProfileNameEffectColor(hue: hue, saturation: 0.78, lightness: 0.72))
    }

    private static func gummyPalette(from color: UInt32) -> [UInt32] {
        let hue = ProfileNameEffectColor(hex: color).hsl.hue
        let stops = [
            GummyColorStop(hueOffsetDegrees: -18, saturation: 0.54, lightness: 0.72),
            GummyColorStop(hueOffsetDegrees: -5, saturation: 0.66, lightness: 0.60),
            GummyColorStop(hueOffsetDegrees: 9, saturation: 0.56, lightness: 0.68),
            GummyColorStop(hueOffsetDegrees: 22, saturation: 0.60, lightness: 0.63)
        ]
        return stops.map { stop in
            let shifted = (hue + stop.hueOffsetDegrees / 360 + 1).truncatingRemainder(dividingBy: 1)
            return hex(ProfileNameEffectColor(hue: shifted, saturation: stop.saturation, lightness: stop.lightness))
        }
    }

    private struct GummyColorStop {
        let hueOffsetDegrees: CGFloat
        let saturation: CGFloat
        let lightness: CGFloat
    }

    private static func hex(_ color: ProfileNameEffectColor) -> UInt32 {
        UInt32((color.red * 255).rounded()) << 16 | UInt32((color.green * 255).rounded()) << 8 | UInt32((color.blue * 255).rounded())
    }

    static func palettes(for effect: ProfileNameEffect) -> [[UInt32]] {
        let catalog = DiscordProfileNameStyles.catalog
        return switch effect {
        case .gradient: catalog.gradients
        case .gummy: catalog.gummyPalettes
        case .prism: catalog.prismPalettes
        default: catalog.solidColors.map { [$0] }
        }
    }
}

private enum ProfileStyleColorSlot: Int, Identifiable, CaseIterable {
    case first, second, third, fourth, fifth
    var id: Self { self }
    static func slots(for effect: ProfileNameEffect) -> [Self] {
        effect == .prism ? allCases : [.first, .second]
    }
}

private struct ProfilePaletteSwatch: View {
    let colors: [UInt32]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ConcentricRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: colors.map(Color.init(hex:)), startPoint: .leading, endPoint: .trailing))
                .overlay {
                    if selected { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 1) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
