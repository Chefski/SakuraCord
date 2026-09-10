import SakuraCordModels
import SwiftUI

struct ProfileServerTag: View {
    let identity: PrimaryGuildIdentity?
    var showsDisclosure = false
    var isHighlighted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let identity, let tag = identity.tag {
                Text(tag)
                    .overlay(alignment: .leading) {
                        if let badgeURL = identity.badgeURL {
                            StaticRemoteImage(url: badgeURL, maximumPixelDimension: 32)
                                .frame(width: 16, height: 16)
                                .offset(x: -22)
                        }
                    }
                    .padding(.leading, identity.badgeURL == nil ? 0 : 22)
            } else {
                Text("Server Tag", bundle: #bundle).italic().foregroundStyle(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .font(.callout).lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.primary.opacity(isHighlighted ? 0.09 : 0.025), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)) }
        .contentShape(.rect(cornerRadius: 8))
    }
}
