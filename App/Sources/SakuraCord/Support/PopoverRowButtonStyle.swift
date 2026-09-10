import SwiftUI

/// Insets resolve against the native popover's container shape.
struct PopoverRowButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, isSelected: isSelected)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(.primary.opacity(configuration.isPressed ? 0.18 : isHovered || isSelected ? 0.1 : 0), in: ConcentricRectangle(corners: .concentric(minimum: .fixed(8))))
                .contentShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(8))))
                .onHover { isHovered = $0 }
        }
    }
}
