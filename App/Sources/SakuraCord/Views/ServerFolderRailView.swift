import SakuraCordModels
import SwiftUI

struct ServerFolderRailView: View {
    let entry: ServerRailFolderEntry
    let selectGuild: (GuildID?) -> Void
    let contextMenuActions: ServerRailContextMenuActions
    let expansionChanged: () -> Void

    @AppStorage private var isExpanded: Bool
    @Environment(ServerRailDragController.self) private var drag

    init(
        entry: ServerRailFolderEntry,
        selectGuild: @escaping (GuildID?) -> Void,
        contextMenuActions: ServerRailContextMenuActions,
        expansionChanged: @escaping () -> Void
    ) {
        self.entry = entry
        self.selectGuild = selectGuild
        self.contextMenuActions = contextMenuActions
        self.expansionChanged = expansionChanged
        _isExpanded = AppStorage(
            wrappedValue: false,
            Self.expansionKey(entry.folder.id)
        )
    }

    static func expansionKey(_ folderID: Int64) -> String {
        "GuildFolders.\(folderID).isExpanded"
    }

    var body: some View {
        VStack(spacing: InterfaceScale.metric(8)) {
            ServerFolderRailHeader(
                entry: entry,
                isExpanded: isExpanded,
                contextMenuActions: contextMenuActions
            ) {
                guard !drag.swallowsClick else { return }
                withAnimation(ServerRailAnimations.folderExpansion) {
                    isExpanded.toggle()
                    expansionChanged()
                }
            }
            .modifier(ServerRailDraggableRow(id: entry.id, isExpandedFolder: isExpanded))

            if isExpanded {
                ExpandedFolderGuilds(
                    folderID: entry.folder.id,
                    guildEntries: entry.guildEntries,
                    selectGuild: selectGuild,
                    contextMenuActions: contextMenuActions
                )
                .transition(.offset(y: -InterfaceScale.metric(10)).combined(with: .opacity))
            }
        }
        .padding(.vertical, isExpanded ? InterfaceScale.metric(5) : 0)
        .background {
            if isExpanded {
                ConcentricRectangle(cornerRadius: InterfaceScale.metric(18), style: .continuous)
                    .fill(Color(hex: entry.folder.colorHex ?? ServerFolderSettingsView.defaultColor).opacity(0.12))
                    .padding(.horizontal, InterfaceScale.metric(7))
                    .transition(.opacity)
            }
        }
    }
}

/// A folder's button. It is also drawn on its own while the folder is dragged.
struct ServerFolderRailHeader: View {
    let entry: ServerRailFolderEntry
    let isExpanded: Bool
    let contextMenuActions: ServerRailContextMenuActions
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: InterfaceScale.metric(5)) {
            ServerRailSelectionIndicator(
                isSelected: entry.containsSelectedGuild,
                isHovering: isHovering,
                hasNotification: showsUnreadIndicators && entry.hasUnreadGuild
            )
            Button(action: toggle) {
                ServerRailBadgedIcon(
                    mentionCount: showsUnreadIndicators ? entry.mentionCount : 0
                ) {
                    Group {
                        if isExpanded {
                            Image(systemName: "folder.fill")
                                .font(.interfaceSystem(size: 21, weight: .semibold))
                                .foregroundStyle(folderColor)
                                .frame(width: InterfaceScale.metric(44), height: InterfaceScale.metric(44))
                        } else {
                            collapsedPreview
                        }
                    }
                    .background(folderColor.opacity(isExpanded ? 0.18 : 0.12))
                    .clipShape(ConcentricRectangle(cornerRadius: InterfaceScale.metric(14), style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .overlay {
                ServerFolderContextMenuBridge(
                    isUnread: entry.hasUnreadGuild || entry.mentionCount > 0,
                    markRead: { contextMenuActions.markFolderRead(entry.guildEntries.map(\.id)) },
                    openSettings: { contextMenuActions.openFolderSettings(entry.folder) }
                )
            }
            .accessibilityLabel(displayName)
            .accessibilityValue(
                "\(isExpanded ? "Expanded" : "Collapsed")"
                    + (showsUnreadIndicators && entry.mentionCount > 0
                        ? ", \(entry.mentionCount) unread mentions" : "")
                    + (showsUnreadIndicators && entry.mentionCount == 0
                        && entry.hasUnreadGuild ? ", Unread" : "")
            )
            .accessibilityHint("Toggles the server folder")
            .help(displayName)
        }
        .frame(width: ChatChromeMetrics.serverRailWidth, height: InterfaceScale.metric(46), alignment: .leading)
        .contentShape(Rectangle())
        .anchorPreference(key: ServerRailHoverPreferenceKey.self, value: .bounds) { bounds in
            isHovering ? ServerRailHoverItem(name: displayName, bounds: bounds) : nil
        }
        .onModalHover { isHovering = $0 }
        .animation(.snappy(duration: 0.18), value: isHovering)
    }

    private var collapsedPreview: some View {
        let preview = entry.previewGuilds
        return VStack(spacing: InterfaceScale.metric(2)) {
            HStack(spacing: InterfaceScale.metric(2)) {
                previewIcon(preview[safe: 0])
                previewIcon(preview[safe: 1])
            }
            HStack(spacing: InterfaceScale.metric(2)) {
                previewIcon(preview[safe: 2])
                previewIcon(preview[safe: 3])
            }
        }
        .frame(width: InterfaceScale.metric(44), height: InterfaceScale.metric(44))
    }

    @ViewBuilder
    private func previewIcon(_ guild: Guild?) -> some View {
        if let guild {
            GuildIconView(
                name: guild.name,
                iconURL: guild.iconURL,
                size: InterfaceScale.metric(18),
                cornerRadius: InterfaceScale.metric(5),
                animates: false
            )
        } else {
            Color.clear.frame(width: InterfaceScale.metric(18), height: InterfaceScale.metric(18))
        }
    }

    private var displayName: String {
        guard let name = entry.folder.name, !name.isEmpty else { return "Server Folder" }
        return name
    }

    private var showsUnreadIndicators: Bool {
        !isExpanded
    }

    private var folderColor: Color {
        Color(hex: entry.folder.colorHex ?? ServerFolderSettingsView.defaultColor)
    }
}

private struct ExpandedFolderGuilds: View {
    let folderID: Int64
    let guildEntries: [ServerRailGuildEntry]
    let selectGuild: (GuildID?) -> Void
    let contextMenuActions: ServerRailContextMenuActions

    var body: some View {
        VStack(spacing: InterfaceScale.metric(8)) {
            ForEach(guildEntries) { entry in
                ServerRailGuildItemView(
                    entry: entry,
                    selectGuild: selectGuild,
                    contextMenuActions: contextMenuActions
                )
                .modifier(ServerRailDraggableRow(id: .guild(entry.id), folderID: folderID))
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
