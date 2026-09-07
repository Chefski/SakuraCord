import SwiftUI

extension View {
    /// Uses the app's shared semitransient host and topmost-popover Escape routing.
    func sakuraCordColorPicker(isPresented: Binding<Bool>, colors: Binding<[UInt32]>, colorCount: ClosedRange<Int> = 1 ... 1) -> some View {
        modifier(SakuraCordColorPickerPopover(isPresented: isPresented, colors: colors, colorCount: colorCount))
    }

    func sakuraCordColorPicker(isPresented: Binding<Bool>, color: Binding<UInt32>) -> some View {
        sakuraCordColorPicker(isPresented: isPresented, colors: Binding(get: { [color.wrappedValue] }, set: {
            if let first = $0.first { color.wrappedValue = first }
        }))
    }
}

private struct SakuraCordColorPickerPopover: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var colors: [UInt32]
    let colorCount: ClosedRange<Int>
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay {
            StableAnchoredPopoverPresenter(isPresented: isPresented, configuration: .toolbarPanel,
                                           onDismiss: { isPresented = false }, content: {
                SakuraCordColorPicker(colors: $colors, colorCount: colorCount)
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.locale, locale)
                    .disabled(!isEnabled)
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
