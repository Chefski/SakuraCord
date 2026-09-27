import SakuraCordModels
import SwiftUI

struct GuildOnboardingChannelsView: View {
    let model: AppModel
    let guildID: GuildID
    @Binding var search: String

    private var groups: [ChannelGroup] {
        ChannelGroup.make(from: model.browsableChannels(in: guildID).filter {
            search.isEmpty || $0.name.localizedStandardContains(search)
                || $0.category?.localizedStandardContains(search) == true
                || $0.topic?.localizedStandardContains(search) == true
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Channels", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            ForEach(groups) { group in
                let settings = model.presentedGuildChannelSettings(in: guildID)
                let following = group.categoryID.map { GuildChannelSelection.isSelected($0, settings: settings) } ?? false
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(group.name ?? "Uncategorized").font(.headline)
                        Spacer(minLength: 12)
                        if let categoryID = group.categoryID {
                            Toggle("Follow Category", isOn: Binding(
                                get: { following },
                                set: { model.setChannelSelected($0, channelID: categoryID, guildID: guildID) }
                            ))
                            .toggleStyle(.switch).controlSize(.small).fixedSize()
                            .accessibilityLabel("Follow \(group.name ?? "Category")")
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(group.channels) { channel in
                            BrowseChannelRow(model: model, channel: channel, followsCategory: following)
                            if channel.id != group.channels.last?.id { Divider().padding(.horizontal, 14) }
                        }
                    }
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.09)) }
                }
            }
            if groups.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No Channels", systemImage: "number", description: Text("There are no available channels to browse."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}

private struct BrowseChannelRow: View {
    let model: AppModel
    let channel: Channel
    let followsCategory: Bool
    @State private var hovered = false
    private var selected: Bool { model.isChannelSelected(channel) || channel.guildID.map { model.isUncustomizedMember(in: $0) } == true }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(channel.name, systemImage: ChannelIconPresentation.systemImage(
                        for: channel,
                        isHidden: channel.permissionOverwrites?.contains { $0.id == channel.guildID?.description && $0.deny & (1 << 10) != 0 } == true,
                        rulesChannelID: nil
                    ))
                    .font(.body.weight(.medium))
                    if let topic = channel.topic, !topic.isEmpty {
                        Text(topic).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if channel.kind != .voice {
                        Text("Active \((channel.lastMessageID?.createdAt ?? channel.id.createdAt).formatted(.relative(presentation: .numeric)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(followsCategory)
            if channel.kind == .text || channel.kind == .announcement {
                Button("View") { model.openCustomizationPreview(channel) }
                    .buttonStyle(.glass).controlSize(.small)
                    .accessibilityLabel("View \(channel.name)")
            } else if channel.kind == .voice {
                Button("Join") { Task { await model.joinVoice(channel) } }
                    .buttonStyle(.glass).controlSize(.small)
            } else if channel.kind == .forum {
                Button("Browse") { model.navigate(to: channel.id) }
                    .buttonStyle(.glass).controlSize(.small)
            }
            Toggle("Show \(channel.name)", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden().disabled(followsCategory)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(hovered ? Color.primary.opacity(0.045) : .clear)
        .onModalHover { hovered = $0 }
        .help(followsCategory ? "Unfollow the category to choose individual channels." : "")
    }

    private func toggle() {
        guard !followsCategory, let guildID = channel.guildID else { return }
        model.setChannelSelected(!selected, channelID: channel.id, guildID: guildID)
    }
}
