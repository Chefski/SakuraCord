import SakuraCordModels
import SwiftUI

struct ForwardSelectionControl: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? SakuraCordAccentColor.color : .clear)
            Circle()
                .stroke(
                    isSelected ? SakuraCordAccentColor.color : Color.secondary,
                    lineWidth: 1.8
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.interfaceSystem(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(
            width: ForwardPickerLayoutMetrics.selectionDiameter,
            height: ForwardPickerLayoutMetrics.selectionDiameter
        )
        .accessibilityHidden(true)
    }
}

struct ForwardDestinationRow: View {
    let destination: ForwardDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: InterfaceScale.metric(12)) {
                ForwardDestinationAvatar(destination: destination)
                VStack(alignment: .leading, spacing: InterfaceScale.metric(2)) {
                    Text(destination.title)
                        .font(.interface(.body).weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let detail = destination.unavailableReason ?? destination.detail
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.interface(.caption))
                            .foregroundStyle(destination.unavailableReason == nil
                                ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                }
                Spacer()
                ForwardSelectionControl(isSelected: isSelected)
            }
            .padding(.horizontal, InterfaceScale.metric(16))
            .frame(height: ForwardPickerLayoutMetrics.rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: InterfaceScale.metric(9), style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: InterfaceScale.metric(9), style: .continuous)
                    .fill(rowBackground)
            }
        }
        .buttonStyle(.plain)
        .disabled(destination.unavailableReason != nil)
        .opacity(destination.unavailableReason == nil ? 1 : 0.62)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(destination.id.accessibilityIdentifier)
        .onModalHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        .primary.opacity(isSelected || isHovered ? 0.075 : 0.001)
    }

    private var accessibilityLabel: String {
        let detail = destination.unavailableReason ?? destination.detail
        return detail.isEmpty ? destination.title : "\(destination.title), \(detail)"
    }
}

private struct ForwardDestinationAvatar: View {
    let destination: ForwardDestination

    var body: some View {
        switch destination.kind {
        case .channel(let channel) where channel.guildID != nil:
            guildIcon(symbol: channel.kind == .voice ? "speaker.wave.2.fill" : "number")
        case .thread(_, let parent):
            guildIcon(symbol: parent?.kind == .forum ? "number" : SakuraCordSystemSymbol.thread)
        case .channel, .user:
            AvatarView(
                name: destination.title,
                url: destination.avatarURL,
                size: InterfaceScale.metric(28)
            )
        }
    }

    private func guildIcon(symbol: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if destination.guild?.iconURL != nil {
                GuildIconView(
                    name: destination.guild?.name ?? destination.title,
                    iconURL: destination.guild?.iconURL,
                    size: InterfaceScale.metric(28),
                    cornerRadius: InterfaceScale.metric(9),
                    animates: false
                )
            } else {
                ConcentricRectangle(cornerRadius: InterfaceScale.metric(9), style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: InterfaceScale.metric(28), height: InterfaceScale.metric(28))
                    .overlay {
                        Text(guildInitials)
                            .font(.interfaceSystem(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
            }
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: InterfaceScale.metric(18), height: InterfaceScale.metric(18))
                .overlay {
                    SakuraCordSystemSymbol.swiftUIImage(named: symbol)
                        .font(.interfaceSystem(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .overlay {
                    Circle().stroke(.black.opacity(0.12), lineWidth: 0.5)
                }
                .offset(x: InterfaceScale.metric(4), y: InterfaceScale.metric(4))
        }
        .frame(width: InterfaceScale.metric(34), height: InterfaceScale.metric(34))
        .accessibilityHidden(true)
    }

    private var guildInitials: String {
        let name = destination.guild?.name ?? destination.title
        let initials = name.split(whereSeparator: { $0.isWhitespace }).compactMap(\.first)
        if initials.count > 1 {
            return String(initials.prefix(3)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
