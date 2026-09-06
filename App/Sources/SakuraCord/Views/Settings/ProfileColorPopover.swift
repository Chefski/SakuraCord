import AppKit
import SwiftUI

struct ProfileColorPopover: View {
    @Binding var value: UInt32
    @State private var hexText = ""
    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(hue: hue, saturation: 1, brightness: 1)
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    Circle().strokeBorder(.white, lineWidth: 2)
                        .background(.black.opacity(0.15), in: Circle())
                        .frame(width: 12, height: 12)
                        .offset(x: saturation * geometry.size.width - 6, y: (1 - brightness) * geometry.size.height - 6)
                }
                .clipShape(ConcentricRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    saturation = min(1, max(0, drag.location.x / geometry.size.width))
                    brightness = min(1, max(0, 1 - drag.location.y / geometry.size.height))
                    publish()
                })
                .accessibilityLabel("Saturation and brightness")
                .accessibilityValue("\(Int(saturation * 100)) percent saturation, \(Int(brightness * 100)) percent brightness")
            }
            .frame(height: 132)

            Slider(value: Binding(get: { hue }, set: { hue = $0; publish() }), in: 0 ... 1) { Text("Hue", bundle: #bundle) }
                .labelsHidden()
                .tint(Color(hue: hue, saturation: 1, brightness: 1))
            HStack {
                TextField("Hex color", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onChange(of: hexText) {
                        let text = hexText.hasPrefix("#") ? String(hexText.dropFirst()) : hexText
                        if text.count == 6, let parsed = UInt32(text, radix: 16), parsed != value { value = parsed }
                    }
            }
            // Keyboard users can adjust both axes without using the color plane.
            HStack {
                Slider(value: Binding(get: { saturation }, set: { saturation = $0; publish() }), in: 0 ... 1) { Text("Saturation", bundle: #bundle) }
                    .accessibilityLabel("Saturation")
                Slider(value: Binding(get: { brightness }, set: { brightness = $0; publish() }), in: 0 ... 1) { Text("Brightness", bundle: #bundle) }
                    .accessibilityLabel("Brightness")
            }
        }
        .padding(14)
        .profileEditorModalSize(width: 236)
        .onChange(of: value, initial: true) { synchronize() }
    }

    private func synchronize() {
        let color = NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                            green: CGFloat((value >> 8) & 255) / 255,
                            blue: CGFloat(value & 255) / 255, alpha: 1)
        hue = color.hueComponent
        saturation = color.saturationComponent
        brightness = color.brightnessComponent
        hexText = String(format: "#%06X", value)
    }

    private func publish() {
        let color = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
            .usingColorSpace(.sRGB) ?? .black
        let encoded = UInt32((color.redComponent * 255).rounded()) << 16
            | UInt32((color.greenComponent * 255).rounded()) << 8
            | UInt32((color.blueComponent * 255).rounded())
        if value != encoded { value = encoded }
    }
}
