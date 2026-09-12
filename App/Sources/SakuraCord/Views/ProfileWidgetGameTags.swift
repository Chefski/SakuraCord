import SwiftUI

/// The editor exposes the current tag groups while preserving unrecognized wire tags.
private enum ProfileWidgetGameTag: String, CaseIterable, Identifiable {
    case casual, intermediate, expert, betterThanYou = "better_than_you"
    case obsessed, loveIt = "love_it", kindOfLoveIt = "kind_of_love_it", kindOfHateIt = "kind_of_hate_it", rageQuitting = "rage_quitting"
    case lookingForGroup = "looking_for_group", openToPlay = "open_to_play", lookingForTips = "looking_for_tips", openToTeach = "open_to_teach", lookingToDiscuss = "looking_to_discuss"

    var id: String { rawValue }
    var label: LocalizedStringResource {
        switch self {
        case .casual: "Casual"
        case .intermediate: "Intermediate"
        case .expert: "Expert"
        case .betterThanYou: "Better than you"
        case .obsessed: "Obsessed"
        case .loveIt: "Love it"
        case .kindOfLoveIt: "Kind of love it"
        case .kindOfHateIt: "Kind of hate it"
        case .rageQuitting: "Rage quitting"
        case .lookingForGroup: "Looking for group"
        case .openToPlay: "Open to play"
        case .lookingForTips: "Looking for tips"
        case .openToTeach: "Open to teach"
        case .lookingToDiscuss: "Looking to discuss"
        }
    }
    var group: Int {
        switch self {
        case .casual, .intermediate, .expert, .betterThanYou: 0
        case .obsessed, .loveIt, .kindOfLoveIt, .kindOfHateIt, .rageQuitting: 1
        default: 2
        }
    }
    var icon: String {
        switch group {
        case 0: "rosette"
        case 1: self == .kindOfHateIt || self == .rageQuitting ? "hand.thumbsdown.fill" : "hand.thumbsup.fill"
        default: "person.2.fill"
        }
    }
}

struct ProfileWidgetGameTags: View {
    let tags: [String]
    var update: (([String]) -> Void)?
    @State private var showsPicker = false
    @State private var expanded = false
    @State private var availableWidth: CGFloat = 296
    @State private var tagWidths: [String: CGFloat] = [:]
    @State private var addWidth: CGFloat = 0
    @State private var overflowWidth: CGFloat = 24

    private var visibleTags: [ProfileWidgetGameTag] { tags.compactMap(ProfileWidgetGameTag.init(rawValue:)) }
    private var canAdd: Bool { update != nil && visibleTags.count < 20 }

    private var collapsedCount: Int {
        guard visibleTags.allSatisfy({ tagWidths[$0.rawValue] != nil }) else { return visibleTags.count }
        var count = 0
        var width: CGFloat = 0
        for tag in visibleTags {
            width += (tagWidths[tag.rawValue] ?? 0) + 4
            if width > availableWidth { break }
            count += 1
        }
        width = 0
        let reserved = overflowWidth + (canAdd ? addWidth + 8 : 4)
        for tag in visibleTags.dropFirst(count) {
            width += (tagWidths[tag.rawValue] ?? 0) + 4
            if width > availableWidth - reserved { break }
            count += 1
        }
        return count
    }

    var body: some View {
        ProfileRoleFlowLayout(spacing: 4) {
            ForEach(Array(visibleTags.prefix(expanded ? visibleTags.count : collapsedCount))) { tag in
                chip(tag)
            }
            if collapsedCount < visibleTags.count {
                Button { expanded.toggle() } label: {
                    if expanded { Image(systemName: "chevron.left").frame(minWidth: 12) } else { Text("+\(visibleTags.count - collapsedCount)") }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 4))
                .accessibilityLabel(expanded ? "Collapse tags" : "Show \(visibleTags.count - collapsedCount) more tags")
                .help(expanded ? "Collapse tags" : "Show all tags")
            }
            if canAdd {
                Button { showsPicker = true } label: { Label("Add tags", systemImage: "plus") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .windowModal(isPresented: $showsPicker, title: "Game Tags") {
                        ProfileWidgetGameTagPicker(tags: tags) { update?($0) }
                    }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = max($0, 1) }
        .background(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(visibleTags) { tag in
                    chip(tag).fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tagWidths[tag.rawValue] = $0 }
                }
                Label("Add tags", systemImage: "plus")
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { addWidth = $0 }
                Text("+\(visibleTags.count)")
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { overflowWidth = $0 }
            }
            .font(.system(size: 12, weight: .medium)).fixedSize()
            .hidden().accessibilityHidden(true).allowsHitTesting(false)
        }
    }

    private func chip(_ tag: ProfileWidgetGameTag) -> some View {
        HStack(spacing: 4) {
            Label { Text(tag.label) } icon: { Image(systemName: tag.icon) }
            if let update {
                Button { update(tags.filter { $0 != tag.rawValue }) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(Text("Remove \(String(localized: tag.label)) tag"))
                    .help("Remove tag")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 4))
    }
}

private struct ProfileWidgetGameTagPicker: View {
    @State private var tags: [String]
    let update: ([String]) -> Void

    init(tags: [String], update: @escaping ([String]) -> Void) {
        _tags = State(initialValue: tags)
        self.update = update
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0 ..< 3) { group in
                if group > 0 { Divider().padding(.vertical, 4) }
                Text(group == 0 ? "Skill level" : group == 1 ? "Rating" : "Looking for")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 8)
                if group == 0 {
                    ProfileWidgetTagOption(label: "None", radio: true, selected: !tags.contains { ProfileWidgetGameTag(rawValue: $0)?.group == 0 }) {
                        setTags(tags.filter { ProfileWidgetGameTag(rawValue: $0)?.group != 0 })
                    }
                }
                ForEach(ProfileWidgetGameTag.allCases.filter { $0.group == group }) { tag in
                    ProfileWidgetTagOption(label: tag.label, radio: group == 0, selected: tags.contains(tag.rawValue)) {
                        var result = tags
                        if group == 0 {
                            result.removeAll { ProfileWidgetGameTag(rawValue: $0)?.group == 0 }
                            result.append(tag.rawValue)
                        } else if result.contains(tag.rawValue) {
                            result.removeAll { $0 == tag.rawValue }
                        } else {
                            result.append(tag.rawValue)
                        }
                        setTags(result)
                    }
                }
            }
        }
        .padding(8)
        }
        .scrollIndicators(.hidden)
        .windowModalSize(width: 240, height: 568)
    }

    private func setTags(_ value: [String]) {
        tags = value
        update(value)
    }
}

private struct ProfileWidgetTagOption: View {
    let label: LocalizedStringResource
    let radio: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: radio ? (selected ? "largecircle.fill.circle" : "circle") : (selected ? "checkmark.square.fill" : "square"))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .font(.system(size: 14)).padding(.horizontal, 8).padding(.vertical, 5).contentShape(.rect)
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
