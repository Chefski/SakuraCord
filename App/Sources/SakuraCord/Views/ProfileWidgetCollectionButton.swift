import SakuraCordModels
import SwiftUI

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
            HStack(spacing: 8) {
                Text(isGameCollection ? "Game Collection" : "Widgets", bundle: #bundle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                ForEach(Array(gameIDs.prefix(3)), id: \.self) { id in
                    let game = resources?.games.first { $0.id == id }
                    ProfileWidgetImageView(url: game?.iconURL ?? game?.coverURL, animates: false, contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(.rect(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                if gameIDs.count > 3 {
                    Text("+\(gameIDs.count - 3)").font(.system(size: 11, weight: .semibold))
                } else if gameIDs.isEmpty {
                    Text("\(widgets.count)").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(.primary.opacity(0.06), in: ConcentricRectangle(cornerRadius: 10))
            .contentShape(ConcentricRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("View Full Profile")
        .accessibilityLabel("View Full Profile, \(widgets.count) widgets")
    }
}
