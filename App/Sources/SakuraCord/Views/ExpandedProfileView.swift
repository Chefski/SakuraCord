import SakuraCordModels
import SwiftUI

struct ExpandedProfileView: View {
    let model: AppModel
    let initialPresentation: ProfilePresentationState
    @State private var theme = ProfileThemeState()
    @State private var selectedGame: ProfileGame?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.profileEditorModal) private var modal

    private var presentation: ProfilePresentationState {
        guard let current = model.expandedProfilePresentation,
              current.id == initialPresentation.id else { return initialPresentation }
        return current
    }

    private var themeHexes: [UInt32] {
        theme.colors(for: presentation.profile, scale: displayScale)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ProfilePresentationContent(
                    presentation: presentation,
                    layout: .expanded,
                    maximumPopoverHeight: geometry.size.height
                )
                .anchorPreference(key: ProfileFrameAnchorKey.self, value: .bounds) { bounds in
                    presentation.profile?.frame.map { ProfileFrameAnchor(frame: $0, bounds: bounds) }
                }

                widgetBoard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        HoverCloseButton(help: "Close Profile", accessibilityIdentifier: "expanded-profile-close") { modal?() }
                            .padding(10)
                    }
                    .padding(3)
            }
            .background {
                if themeHexes.count >= 2 {
                    LinearGradient(colors: themeHexes.prefix(2).map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            ConcentricRectangle(cornerRadius: 16, style: .continuous)
                                .fill(ProfilePalette.innerSurfaceOverlay(for: colorScheme))
                                .padding(3)
                        }
                }
            }
        }
        .profileEditorModalSize(width: 820, height: 720)
        .background(ProfileVerticalScrollInput())
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .containerShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded Profile")
        .task(id: theme.source(for: presentation.profile, scale: displayScale)) {
            await theme.load(theme.source(for: presentation.profile, scale: displayScale))
        }
        .profileEditorOverlay(item: $selectedGame) { game in
            ProfileGameView(model: model, game: game)
        }
    }

    @ViewBuilder
    private var widgetBoard: some View {
        if let profile = presentation.profile, let widgets = profile.widgets, !widgets.isEmpty {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    ProfileWidgetsSection(
                        displayName: profile.displayName,
                        widgets: widgets,
                        resources: profile.widgetResources,
                        animates: modal?.animationState.isVisible ?? true,
                        openGame: { selectedGame = $0 },
                        connectApplication: profile.widgetResources?.connections == nil ? nil : { configuration in
                            if let url = configuration.connectionURL {
                                _ = MessageLinkActivator.activate(url, model: model, displayedText: url.absoluteString)
                            }
                        }
                    )
                    .padding(16)
                    .padding(.top, 26)
                    .frame(width: geometry.size.width, alignment: .leading)
                }
            }
        } else if presentation.isLoading {
            ProgressView("Loading widgets…").padding(48)
        } else if let error = presentation.errorMessage {
            ContentUnavailableView {
                Label("Couldn't Load Widgets", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView("No Widgets", systemImage: "square.grid.2x2", description: Text("This person hasn't added any widgets to their profile."))
        }
    }
}

struct ExpandedProfilePresentationModifier: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content.profileEditorOverlay(item: Binding(
            get: { model.expandedProfilePresentation },
            set: { if $0 == nil { model.dismissExpandedProfile() } }
        )) { presentation in
            ExpandedProfileView(model: model, initialPresentation: presentation)
        }
    }
}
