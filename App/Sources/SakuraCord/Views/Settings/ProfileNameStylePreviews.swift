import SakuraCordModels
import SwiftUI

struct ProfileNameStylePreviews: View {
    let profile: UserProfile
    let style: DisplayNameStyle
    @Binding var isDark: Bool

    private var preview: UserProfile {
        var value = profile
        value.user.displayNameStyle = style
        return value
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: profile.themeHexes.isEmpty ? [.primary.opacity(0.04), .primary.opacity(0.1)] : profile.themeHexes.map(Color.init(hex:)), startPoint: .top, endPoint: .bottom)
            if let banner = profile.bannerURL {
                AnimatedRemoteImage(url: banner, animates: false, contentMode: .fill)
                    .blur(radius: 2)
                    .opacity(0.15)
                    .clipped()
            }
            VStack(spacing: 0) {
                Spacer(minLength: 60)
                ProfileStylePreviewCards(profile: preview)
                Spacer(minLength: 30)
                HStack(alignment: .bottom, spacing: 12) {
                    Text("Note: Display name colours and effects will not appear in servers. Styles may also look different across Discord and light/dark mode.", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Preview appearance", selection: $isDark) {
                        Image(systemName: "moon.stars.fill").tag(true)
                        Image(systemName: "sun.max.fill").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 82)
                }
                .padding(24)
            }
        }
        .clipped()
        .environment(\.colorScheme, isDark ? .dark : .light)
    }
}

private struct ProfileStylePreviewCards: View {
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: -10) {
            MemberProfilePopover(
                member: Member(user: profile.user, roleName: "", status: profile.status),
                profile: profile, isLoading: false, errorMessage: nil,
                maximumPopoverHeight: 232, showsRoles: false, footer: EmptyView()
            )
            .allowsHitTesting(false)
            .clipShape(ConcentricRectangle(cornerRadius: 8))
            .scaleEffect(300.0 / 330, anchor: .topLeading)
            .frame(width: 300, height: 211, alignment: .topLeading)

            HStack(alignment: .top, spacing: 12) {
                DecoratedAvatarView(name: profile.displayName, avatarURL: profile.avatarURL,
                                    decorationURL: profile.user.avatarDecorationURL, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        ProfileDisplayName(name: profile.displayName, style: profile.user.displayNameStyle, size: 14)
                        Text("03:30").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("does anyone read this?", bundle: #bundle).font(.body)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 318, height: 84)
            .background(.background, in: ConcentricRectangle(cornerRadius: 8))
            .overlay { ConcentricRectangle(cornerRadius: 8).stroke(.primary.opacity(0.15)) }
            .offset(x: 24)

            ProfileMemberNameplateRow(profile: profile)
                .frame(width: 280, height: 42)
        }
        .frame(width: 342, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display name style previews")
    }
}

struct ProfileMemberNameplateRow: View {
    let profile: UserProfile

    var body: some View {
        MemberRow(member: Member(user: profile.user, roleName: "", status: profile.status), isSelected: false) {}
    }
}
