import SwiftUI

/// Shared live text and imagery for the anchor, selected values and option rows.
struct SelectionFieldOptionLabel<ID: Hashable & Sendable>: View {
    let option: SelectionFieldOption<ID>
    var showsSubtitle = false

    var body: some View {
        HStack(spacing: 8) {
            SelectionFieldOptionIcon(leading: option.leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                if showsSubtitle, let subtitle = option.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .help([option.title, option.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private var titleColor: Color {
        switch option.titleStyle {
        case .standard: .primary
        case .memberColor(let hex):
            SakuraCordAccentColor.usesAccentFallback(forRoleColorHex: hex) ? .primary : SakuraCordAccentColor.color(forRoleColorHex: hex)
        case .roleColor(let hex):
            SakuraCordAccentColor.color(forRoleColorHex: hex)
        }
    }
}

private struct SelectionFieldOptionIcon: View {
    let leading: SelectionFieldLeading

    var body: some View {
        Group {
            switch leading {
            case .none:
                EmptyView()
            case .systemImage(let name):
                Image(systemName: name).foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            case .text(let text):
                Text(text).frame(width: 20, height: 20)
            case .remoteImage(let url, let fallback, let shape):
                remoteImage(url: url, fallback: fallback, circle: shape == .circle)
            case .role(let color, let iconURL, let emoji):
                if let emoji, !emoji.isEmpty {
                    Text(emoji).frame(width: 20, height: 20)
                } else if let iconURL {
                    remoteImage(url: iconURL, fallback: "", circle: false)
                } else {
                    Circle().fill(color.map { Color(hex: $0) } ?? .secondary)
                        .frame(width: 10, height: 10)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func remoteImage(url: URL?, fallback: String, circle: Bool) -> some View {
        Group {
            if let url {
                AnimatedRemoteImage(url: url, maximumPixelDimension: 64,
                                    contentMode: circle ? .fill : .fit, usesSwiftUIRendering: true)
            } else {
                ZStack {
                    Color.primary.opacity(0.08)
                    Text(String(fallback.prefix(1))).font(.system(size: 10, weight: .medium))
                }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(.rect(cornerRadius: circle ? 10 : 4))
    }
}
