import SwiftUI

/// Matches the profile surface's uniform concentric corners and minimum radius.
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
                .background(.primary.opacity(configuration.isPressed ? 0.18 : isHovered || isSelected ? 0.1 : 0), in: ConcentricRectangle(cornerRadius: 16))
                .contentShape(ConcentricRectangle(cornerRadius: 16))
                .onHover { isHovered = $0 }
        }
    }
}
