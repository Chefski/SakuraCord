import AppKit
import DiscordProtocol
import SwiftUI

/// Ordinary name labels use only the typeface; their owner keeps color,
/// spacing, truncation, and interaction policy.
struct DisplayNameFontModifier: ViewModifier {
    let fontID: Int?
    let textStyle: NSFont.TextStyle
    @State private var loadedFont: NSFont?

    private struct FontRequest: Equatable {
        let fontID: Int?
        let size: CGFloat
    }

    func body(content: Content) -> some View {
        let fallback = NSFont.systemFont(ofSize: NSFont.interfacePreferredFont(forTextStyle: textStyle).pointSize, weight: .semibold)
        content
            .font(Font(loadedFont ?? ProfileNameFontCache.font(id: fontID, fallback: fallback)))
            .task(id: FontRequest(fontID: fontID, size: fallback.pointSize)) {
                loadedFont = nil
                guard let definition = ProfileNameFontCache.customDefinition(for: fontID) else { return }
                loadedFont = try? await ProfileNameFontLoader.shared.font(definition, size: fallback.pointSize)
            }
    }
}

extension View {
    func displayNameFont(_ fontID: Int?, textStyle: NSFont.TextStyle) -> some View {
        modifier(DisplayNameFontModifier(fontID: fontID, textStyle: textStyle))
    }
}
