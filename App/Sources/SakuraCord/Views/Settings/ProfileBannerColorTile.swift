import SakuraCordModels
import SwiftUI

struct ProfileBannerColorTile: View {
    let editor: ProfileEditorState
    let profile: UserProfile
    let height: CGFloat
    @State private var isPresented = false
    @State private var theme = ProfileThemeState()
    @Environment(\.displayScale) private var displayScale

    private var color: UInt32 {
        profile.accentHex ?? theme.colors(for: profile, scale: displayScale, isPreview: true).first ?? 0x41434A
    }

    var body: some View {
        Button { isPresented = true } label: {
            ConcentricRectangle(cornerRadius: 8)
                .fill(Color(hex: color))
                .overlay { Image(systemName: "pencil").foregroundStyle(.white).shadow(radius: 1) }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(ConcentricRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Banner Color")
        .sakuraCordColorPicker(isPresented: $isPresented, colors: Binding(get: {
            [color]
        }, set: { colors in
            if let color = colors.first { editor.setBannerColor(color) }
        }), colorCount: 1 ... 1)
        .contextMenu {
            if profile.accentHex != nil { Button("Reset Banner Color") { editor.setBannerColor(nil) } }
        }
        .task(id: theme.source(for: profile, scale: displayScale, isPreview: true)) {
            await theme.load(theme.source(for: profile, scale: displayScale, isPreview: true))
        }
    }
}
