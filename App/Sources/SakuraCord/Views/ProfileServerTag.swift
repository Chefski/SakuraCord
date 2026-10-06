import SakuraCordModels
import SwiftUI

nonisolated enum ServerTagAppearance {
    static let height: CGFloat = 18
    static let badgeSize: CGFloat = 12
    static let fontSize: CGFloat = 11
    static let spacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 5
    static let cornerRadius: CGFloat = 5
    static let backgroundOpacity = 0.025
    static let highlightedBackgroundOpacity = 0.09
    static let outlineOpacity = 0.1
}

struct AppIdentityBadge: View {
    var isVerified = false

    var body: some View {
        HStack(spacing: ServerTagAppearance.spacing) {
            if isVerified {
                Image(systemName: "checkmark").accessibilityHidden(true)
            }
            Text("APP")
        }
        .font(.system(size: ServerTagAppearance.fontSize, weight: .bold))
        .padding(.horizontal, ServerTagAppearance.horizontalPadding)
        .frame(height: ServerTagAppearance.height)
        .foregroundStyle(.white)
        .background(
            isVerified ? Color(hex: DiscordBuiltInCommands.clydeAccent) : .indigo,
            in: .rect(cornerRadius: ServerTagAppearance.cornerRadius)
        )
        .accessibilityLabel(isVerified ? "Verified App" : "App")
    }
}

struct ProfileServerTag: View {
    let identity: PrimaryGuildIdentity?
    var showsDisclosure = false
    var isHighlighted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ServerTagAppearance.spacing) {
            if let identity, let tag = identity.tag {
                Text(tag)
                    .overlay(alignment: .leading) {
                        if let badgeURL = identity.badgeURL {
                            StaticRemoteImage(url: badgeURL, maximumPixelDimension: 32)
                                .frame(width: ServerTagAppearance.badgeSize, height: ServerTagAppearance.badgeSize)
                                .offset(x: -(ServerTagAppearance.badgeSize + ServerTagAppearance.spacing))
                        }
                    }
                    .padding(.leading, identity.badgeURL == nil ? 0 : ServerTagAppearance.badgeSize + ServerTagAppearance.spacing)
            } else {
                Text("Server Tag", bundle: #bundle).italic().foregroundStyle(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .font(.system(size: ServerTagAppearance.fontSize)).lineLimit(1)
        .padding(.horizontal, ServerTagAppearance.horizontalPadding)
        .frame(height: ServerTagAppearance.height)
        .background(
            .primary.opacity(isHighlighted ? ServerTagAppearance.highlightedBackgroundOpacity : ServerTagAppearance.backgroundOpacity),
            in: .rect(cornerRadius: ServerTagAppearance.cornerRadius)
        )
        .overlay { RoundedRectangle(cornerRadius: ServerTagAppearance.cornerRadius).strokeBorder(.primary.opacity(ServerTagAppearance.outlineOpacity)) }
        .contentShape(.rect(cornerRadius: ServerTagAppearance.cornerRadius))
    }
}
