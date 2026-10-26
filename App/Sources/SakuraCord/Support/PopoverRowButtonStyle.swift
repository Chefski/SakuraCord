import SwiftUI

/// Matches the profile surface's uniform concentric corners and minimum radius.
struct PopoverRowButtonStyle: ButtonStyle {
    var isSelected = false
    var cornerRadius: CGFloat = InterfaceScale.metric(16)

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let cornerRadius: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(.primary.opacity(configuration.isPressed ? 0.18 : isHovered || isSelected ? 0.1 : 0), in: ConcentricRectangle(cornerRadius: cornerRadius))
                .contentShape(ConcentricRectangle(cornerRadius: cornerRadius))
                .onModalHover { isHovered = $0 }
        }
    }
}
