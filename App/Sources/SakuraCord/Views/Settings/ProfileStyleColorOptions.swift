import DiscordProtocol
import SakuraCordModels
import SwiftUI

struct ProfileStyleColorOptions: View {
    @Binding var style: DisplayNameStyle
    let darkAppearance: Bool
    @State private var isColorPickerPresented = false

    private var effect: ProfileNameEffect { ProfileNameEffect(rawValue: style.effectID) ?? .solid }
    private var defaults: [UInt32] { DiscordProfileNameStyles.defaultColors(for: effect, darkAppearance: darkAppearance) }

    var body: some View {
        Button { isColorPickerPresented = true } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: customColors.map(Color.init(hex:)), startPoint: .leading, endPoint: .trailing))
                .overlay { Image(systemName: "pencil").font(.caption2).foregroundStyle(.white).shadow(radius: 1) }
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit colours")
        .help("Edit colours")
        .sakuraCordColorPicker(isPresented: $isColorPickerPresented, colors: Binding(get: {
            customColors
        }, set: { colors in
            style.colors = colors
        }), colorCount: customColorCount ... customColorCount)
        .id(effect)
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
