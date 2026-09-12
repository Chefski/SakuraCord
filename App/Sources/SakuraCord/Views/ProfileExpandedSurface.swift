import SakuraCordModels
import SwiftUI

/// Shared geometry and theme surface for the expanded profile and editable preview.
struct ProfileExpandedSurface<ProfileContent: View, Widgets: View>: View {
    let profile: UserProfile?
    var isPreview = false
    @ViewBuilder let profileContent: ProfileContent
    @ViewBuilder let widgets: Widgets
    @State private var theme = ProfileThemeState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ProfileExpandedColumns(profileWidth: MemberProfilePopover<EmptyView>.preferredWidth) {
            profileContent
                .anchorPreference(key: ProfileFrameAnchorKey.self, value: .bounds) { bounds in
                    profile?.frame.map { ProfileFrameAnchor(frame: $0, bounds: bounds) }
                }
            widgets
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(3)
        }
        .background {
            let colors = theme.colors(for: profile, scale: displayScale, isPreview: isPreview)
            if colors.count >= 2 {
                LinearGradient(colors: colors.prefix(2).map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        ConcentricRectangle(cornerRadius: 16, style: .continuous)
                            .fill(ProfilePalette.innerSurfaceOverlay(for: colorScheme))
                            .padding(3)
                    }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .containerShape(.rect(cornerRadius: 16))
        .task(id: theme.source(for: profile, scale: displayScale, isPreview: isPreview)) {
            await theme.load(theme.source(for: profile, scale: displayScale, isPreview: isPreview))
        }
    }
}

/// Both boards use the same scroll viewport and reserved space for their top action.
struct ProfileWidgetBoardViewport<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .padding(16)
                .padding(.top, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Propose each column's real width before measuring, then cap the shared viewport.
private struct ProfileExpandedColumns: Layout {
    let profileWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 820
        let heights = subviews.enumerated().map { index, view in
            view.sizeThatFits(ProposedViewSize(width: index == 0 ? profileWidth : max(0, width - profileWidth), height: nil)).height
        }
        return CGSize(width: width, height: proposal.height ?? min(720, heights.max() ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + (index == 0 ? 0 : profileWidth), y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: index == 0 ? profileWidth : max(0, bounds.width - profileWidth), height: bounds.height))
        }
    }
}
