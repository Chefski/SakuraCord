import SakuraCordModels
import SwiftUI

struct ProfileApplicationWidgetCard: View {
    let configuration: ProfileApplicationWidget
    let identity: ProfileWidgetApplicationIdentity?
    var animates = true
    var compact = false
    var openProfile: (() -> Void)?
    var connection: ProfileWidgetConnection?
    var connect: (() -> Void)?
    @State private var isSubtitleHovered = false

    var body: some View {
        if compact, let surface = configuration.surfaces["mini_profile"], let openProfile {
            compactCard(surface, open: openProfile)
        } else { fullCard }
    }

    private func compactCard(_ surface: ProfileWidgetSurface, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            ZStack(alignment: .trailing) {
                let contained = surface.layout == "mini_profile_contained_stat"
                ProfileConfiguredWidgetImage(field: surface.components[contained ? "contained_image" : "hero_image"]?["image"], data: identity?.data ?? [:], animates: animates)
                    .frame(width: contained ? 64 : 110, height: contained ? 64 : 88)
                    .mask {
                        if contained { Rectangle() } else {
                            LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                    .padding(.trailing, contained ? 10 : 0)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        ProfileWidgetImageView(url: configuration.applicationIconURL, animates: animates).frame(width: 16, height: 16)
                        Text(configuration.applicationName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        ProfileConfiguredWidgetText(component: surface.components["stat"], data: identity?.data ?? [:], required: true)
                            .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("View All Stats", bundle: #bundle)
                            .underline(isSubtitleHovered)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .onModalHover { isSubtitleHovered = $0 }
                    }
                }
                .padding(10).padding(.trailing, contained ? 74 : 46)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 88)
            .modifier(CompactProfileWidgetHover())
            .clipShape(ConcentricRectangle(cornerRadius: 10))
            .contentShape(ConcentricRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("View Full Profile")
        .accessibilityLabel("View Full Profile, \(configuration.applicationName)")
    }

    private var fullCard: some View {
        VStack(spacing: 0) {
            if let surface = configuration.surfaces["widget_top"] {
                ProfileApplicationWidgetHero(configuration: configuration, surface: surface, data: identity?.data ?? [:], animates: animates)
            }
            if let surface = configuration.surfaces["widget_bottom"] {
                Divider()
                ProfileApplicationWidgetDetails(surface: surface, data: identity?.data ?? [:], animates: animates)
            }
            if let connection, let connect {
                ProfileWidgetConnectionFooter(connection: connection, hasData: identity != nil,
                                              canConnect: configuration.connectionURL != nil, connect: connect)
            }
        }
        .background(.primary.opacity(0.035), in: ConcentricRectangle(cornerRadius: 16))
        .clipShape(ConcentricRectangle(cornerRadius: 16))
    }
}

private struct ProfileWidgetConnectionFooter: View {
    let connection: ProfileWidgetConnection
    let hasData: Bool
    let canConnect: Bool
    let connect: () -> Void

    private var needsConnection: Bool {
        connection == .unlinked || connection == .linked(sharesProfileData: false)
    }

    var body: some View {
        if needsConnection, canConnect {
            let reconnect = connection != .unlinked
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reconnect ? "Reconnect your account to get your stats" : "Link your account to get your stats", bundle: #bundle)
                        .font(.system(size: 14, weight: .medium))
                    Text(reconnect
                         ? "The widget won’t appear on your profile until you reconnect your account"
                         : "This widget won’t appear on your profile until you connect your account", bundle: #bundle)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(reconnect ? "Reconnect" : "Connect", action: connect)
            }
            .padding(12)
            .background(.primary.opacity(0.04))
        } else if !hasData {
            Label("Your game stats are still syncing. Keep playing!", systemImage: "clock")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProfileApplicationWidgetHero: View {
    let configuration: ProfileApplicationWidget
    let surface: ProfileWidgetSurface
    let data: [String: ProfileWidgetValue]
    let animates: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 5) {
                    ProfileWidgetImageView(url: configuration.applicationIconURL, animates: animates).frame(width: 16, height: 16)
                    Text(configuration.applicationName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ProfileConfiguredWidgetText(component: surface.components["title"], data: data, required: true)
                        .font(.system(size: 18, weight: .medium))
                    ForEach(["subtitle_1", "subtitle_2", "subtitle_3"], id: \.self) { key in
                        ProfileConfiguredWidgetText(component: surface.components[key], data: data)
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            if surface.layout == "widget_top_hero" || surface.layout == "widget_top_contained" {
                Color.clear
                    .overlay {
                        let contained = surface.layout == "widget_top_contained"
                        ProfileConfiguredWidgetImage(field: surface.components[contained ? "contained_image" : "hero_image"]?["image"], data: data, animates: animates)
                            .padding(contained ? 16 : 0)
                            .mask {
                                if contained {
                                    Color.black
                                } else {
                                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.32)], startPoint: .leading, endPoint: .trailing)
                                }
                            }
                    }
                    .clipped()
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .frame(minHeight: 152, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProfileApplicationWidgetDetails: View {
    let surface: ProfileWidgetSurface
    let data: [String: ProfileWidgetValue]
    let animates: Bool

    var body: some View {
        Group {
            switch surface.layout {
            case "widget_bottom_progress":
                ProfileWidgetProgressDetails(surface: surface, data: data, animates: animates)
            case "widget_bottom_stats":
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(0 ..< 2) { row in
                        GridRow {
                            ForEach(0 ..< 3) { column in
                                ProfileWidgetStatistic(component: surface.components["stat_\(row * 3 + column + 1)"], data: data)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            case "widget_bottom_collection":
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(1 ..< 5) { index in
                        let fields = surface.components["item_\(index)"]
                        HStack(spacing: 12) {
                            ProfileConfiguredWidgetImage(field: fields?["image"], data: data, animates: animates).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                ProfileConfiguredWidgetValue(field: fields?["name"], data: data).font(.system(size: 14, weight: .medium))
                                ProfileConfiguredWidgetValue(field: fields?["description"], data: data).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            default: EmptyView()
            }
        }
        .padding(16)
    }
}

private struct ProfileWidgetProgressDetails: View {
    let surface: ProfileWidgetSurface
    let data: [String: ProfileWidgetValue]
    let animates: Bool

    var current: Double? { surface.components["progress"]?["current"]?.resolve(data: data)?.number }
    var maximum: Double? { surface.components["progress"]?["max"]?.resolve(data: data)?.number }

    private var percentage: Double {
        guard let current else { return 0 }
        let fraction: Double
        if let maximum { fraction = maximum == 0 ? 0 : current / maximum } else { fraction = current }
        return fraction.isNaN ? 0 : min(max((fraction * 100).rounded(), 0), 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileConfiguredWidgetImage(field: surface.components["objective"]?["image"], data: data, animates: animates)
                .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: percentage, total: 100)
                    .tint(.primary)
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        ProfileConfiguredWidgetValue(field: surface.components["objective"]?["name"], data: data)
                            .font(.system(size: 14, weight: .medium))
                        ProfileConfiguredWidgetValue(field: surface.components["objective"]?["description"], data: data)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let current {
                        Text(maximum.map { "\(current.formatted())/\($0.formatted())" }
                             ?? "\(Int(percentage))%")
                            .font(.system(size: 14, weight: .medium)).lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct ProfileWidgetStatistic: View {
    let component: [String: ProfileWidgetConfiguredField]?
    let data: [String: ProfileWidgetValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ProfileConfiguredWidgetValue(field: component?["value"], data: data).font(.system(size: 14, weight: .medium))
                if component?["icon"]?.resolve(data: data) != nil {
                    ProfileConfiguredWidgetImage(field: component?["icon"], data: data, animates: true).frame(width: 16, height: 16)
                }
            }
            if component?["label"] != nil {
                ProfileConfiguredWidgetValue(field: component?["label"], data: data).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
    }
}

private struct ProfileConfiguredWidgetText: View {
    let component: [String: ProfileWidgetConfiguredField]?
    let data: [String: ProfileWidgetValue]
    var required = false

    var body: some View {
        if component != nil || required {
            HStack(spacing: 4) {
                if let label = component?["label"]?.resolve(data: data)?.text, !label.isEmpty { Text(label + ":") }
                ProfileConfiguredWidgetValue(field: component?["text"], data: data)
                if component?["icon"]?.resolve(data: data) != nil {
                    ProfileConfiguredWidgetImage(field: component?["icon"], data: data, animates: true).frame(width: 18, height: 18)
                }
            }
            .lineLimit(2)
        }
    }
}

private struct ProfileConfiguredWidgetValue: View {
    let field: ProfileWidgetConfiguredField?
    let data: [String: ProfileWidgetValue]

    var body: some View {
        if let value = field?.resolve(data: data) {
            switch value {
            case let .text(text): Text(text)
            case let .number(number):
                if field?.presentation == "duration" {
                    Text(Duration.milliseconds(number.isFinite ? max(0, floor(number)) : 0).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                } else { Text(number.formatted()) }
            case .image: EmptyView()
            }
        } else {
            RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.08)).frame(width: 70, height: 12).accessibilityLabel("Not available")
        }
    }
}

private struct ProfileConfiguredWidgetImage: View {
    let field: ProfileWidgetConfiguredField?
    let data: [String: ProfileWidgetValue]
    let animates: Bool

    var body: some View {
        if case let .image(url, _, _) = field?.resolve(data: data) {
            ProfileWidgetImageView(url: url, animates: animates, contentMode: .fill)
        } else { Rectangle().fill(.primary.opacity(0.06)).accessibilityHidden(true) }
    }
}

private extension ProfileWidgetValue {
    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var text: String? {
        switch self {
        case let .text(value): value
        case let .number(value): value.formatted()
        case .image: nil
        }
    }
}
