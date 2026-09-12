import SwiftUI

/// Grid cards keep identical corners regardless of their surrounding containers.
enum ProfileEditorCardStyle {
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
}

extension View {
    func profileEditorCardHover() -> some View {
        modifier(ProfileEditorCardHover())
    }

    func profileEditorTextHover(isEnabled: Bool = true, isEditing: Bool = false) -> some View {
        modifier(ProfileEditorTextHover(isEnabled: isEnabled, isEditing: isEditing))
    }
}

private struct ProfileEditorCardHover: ViewModifier {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let highlighted = isEnabled && isHovered
        content
            .overlay {
                ProfileEditorCardStyle.shape
                    .fill(.white.opacity(highlighted ? 0.08 : 0))
                    .overlay {
                        ProfileEditorCardStyle.shape
                            .stroke(.white.opacity(highlighted ? 0.25 : 0), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: highlighted)
            }
            .onModalHover { isHovered = $0 }
    }
}

private struct ProfileEditorTextHover: ViewModifier {
    let isEnabled: Bool
    let isEditing: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.primary.opacity(isEnabled && (isEditing || isHovered) ? 0.3 : 0), lineWidth: 1)
                    .padding(-3).allowsHitTesting(false)
            }
            .onModalHover { isHovered = $0 }
    }
}

/// Section insertion is a line and a plus; only its hit area remains at rest.
struct ProfileWidgetSectionInsertion: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Color.clear.frame(height: 16).contentShape(Rectangle())
                .overlay {
                    HStack(spacing: 0) {
                        Rectangle().frame(height: 1)
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                        Rectangle().frame(height: 1)
                    }
                    .foregroundStyle(.secondary)
                    .opacity(isHovered || isFocused ? 1 : 0)
                    .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain).focused($isFocused)
        .onModalHover { isHovered = $0 }
        .nativeHoverHelp(title)
        .accessibilityLabel(title)
    }
}

struct ProfileWidgetAddField: View {
    var alwaysVisible = false
    let action: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
                .overlay {
                    Label("Add Field", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.primary.opacity(isHovered ? 0.06 : 0), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                        .opacity(alwaysVisible || isHovered || isFocused ? 1 : 0)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain).focused($isFocused)
        .onModalHover { isHovered = $0 }
        .accessibilityLabel("Add Field")
    }
}
