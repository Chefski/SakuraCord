import AppKit
import DiscordProtocol
import SakuraCordModels
import SwiftUI

/// The rendered profile text owns layout throughout editing. The native field
/// occupies that same rectangle; editing accessories never add rows or padding.
struct ProfileInlineTextEditor<Content: View>: View {
    let label: LocalizedStringKey
    @Binding var value: String
    var font: Font = .system(size: 14)
    var nameStyle: DisplayNameStyle?
    var nameSize: CGFloat = 22
    var maximumLength: Int?
    @ViewBuilder let content: Content

    @State private var loadedFont: NSFont?
    @State private var isEditing = false
    @State private var isHovered = false
    @State private var originalValue = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
            .overlay(alignment: .topLeading) {
                TextField(label, text: $value)
                    .textFieldStyle(.plain)
                    .font(loadedFont.map(Font.init) ?? font)
                    .lineLimit(1)
                    .focused($isFocused)
                    .opacity(isEditing ? 1 : 0)
                    .allowsHitTesting(isEditing)
                    .accessibilityHidden(!isEditing)
                    .onSubmit { finish() }
                    .onExitCommand { value = originalValue; finish() }

            }
            .overlay {
                if !isEditing {
                    Button {
                        originalValue = value
                        isEditing = true
                        isFocused = true
                    } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovered, !isEditing {
                    Image(systemName: "pencil").font(.caption).padding(4)
                        .background(.regularMaterial, in: .circle).offset(x: 12, y: -8)
                        .allowsHitTesting(false)
                }
            }
        .onHover { isHovered = $0 }
        .onChange(of: value) { _, newValue in
            guard let maximumLength, newValue.utf16.count > maximumLength else { return }
            var length = 0
            value = String(newValue.prefix { character in
                length += character.utf16.count
                return length <= maximumLength
            })
        }
        .task(id: nameStyle?.fontID) {
            loadedFont = nil
            guard let definition = DiscordProfileNameStyles.catalog.fonts.first(where: { $0.id == nameStyle?.fontID }) else { return }
            loadedFont = try? await ProfileNameFontLoader.shared.font(definition, size: nameSize)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused, isEditing { finish() }
        }
    }

    private func finish() {
        isEditing = false
        isFocused = false
    }
}
