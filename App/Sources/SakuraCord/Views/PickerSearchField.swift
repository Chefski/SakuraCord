import OSLog
import SakuraCordModels
import SwiftUI

struct PickerSearchField: View {
    @Binding var text: String
    let placeholder: String
    var accessibilityIdentifier = "picker-search"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .tint(SakuraCordAccentColor.color)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 40)
        .contentShape(ConcentricRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { isFocused = true }
        .glassEffect(
            .regular.interactive(),
            in: ConcentricRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
        .task {
            await Task.yield()
            isFocused = true
        }
    }
}

/// Shared search chrome for floating pickers; the caller owns text editing and keyboard behavior.
struct PickerSearchHeader<Input: View>: View {
    @Binding var text: String
    let focus: () -> Void
    @ViewBuilder let input: () -> Input

    var body: some View {
        HStack(spacing: ChatChromeMetrics.pickerSearchHeaderSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: ChatChromeMetrics.pickerSearchHeaderIconSize, weight: .medium))
                .foregroundStyle(.secondary)
            input().frame(maxWidth: .infinity)
            Button {
                text = ""
                focus()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear search")
            .accessibilityLabel("Clear search")
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
            .accessibilityHidden(text.isEmpty)
        }
        .padding(.horizontal, ChatChromeMetrics.pickerSearchHeaderInset)
        .frame(height: ChatChromeMetrics.pickerSearchHeaderHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
        .accessibilityIdentifier("picker-search")
    }
}
