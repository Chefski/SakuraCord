import SwiftUI

struct GuildIconView: View {
    let name: String
    let iconURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    var animates = true
    var isSelected = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        name: String,
        iconURL: URL?,
        size: CGFloat,
        cornerRadius: CGFloat,
        animates: Bool = true,
        isSelected: Bool = false
    ) {
        self.name = name
        self.iconURL = iconURL
        self.size = size
        self.cornerRadius = cornerRadius
        self.animates = animates
        self.isSelected = isSelected
    }

    var body: some View {
        let displayedCornerRadius = iconURL == nil ? size * 0.25 : cornerRadius
        ZStack {
            ConcentricRectangle(cornerRadius: displayedCornerRadius, style: .continuous)
                .fill(iconURL == nil ? fallbackBackground : Color.secondary.opacity(0.16))
            if let iconURL {
                StaticRemoteImage(
                    url: iconURL,
                    maximumPixelDimension: requestedPixelDimension
                )
                if animates,
                   NativeTimelineAvatarPresentation
                    .shouldDecodeAnimation(for: iconURL)
                {
                    AnimatedRemoteImage(
                        url: iconURL,
                        maximumPixelDimension: requestedPixelDimension
                    )
                    .transition(.identity)
                }
            } else {
                Text(initials)
                    .font(.system(size: size * 0.43, weight: .medium))
                    .foregroundStyle(isSelected ? .white : fallbackForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .clipShape(ConcentricRectangle(cornerRadius: displayedCornerRadius, style: .continuous))
        .accessibilityLabel(name.isEmpty ? "Unnamed Server" : name)
    }

    private var requestedPixelDimension: Int {
        max(1, Int((size * 2).rounded(.up)))
    }

    private var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return String(words.prefix(3).compactMap(\.first))
        }
        return words.first.map { String($0.prefix(2)) } ?? "?"
    }

    private var fallbackBackground: Color {
        if isSelected { return Color(hex: 0x6D7EEE) }
        return Color.secondary.opacity(0.16)
    }

    private var fallbackForeground: Color {
        Color(hex: colorScheme == .dark ? 0xF2F2F4 : 0x3C3D42)
    }
}
