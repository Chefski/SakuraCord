import Foundation
import SakuraCordModels

public extension MockChatProvider {
    func componentChoices(
        kind: ComponentSelectKind,
        query: String,
        guildID: GuildID?,
        channelID _: ChannelID
    ) async throws -> [ComponentSelectOption] {
        let members = try await members(in: guildID)
        let roles = Dictionary(
            members.flatMap(\.roles).map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        ).values
        let choices: [ComponentSelectOption]
        switch kind {
        case .string:
            choices = []
        case .user:
            choices = members.map(Self.componentChoice)
        case .role:
            choices = roles.map(Self.componentChoice)
        case .mentionable:
            choices =
                members.map(Self.componentChoice)
                + roles.map(Self.componentChoice)
        case .channel:
            choices = try await channels(in: guildID).map {
                ComponentSelectOption(
                    label: "#\($0.name)",
                    value: String($0.id.rawValue),
                    imageURL: $0.iconURL,
                    imageShape: .roundedRectangle
                )
            }
        }
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return choices
            .filter {
                normalizedQuery.isEmpty
                    || $0.label.localizedCaseInsensitiveContains(
                        normalizedQuery
                    )
                    || $0.description?.localizedCaseInsensitiveContains(
                        normalizedQuery
                    ) == true
            }
            .sorted {
                let comparison = $0.label.localizedCaseInsensitiveCompare(
                    $1.label
                )
                return comparison == .orderedSame
                    ? $0.value < $1.value
                    : comparison == .orderedAscending
            }
            .prefix(25)
            .map(\.self)
    }

    private static func componentChoice(
        for member: Member
    ) -> ComponentSelectOption {
        ComponentSelectOption(
            label: member.user.displayName,
            value: String(member.id.rawValue),
            description: "@\(member.user.username)",
            imageURL: member.user.avatarURL
        )
    }

    private static func componentChoice(
        for role: GuildRole
    ) -> ComponentSelectOption {
        ComponentSelectOption(
            label: "@\(role.name)",
            value: String(role.id.rawValue),
            imageURL: role.iconURL,
            imageShape: .roundedRectangle
        )
    }
}
