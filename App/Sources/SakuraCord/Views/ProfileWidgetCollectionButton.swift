import SakuraCordModels
import SwiftUI

struct CompactProfileWidgets: View {
    let widgets: [ProfileWidget]
    let resources: ProfileWidgetResources?
    let animates: Bool
    let open: () -> Void

    private func hasMiniProfile(_ widget: ProfileWidget) -> Bool {
        guard case let .application(id) = widget.content else { return false }
        return resources?.applications.contains {
            $0.applicationID == id && $0.isPublished && $0.surfaces["mini_profile"] != nil
        } == true
    }

    var body: some View {
        VStack(spacing: InterfaceScale.metric(8)) {
            ForEach(widgets.filter(hasMiniProfile)) { widget in
                ProfileWidgetCard(widget: widget, resources: resources, animates: animates, compact: true, openProfile: open)
            }
            let remaining = widgets.filter { !hasMiniProfile($0) }
            if !remaining.isEmpty {
                ProfileWidgetCollectionButton(widgets: remaining, resources: resources, open: open)
            }
        }
    }
}

/// A fixed-height entry point keeps even the largest widget board out of the popover.
struct ProfileWidgetCollectionButton: View {
    let widgets: [ProfileWidget]
    let resources: ProfileWidgetResources?
    let open: () -> Void

    private var gameIDs: [String] {
        var seen: Set<String> = []
        return widgets.flatMap { widget -> [String] in
            guard case let .games(_, games) = widget.content else { return [] }
            return games.map(\.id)
        }.filter { seen.insert($0).inserted }
    }

    private var isGameCollection: Bool {
        widgets.allSatisfy { if case .games = $0.content { return true }; return false }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: InterfaceScale.metric(8)) {
                Text(isGameCollection ? "Game Collection" : "Widgets", bundle: #bundle)
                    .font(.interfaceSystem(size: 13, weight: .semibold))
                Spacer(minLength: InterfaceScale.metric(4))
                ForEach(Array(gameIDs.prefix(3)), id: \.self) { id in
                    let game = resources?.games.first { $0.id == id }
                    ProfileWidgetImageView(url: game?.iconURL ?? game?.coverURL, animates: false, contentMode: .fill)
                        .frame(width: InterfaceScale.metric(26), height: InterfaceScale.metric(26))
                        .clipShape(.rect(cornerRadius: InterfaceScale.metric(6)))
                        .accessibilityHidden(true)
                }
                if gameIDs.count > 3 {
                    Text("+\(gameIDs.count - 3)").font(.interfaceSystem(size: 11, weight: .semibold))
                } else if gameIDs.isEmpty {
                    Text("\(widgets.count)").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.interfaceSystem(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, InterfaceScale.metric(10))
            .frame(height: InterfaceScale.metric(44))
            .modifier(CompactProfileWidgetHover(backgroundOpacity: 0.06))
            .contentShape(ConcentricRectangle(cornerRadius: InterfaceScale.metric(10)))
        }
        .buttonStyle(.plain)
        .help("View Full Profile")
        .accessibilityLabel("View Full Profile, \(widgets.count) widgets")
    }
}
