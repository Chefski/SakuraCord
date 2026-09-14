import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileStyleColorOptions: View {
    @Binding var style: DisplayNameStyle
    let darkAppearance: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isColorPickerPresented = false

    private var effect: ProfileNameEffect { ProfileNameEffect(rawValue: style.effectID) ?? .solid }
    private var defaults: [UInt32] { DiscordProfileNameStyles.defaultColors(for: effect, darkAppearance: darkAppearance) }

    var body: some View {
        HStack(spacing: 8) {
            if effect == .solid || effect == .pop {
                defaultColorButton
            }
            customColorButton
        }
        .frame(width: 140, alignment: .trailing)
        .onChange(of: effect) { _, _ in isColorPickerPresented = false }
    }

    private var defaultColorButton: some View {
        let selected = effect == .solid ? style.colors.isEmpty : customColors == defaults
        return Button {
            isColorPickerPresented = false
            style.colors = effect == .solid ? [] : defaults
        } label: {
            Circle()
                .fill(Color(hex: defaults[0]))
                .overlay {
                    Circle().strokeBorder(selected ? SakuraCordAccentColor.color : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1)
                }
                .overlay {
                    Image(systemName: selected ? "checkmark" : "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 1)
                }
                .frame(width: 28, height: 28)
                .padding(.vertical, 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Default")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help("Default")
    }

    private var customColorButton: some View {
        Button { isColorPickerPresented = true } label: {
            Capsule()
                .fill(LinearGradient(colors: customColors.map(Color.init(hex:)), startPoint: .leading, endPoint: .trailing))
                .overlay { Capsule().stroke(.primary.opacity(0.15), lineWidth: 1) }
                .overlay {
                    Image(systemName: "pencil").font(.caption)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 1)
                }
                .frame(width: CGFloat(customColorCount) * 28, height: 28)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: customColorCount)
                .padding(.vertical, 2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit colours")
        .help("Edit colours")
        .sakuraCordColorPicker(isPresented: $isColorPickerPresented, colors: Binding(get: {
            customColors
        }, set: { colors in
            style.colors = colors
        }), colorCount: customColorCount ... customColorCount)
    }

    private var customColorCount: Int {
        switch effect {
        case .gradient: 2
        case .gummy: 4
        case .prism: 5
        default: 1
        }
    }

    private var customColors: [UInt32] {
        style.colors.count == customColorCount ? style.colors : defaults
    }

}
