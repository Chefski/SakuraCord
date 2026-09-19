import AppKit
import SwiftUI

/// The SwiftUI controls use the same capsule, brightness, border and press
/// metrics as native timeline embed buttons.
struct PollButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PollButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct PollButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let press: CGFloat = configuration.isPressed ? 1 : 0
            let brightness = NativeTimelineComponentButtonVisualState.brightness(isHovered: isHovered && isEnabled, pressProgress: press)
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : .primary)
                .padding(.horizontal, 16)
                .frame(minHeight: NativeTimelineComponentButtonMetrics.height)
                .background {
                    Capsule().fill(prominent ? SakuraCordAccentColor.color : Color(nsColor: .controlColor))
                        .overlay { Capsule().fill(.black.opacity(0.12)) }
                }
                .overlay {
                    Capsule().strokeBorder((prominent ? Color.white : .primary).opacity(
                        NativeTimelineComponentButtonVisualState.borderAlpha(isHovered: isHovered, isEnabled: isEnabled)
                    ), lineWidth: 1).allowsHitTesting(false)
                }
                .brightness(brightness)
                .scaleEffect(NativeTimelineComponentButtonVisualState.scale(pressProgress: press))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onModalHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
        }
    }
}

struct PollInputSurface: ViewModifier {
    let isFocused: Bool
    let focus: () -> Void
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                ConcentricRectangle(cornerRadius: ChatChromeMetrics.composerCornerRadius)
                    .fill(.background.opacity(0.72))
                    .contentShape(ConcentricRectangle(cornerRadius: ChatChromeMetrics.composerCornerRadius))
                    .onTapGesture(perform: focus)
            }
            .overlay {
                ConcentricRectangle(cornerRadius: ChatChromeMetrics.composerCornerRadius)
                    .stroke(.primary.opacity(isFocused ? 0.3 : isHovered ? 0.2 : 0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onModalHover { isHovered = $0 }
    }
}

struct PollChoiceControl: View {
    let title: String
    @Binding var selection: Int
    let options: [SelectionFieldOption<Int>]
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 10) {
                Text(options.first(where: { $0.id == selection })?.title ?? title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(PollButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(options.first(where: { $0.id == selection })?.title ?? "")
        .overlay {
            StableAnchoredPopoverPresenter(isPresented: isPresented, configuration: .toolbarPanel, onDismiss: { isPresented = false }, content: {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(options) { option in
                            Button {
                                selection = option.id
                                isPresented = false
                            } label: {
                                HStack(spacing: 10) {
                                    Text(option.title).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark").opacity(selection == option.id ? 1 : 0)
                                }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(PopoverRowButtonStyle(isSelected: selection == option.id))
                        }
                    }.padding(6)
                }.frame(width: 248, height: min(360, CGFloat(options.count) * 36 + 12))
            })
        }
    }
}
