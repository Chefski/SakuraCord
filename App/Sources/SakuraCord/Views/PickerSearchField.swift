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
