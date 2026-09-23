import Observation
import SakuraCordModels
import SwiftUI

/// Keeps rail observation out of the workspace root. Timeline, member-list,
/// composer, and loading publications can invalidate `ChatRootView` without
/// rebuilding or comparing every server row.
struct ServerRailContainer: View {
    let model: AppModel

    var body: some View {
        ServerRailView(
            items: model.serverRailPresentation.items,
            directMessages: model.serverRailPresentation.directMessages,
            home: model.serverRailPresentation.home,
            selectHome: { model.selectGuild(nil) },
            selectDirectMessage: { model.navigate(to: $0) },
            selectGuild: model.selectGuild,
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
                }
            )
        )
    }
}

struct ServerRailView: View {
    let items: [ServerRailPresentationItem]
    let directMessages: [ServerRailDirectMessageEntry]
    let home: ServerRailHomeEntry
    let selectHome: () -> Void
    let selectDirectMessage: (ChannelID) -> Void
    let selectGuild: (GuildID?) -> Void
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

                ForEach(directMessages) { entry in
                    DirectMessageRailButton(entry: entry) {
                        selectDirectMessage(entry.id)
                    }
                }

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

private struct DirectMessageRailButton: View {
    let entry: ServerRailDirectMessageEntry
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let channel = entry.channel
        let displayName = channel.name.isEmpty ? "Group Direct Message" : channel.name

        HStack(spacing: 5) {
            ServerRailSelectionIndicator(
                isSelected: entry.isSelected,
                isHovering: isHovering,
                hasNotification: true
            )
            Button(action: action) {
                ServerRailBadgedIcon(mentionCount: channel.mentionCount) {
                    DirectMessageAvatar(
                        channel: channel,
                        size: 44,
                        status: nil,
                        animates: isHovering
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayName)
            .accessibilityValue(
                channel.mentionCount > 0
                    ? "\(channel.mentionCount) unread mentions"
                    : "Unread"
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

struct ServerRailBadgedIcon<Icon: View>: View {
    let mentionCount: Int
    let icon: Icon

    init(mentionCount: Int, @ViewBuilder icon: () -> Icon) {
        self.mentionCount = mentionCount
        self.icon = icon()
    }

    var body: some View {
        if mentionCount > 0 {
            icon
                .overlay(alignment: .bottomTrailing) {
                    badge
                        .padding(2)
                        .background(.black, in: Capsule())
                        .offset(x: 6, y: 6)
                        .blendMode(.destinationOut)
                        .accessibilityHidden(true)
                }
                .compositingGroup()
                .overlay(alignment: .bottomTrailing) {
                    badge.offset(x: 4, y: 4)
                }
        } else {
            icon
        }
    }

    private var badge: some View {
        Text(mentionCount, format: .number)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color(hex: 0xF23F43), in: Capsule())
    }
}

struct ServerRailContextMenuActions {
    let markRead: (GuildID) -> Void
    let mute: (Guild, ChannelMuteDuration) -> Void
    let unmute: (Guild) -> Void
    let setNotificationLevel: (Guild, MessageNotificationLevel) -> Void
    let setNotificationToggle: (Guild, GuildNotificationToggle, Bool) -> Void
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
                ServerRailBadgedIcon(mentionCount: guild.mentionCount) {
                    GuildIconView(
                        name: displayName,
                        iconURL: guild.iconURL,
                        size: 44,
                        cornerRadius: 14,
                        animates: isHovering
                    )
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
                    }
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
                hasNotification: false
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Direct Messages")
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
