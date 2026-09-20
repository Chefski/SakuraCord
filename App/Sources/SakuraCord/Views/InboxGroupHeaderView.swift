import AppKit
import SakuraCordModels
import SwiftUI

nonisolated struct InboxGroupHeaderPresentation: Equatable {
    let channelID: ChannelID
    let title: String
    let subtitle: String?
    let guildName: String?
    let guildIconURL: URL?
    let systemImage: String
    let mentionCount: Int
    let isCollapsed: Bool
    let isAgeRestricted: Bool

    @MainActor
    init(_ group: InboxUnreadGroup, model: AppModel) {
        let channel = model.snapshot?.channels.first { $0.id == group.channelID }
        let thread = model.inbox.threads[group.channelID]
            ?? model.snapshot?.activeJoinedThreads.first { $0.id == group.channelID }
        let parent = thread.flatMap { thread in
            model.snapshot?.channels.first { $0.id == thread.parentID }
        }
        let guild = model.snapshot?.guilds.first { $0.id == group.guildID }
        guildName = guild?.name ?? group.subtitle
        guildIconURL = guild?.iconURL
        systemImage = group.isEvents ? "calendar" : thread != nil ? "bubble.left.and.bubble.right"
            : ChannelIconPresentation.systemImage(for: channel?.kind ?? .text, isHidden: false)
        channelID = group.channelID
        title = group.title
        subtitle = [guildName, thread != nil ? parent?.name : channel?.category]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ")
        mentionCount = group.mentionCount
        isCollapsed = group.isCollapsed
        isAgeRestricted = group.isAgeRestricted
    }
}

struct InboxGroupHeaderView: View {
    let header: InboxGroupHeaderPresentation
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.openInboxGroup(header.channelID) } label: {
                HStack(spacing: 10) {
                    if let guildName = header.guildName {
                        GuildIconView(name: guildName, iconURL: header.guildIconURL,
                                      size: 32, cornerRadius: 8, animates: false)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: header.systemImage)
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(header.title).font(.headline).lineLimit(1)
                        }
                        if let subtitle = header.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(PopoverRowButtonStyle())
            .help("Open conversation")
            if header.mentionCount > 0 {
                Text(header.mentionCount, format: .number)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(header.mentionCount == 1 ? "1 mention" : "\(header.mentionCount) mentions")
            }
            HoverActionButton(
                systemImage: "envelope.open", help: "Mark as Read"
            ) { model.markInboxGroupRead(header.channelID) }
            HoverActionButton(
                systemImage: header.isAgeRestricted ? "lock.fill" : header.isCollapsed ? "chevron.right" : "chevron.down",
                help: header.isAgeRestricted ? "Unlock \(header.title)" : header.isCollapsed ? "Expand \(header.title)" : "Collapse \(header.title)",
                iconFont: .caption.weight(.semibold)
            ) { model.toggleInboxGroup(header.channelID) }
            .disabled(model.inbox.isSavingSettings)
        }
        .contextMenu {
            Button("View All Unread") { model.openInboxGroup(header.channelID) }
            if let group = model.inbox.groups.first(where: { $0.id == header.channelID }), let guildID = group.guildID {
                Button("Mark Server as Read") { model.markInboxGuildRead(guildID) }
            }
            if let channel = model.snapshot?.channels.first(where: { $0.id == header.channelID }) {
                Menu("Notifications") {
                    ForEach([MessageNotificationLevel.inherit, .allMessages, .onlyMentions, .nothing], id: \.self) { level in
                        Button(level.menuTitle) { model.setChannelNotificationLevel(level, for: channel) }
                    }
                }
                .disabled(model.isChannelNotificationMutationPending(channel.id))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension NativeTimelineCanvasView {
    // Only supplementary headers intersecting the viewport own native controls.
    // All message content remains in the existing virtualized drawing canvas.
    func reconcileInboxHeaders() {
        reconcileInboxForumPosts()
        reconcileInboxEventViews()
        var desired: [ChannelID: (InboxGroupHeaderPresentation, CGRect)] = [:]
        if let first = rowIndex(at: max(0, visibleRect.minY)) {
            var index = first
            while items.indices.contains(index), displayedRowOrigin(at: index) < visibleRect.maxY {
                if case let .inboxGroup(header) = items[index] {
                    desired[header.channelID] = (header, CGRect(x: 0, y: displayedRowOrigin(at: index), width: bounds.width, height: 58))
                }
                index += 1
            }
        }
        for id in Array(inboxHeaderHosts.keys) where desired[id] == nil {
            inboxHeaderHosts.removeValue(forKey: id)?.removeFromSuperview()
        }
        guard let model else { return }
        for (id, value) in desired {
            let view = InboxGroupHeaderView(header: value.0, model: model)
            let host: NSHostingView<InboxGroupHeaderView>
            if let existing = inboxHeaderHosts[id] {
                host = existing
                if host.rootView.header != value.0 { host.rootView = view }
            } else {
                host = NSHostingView(rootView: view)
                inboxHeaderHosts[id] = host
                addSubview(host)
            }
            host.frame = value.1
        }
    }
}
