import Foundation
import SakuraCordModels

/// Gateway interaction metadata never carries option values; Discord serves
/// them, with the command's option definitions, on demand.
struct MessageInteractionDataDTO: Decodable {
    struct OptionDTO: Decodable {
        var type: Int
        var name: String
        var value: JSONValue?
        var options: [OptionDTO]?
    }

    struct CommandDTO: Decodable {
        var localizedName: String?
        var options: [ApplicationCommandIndexDecoder.OptionDTO]?

        enum CodingKeys: String, CodingKey {
            case options
            case localizedName = "name_localized"
        }
    }

    var name: String
    var options: [OptionDTO]?
    var applicationCommand: CommandDTO?

    enum CodingKeys: String, CodingKey {
        case name, options
        case applicationCommand = "application_command"
    }

    var domain: MessageInteractionData {
        MessageInteractionData(
            commandName: applicationCommand?.localizedName ?? name,
            options: Self.options(
                options ?? [], definitions: (applicationCommand?.options ?? []).map { $0.domain(idPrefix: "") }
            )
        )
    }

    private static func options(
        _ values: [OptionDTO], definitions: [ApplicationCommandOption]
    ) -> [MessageInteractionData.Option] {
        values.map { value in
            let definition = definitions.first { $0.name == value.name }
            return MessageInteractionData.Option(
                name: definition?.displayName ?? value.name,
                type: ApplicationCommandOptionType(rawValue: value.type),
                value: value.value.flatMap { displayValue($0, choices: definition?.choices ?? []) },
                options: options(value.options ?? [], definitions: definition?.options ?? [])
            )
        }
    }

    private static func displayValue(_ value: JSONValue, choices: [ApplicationCommandChoice]) -> String? {
        let choice = choices.first {
            switch $0.value {
            case let .string(choice): value == .string(choice)
            case let .integer(choice): value == .number(Double(choice))
            case let .number(choice): value == .number(choice)
            }
        }
        if let choice { return choice.displayName }
        return switch value {
        case let .string(value): value
        case let .number(value): Int64(exactly: value).map(String.init) ?? String(value)
        case let .bool(value): String(value)
        default: nil
        }
    }
}

public extension DiscordRESTProvider {
    func messageInteractionData(channelID: ChannelID, messageID: MessageID) async throws -> MessageInteractionData {
        let value: MessageInteractionDataDTO = try await request(
            "/channels/\(channelID)/messages/\(messageID)/interaction-data"
        )
        return value.domain
    }
}
