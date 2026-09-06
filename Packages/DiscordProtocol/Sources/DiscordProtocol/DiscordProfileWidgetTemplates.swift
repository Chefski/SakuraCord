import SakuraCordModels

/// Fixed illustration subjects from official stable607562 module788259.
/// These only illustrate empty widget templates; selectable games always come
/// from the live suggestions/autocomplete endpoints.
public enum DiscordProfileWidgetTemplates {
    public static let gameKinds: [ProfileGameWidgetKind] = [.favorite, .liked, .rotation, .wanted]

    public static func artworkGameIDs(for kind: ProfileGameWidgetKind) -> [String] {
        switch kind {
        case .favorite: ["1402418696126992445"]
        case .rotation: ["700136079562375258"]
        case .liked: ["1384276457596911676", "1402692356343599254", "1344368447928401961", "1137125502985961543"]
        case .wanted: ["1314395942253756416", "356875762940379136", "1402418594532298837", "1413176957381771337"]
        }
    }
}
