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
    var alwaysExpanded = false
    var update: (([String]) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Namespace private var tagCoordinateSpace
    @State private var addButtonFrame: CGRect = .zero
    @State private var pickerAnchorFrame: CGRect = .zero
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
            ForEach(Array(visibleTags.prefix(alwaysExpanded || expanded ? visibleTags.count : collapsedCount))) { tag in
                chip(tag)
            }
            if !alwaysExpanded, collapsedCount < visibleTags.count {
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
                Button {
                    pickerAnchorFrame = addButtonFrame
                    showsPicker = true
                } label: { Label("Add tags", systemImage: "plus") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .onGeometryChange(for: CGRect.self) { [tagCoordinateSpace] in $0.frame(in: .named(tagCoordinateSpace)) } action: { addButtonFrame = $0 }
            }
        }
        .coordinateSpace(name: tagCoordinateSpace)
        .overlay(alignment: .topLeading) {
            // Keep the presentation source independent of the reflowing Add Tags
            // button. Capture its position once for each opening.
            StableAnchoredPopoverPresenter(isPresented: showsPicker, configuration: .toolbarPanel,
                                           onDismiss: { showsPicker = false }, content: {
                ProfileWidgetGameTagPicker(tags: tags) { update?($0) }
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.locale, locale)
            })
            .frame(width: pickerAnchorFrame.width, height: pickerAnchorFrame.height)
            .offset(x: pickerAnchorFrame.minX, y: pickerAnchorFrame.minY)
        }
        .onChange(of: update != nil) { _, editable in if !editable { showsPicker = false } }
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
        ProfileWidgetGameTagChip(tag: tag, remove: update.map { update in
            { update(tags.filter { $0 != tag.rawValue }) }
        })
    }
}

private struct ProfileWidgetGameTagChip: View {
    let tag: ProfileWidgetGameTag
    let remove: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Group {
            if let remove {
                Button(action: remove) { label }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove \(String(localized: tag.label)) tag"))
                    .help("Remove tag")
            } else { label }
        }
        .background(.primary.opacity(remove != nil && isEnabled && isHovered ? 0.14 : 0.07), in: .rect(cornerRadius: 4))
        .onModalHover { isHovered = $0 }
    }

    private var label: some View {
        HStack(spacing: 4) {
            Label { Text(tag.label) } icon: { Image(systemName: tag.icon) }
            if remove != nil { Image(systemName: "xmark") }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .contentShape(.rect(cornerRadius: 4))
    }
}

private struct ProfileWidgetGameTagPicker: View {
    let tags: [String]
    let update: ([String]) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0 ..< 3) { group in
                    if group > 0 { Divider().padding(.horizontal, 8).padding(.vertical, 4) }
                    Text(group == 0 ? "Skill level" : group == 1 ? "Rating" : "Looking for")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 8)
                    if group == 0 {
                        ProfileWidgetTagOption(label: "None", selected: !tags.contains { ProfileWidgetGameTag(rawValue: $0)?.group == 0 }) {
                            setTags(tags.filter { ProfileWidgetGameTag(rawValue: $0)?.group != 0 })
                        }
                    }
                    ForEach(ProfileWidgetGameTag.allCases.filter { $0.group == group }) { tag in
                        ProfileWidgetTagOption(label: tag.label, selected: tags.contains(tag.rawValue)) {
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
            .padding(4)
        }
        .scrollIndicators(.visible)
        .frame(width: 264, height: 360)
    }

    private func setTags(_ value: [String]) {
        update(value)
    }
}

private struct ProfileWidgetTagOption: View {
    let label: LocalizedStringResource
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.body.bold()) }
            }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowButtonStyle(isSelected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
