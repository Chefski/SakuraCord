import AppKit
import DiscordProtocol
import SakuraCordModels
import SwiftUI

/// Text determines its own size while editing; longer values wrap and grow the
/// profile rather than clipping inside the original, shorter label.
struct ProfileInlineTextEditor<Content: View>: View {
    let label: LocalizedStringKey
    @Binding var value: String
    var placeholder: String = ""
    var font: Font = .system(size: 14)
    var nameStyle: DisplayNameStyle?
    var nameSize: CGFloat = 22
    var maximumLength: Int?
    @ViewBuilder let content: Content

    @State private var loadedFont: NSFont?
    @State private var isEditing = false
    @State private var originalValue = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                ProfileInlineTextLayout {
                    Text(value.isEmpty ? placeholder : value)
                        .font(loadedFont.map(Font.init) ?? font)
                        .hidden().accessibilityHidden(true)
                    TextField("", text: $value, prompt: Text(placeholder), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(loadedFont.map(Font.init) ?? font)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(label)
                        .focused($isFocused)
                        .onSubmit { finish() }
                        .onExitCommand { value = originalValue; finish() }
                }
            } else {
                content.allowsHitTesting(false).accessibilityHidden(true)
                    .overlay {
                        Button {
                            originalValue = value
                            isEditing = true
                            isFocused = true
                        } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(label)
                            .accessibilityValue(value.isEmpty ? placeholder : value)
                    }
            }
        }
        .profileEditorTextHover(isEditing: isEditing)
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

/// Match the field to its text's natural width, capped by the space available.
/// The actual native field supplies the wrapped height and owns the editing UI.
private struct ProfileInlineTextLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalWidth = subviews[0].sizeThatFits(.unspecified).width
        let width = min(proposal.width ?? naturalWidth, naturalWidth)
        let field = subviews[1].sizeThatFits(fieldProposal(width: width, subviews: subviews))
        return CGSize(width: width, height: field.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[1].place(at: bounds.origin, proposal: fieldProposal(width: bounds.width, subviews: subviews))
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        subviews[1].dimensions(in: fieldProposal(width: bounds.width, subviews: subviews))[guide]
    }

    private func fieldProposal(width: CGFloat, subviews: Subviews) -> ProposedViewSize {
        // The native field reserves space for its insertion point. Let that
        // extend past the text's layout bounds, so focusing neither moves the
        // adjacent controls nor wraps an otherwise fitting line.
        let inset = max(0, subviews[1].sizeThatFits(.unspecified).width - subviews[0].sizeThatFits(.unspecified).width)
        return ProposedViewSize(width: width + inset, height: nil)
    }
}
