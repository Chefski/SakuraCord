import Observation
import SakuraCordModels
import SwiftUI

/// Keeps rail observation out of the workspace root. Timeline, member-list,
/// composer, and loading publications can invalidate `ChatRootView` without
/// rebuilding or comparing every server row.
struct ServerRailContainer: View {
    let model: AppModel

    var body: some View {
        @Bindable var invites = model.serverInvites
        ServerRailView(
            items: model.serverRailPresentation.items,
            home: model.serverRailPresentation.home,
            selectHome: { model.selectGuild(nil) },
            selectGuild: model.selectGuild,
            joinServer: { invites.showsJoinDialog = true },
            contextMenuActions: ServerRailContextMenuActions(
                markRead: model.markGuildRead,
                mute: { guild, duration in
                    model.setGuildMute(
                        true,
                        until: duration.endDate(),
                        for: guild
                    )
                },
                unmute: { guild in
                    model.setGuildMute(false, until: nil, for: guild)
                },
                setNotificationLevel: { guild, level in
                    model.setGuildNotificationLevel(level, for: guild)
                },
                setNotificationToggle: { guild, toggle, isEnabled in
                    model.setGuildNotificationToggle(
                        toggle,
                        isEnabled: isEnabled,
                        for: guild
                    )
                },
                leaveServer: { guild in invites.leaveConfirmation = guild }
            )
        )
        .windowModal(isPresented: $invites.showsJoinDialog, cornerRadius: 32, cornerStyle: .circular,
                     isConcealed: { model.serverInvites.captcha.challenge != nil }, content: { JoinServerView(model: model) })
        .windowModal(isPresented: Binding(
            get: { model.onboarding.presentedGuildID != nil && !invites.showsJoinDialog },
            set: { if !$0 { model.onboarding.presentedGuildID = nil } }
        ), cornerRadius: 32, cornerStyle: .circular) {
            if let guildID = model.onboarding.presentedGuildID { GuildOnboardingView(model: model, guildID: guildID) }
        }
        .modifier(ServerInviteCaptchaPresentation(store: invites.captcha))
        .alert("Leave \(invites.leaveConfirmation?.name ?? "Server")?",
               isPresented: Binding(get: { invites.leaveConfirmation != nil },
                                    set: { if !$0 { invites.leaveConfirmation = nil } }),
               presenting: invites.leaveConfirmation) { guild in
            Button("Leave Server", role: .destructive) {
                model.startAccountChildTask(account: model.accountSession()) { model, _ in
                    _ = await model.leaveServer(guild)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won’t be able to rejoin this server unless you have a new or existing invite.")
        }
        .alert("Unable to Leave Server",
               isPresented: Binding(get: { invites.leaveError != nil }, set: { if !$0 { invites.leaveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(invites.leaveError ?? "")
        }
    }
}

struct ServerRailView: View {
    let items: [ServerRailPresentationItem]
    let home: ServerRailHomeEntry
    let selectHome: () -> Void
    let selectGuild: (GuildID?) -> Void
    var joinServer: () -> Void = {}
    let contextMenuActions: ServerRailContextMenuActions
    @State private var folderLayoutRevision = 0

    var body: some View {
        ScrollView {
            // Expanded folders make rail rows variable-height. Lazy layout
            // corrects its content estimate while reverse-scrolling, which
            // disrupts AppKit's elastic rebound at the top boundary.
            VStack(spacing: 10) {
                HomeRailButton(
                    home: home,
                    action: selectHome
                )

                Divider().padding(.horizontal, 12)

                ForEach(items) { item in
                    ServerRailItemView(
                        item: item,
                        selectGuild: selectGuild,
                        contextMenuActions: contextMenuActions,
                        folderExpansionChanged: {
                            folderLayoutRevision &+= 1
                        }
                    )
                }
                Button(action: joinServer) {
                    Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.green)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .help("Add a Server")
                .accessibilityLabel("Add a Server")
                .accessibilityIdentifier("add-server")
            }
            .padding(.bottom, 12)
            .animation(ServerRailAnimations.folderExpansion, value: folderLayoutRevision)
        }
        // Unlike .hidden, .never overrides macOS's always-visible scrollbar preference.
        .scrollIndicators(.never)
        .background {
            ScrollInputPerformanceProbeAttachment(surface: .serverList)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: ChatChromeMetrics.serverRailWidth)
        .overlayPreferenceValue(ServerRailHoverPreferenceKey.self) { hoverItem in
            GeometryReader { proxy in
                if let hoverItem {
                    ServerRailHoverLabel(name: hoverItem.name)
                        .offset(
                            x: ChatChromeMetrics.serverRailWidth + 7,
                            y: proxy[hoverItem.bounds].midY - 16
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .zIndex(200)
    }
}

struct ServerRailContextMenuActions {
    let markRead: (GuildID) -> Void
    let mute: (Guild, ChannelMuteDuration) -> Void
    let unmute: (Guild) -> Void
    let setNotificationLevel: (Guild, MessageNotificationLevel) -> Void
    let setNotificationToggle: (Guild, GuildNotificationToggle, Bool) -> Void
    var leaveServer: (Guild) -> Void = { _ in }
}

private struct ServerRailItemView: View {
    let item: ServerRailPresentationItem
    let selectGuild: (GuildID?) -> Void
    let contextMenuActions: ServerRailContextMenuActions
    let folderExpansionChanged: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch item {
            case .guild(let entry):
                ServerRailGuildItemView(
                    entry: entry,
                    selectGuild: selectGuild,
                    contextMenuActions: contextMenuActions
                )
            case .folder(let entry):
                ServerFolderRailView(
                    entry: entry,
                    selectGuild: selectGuild,
                    contextMenuActions: contextMenuActions,
                    expansionChanged: folderExpansionChanged
                )
            }
        }
    }
}

struct ServerRailGuildItemView: View {
    let entry: ServerRailGuildEntry
    let selectGuild: (GuildID?) -> Void
    let contextMenuActions: ServerRailContextMenuActions

    var body: some View {
        if let presentation = entry.presentation {
            GuildRailButton(
                presentation: presentation,
                isSelected: entry.isSelected,
                contextMenuActions: contextMenuActions
            ) {
                selectGuild(entry.id)
            }
        }
    }
}

enum ServerRailAnimations {
    static let folderExpansion = Animation.spring(duration: 0.38, bounce: 0.08)
}

struct GuildRailButton: View {
    let presentation: ServerRailGuildPresentation
    let isSelected: Bool
    let contextMenuActions: ServerRailContextMenuActions
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let guild = presentation.guild
        let displayName = guild.name.isEmpty ? "Unnamed Server" : guild.name

        HStack(spacing: 5) {
            ServerRailSelectionIndicator(
                isSelected: isSelected,
                isHovering: isHovering,
                hasNotification: guild.unreadCount > 0
            )
            Button(action: action) {
                GuildIconView(
                    name: displayName,
                    iconURL: guild.iconURL,
                    size: 44,
                    cornerRadius: 14,
                    animates: isHovering
                )
                    .overlay(alignment: .bottomTrailing) {
                        if guild.mentionCount > 0 {
                            Text(guild.mentionCount, format: .number)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(.red, in: Capsule())
                                .offset(x: 4, y: 4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .overlay {
                ServerContextMenuBridge(
                    isUnread: guild.unreadCount > 0,
                    isMutationPending:
                        presentation.isNotificationMutationPending,
                    notificationSettings: presentation.notificationSettings,
                    markRead: { contextMenuActions.markRead(guild.id) },
                    mute: { contextMenuActions.mute(guild, $0) },
                    unmute: { contextMenuActions.unmute(guild) },
                    setNotificationLevel: {
                        contextMenuActions.setNotificationLevel(guild, $0)
                    },
                    setNotificationToggle: { toggle, isEnabled in
                        contextMenuActions.setNotificationToggle(
                            guild,
                            toggle,
                            isEnabled
                        )
                    },
                    copyServerID: {
                        ChannelContextMenuValue.copy(guild.id.description)
                    },
                    leaveServer: guild.isOwnedByCurrentUser == false && !guild.isUnavailable
                        ? { contextMenuActions.leaveServer(guild) } : nil
                )
            }
            .accessibilityLabel(displayName)
            .accessibilityValue(
                guild.mentionCount > 0
                    ? "\(guild.mentionCount) unread mentions"
                    : (guild.unreadCount > 0 ? "Unread" : "")
            )
            .help(displayName)
        }
        .frame(width: ChatChromeMetrics.serverRailWidth, height: 46, alignment: .topLeading)
        .contentShape(Rectangle())
        .anchorPreference(key: ServerRailHoverPreferenceKey.self, value: .bounds) { bounds in
            isHovering ? ServerRailHoverItem(name: displayName, bounds: bounds) : nil
        }
        .onModalHover { isHovering = $0 }
        .animation(.snappy(duration: 0.18), value: isHovering)
    }
}

private struct ServerRailHoverLabel: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .frame(height: 32)
            .glassEffect(.regular, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ServerRailHoverItem {
    let name: String
    let bounds: Anchor<CGRect>
}

struct ServerRailHoverPreferenceKey: PreferenceKey {
    static let defaultValue: ServerRailHoverItem? = nil

    static func reduce(value: inout ServerRailHoverItem?, nextValue: () -> ServerRailHoverItem?) {
        value = nextValue() ?? value
    }
}

private struct HomeRailButton: View {
    let home: ServerRailHomeEntry
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            ServerRailSelectionIndicator(
                isSelected: home.isSelected,
                isHovering: isHovering,
                hasNotification: home.isUnread
            )
            Button(action: action) {
                Image(systemName: "message.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(
                        home.isSelected
                            ? SakuraCordAccentColor.color
                            : Color.secondary.opacity(0.16),
                        in: ConcentricRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if home.mentionCount > 0 {
                            Text(home.mentionCount, format: .number)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(.red, in: Capsule())
                                .offset(x: 4, y: 4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Direct Messages")
            .accessibilityValue(
                home.mentionCount > 0
                    ? "\(home.mentionCount) unread mentions"
                    : (home.isUnread ? "Unread" : "")
            )
        }
        .frame(width: ChatChromeMetrics.serverRailWidth, height: 46, alignment: .leading)
        .contentShape(Rectangle())
        .onModalHover { isHovering = $0 }
        .help("Direct Messages")
    }
}

struct ServerRailSelectionIndicator: View {
    let isSelected: Bool
    let isHovering: Bool
    let hasNotification: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(colorScheme == .dark ? Color.white : Color.black)
            .frame(width: 4, height: indicatorHeight)
            .opacity(indicatorHeight == 0 ? 0 : 1)
            .frame(width: 7, height: 40)
            .animation(.snappy(duration: 0.2), value: indicatorHeight)
    }

    private var indicatorHeight: CGFloat {
        if isSelected {
            return 36
        }
        if isHovering {
            return 20
        }
        if hasNotification {
            return 8
        }
        return 0
    }
}
