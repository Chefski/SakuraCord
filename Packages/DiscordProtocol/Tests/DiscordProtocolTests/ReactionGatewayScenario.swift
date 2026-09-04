@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Testing

struct ReactionGatewayScenario {
    var run: Void {
        get async throws {
        RateLimitURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RateLimitURLProtocol.self]
        let socket = ReadyGatewaySocket()
        await socket.push(gatewayMessage(
            op: 10, data: .object(["heartbeat_interval": .number(60_000)])
        ))
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "session_id": .string("reaction-session"),
                "resume_gateway_url": .string("wss://gateway.discord.gg"),
                "guilds": .array([]),
            ]),
            sequence: 1,
            eventName: "READY"
        ))
        let provider = DiscordRESTProvider(
            credentials: TestCredentialStore(),
            handle: CredentialHandle(accountID: "1"),
            session: URLSession(configuration: configuration),
            gatewayTransport: ReadyGatewayTransport(socket: socket)
        )
        let events = await provider.eventStream()
        _ = try await provider.bootstrap()

        let created = Task { () -> Message? in
            for await event in events {
                if case let .messageCreated(message) = event { return message }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "id": .string("300"),
                "channel_id": .string("200"),
                "guild_id": .string("100"),
                "author": .object([
                    "id": .string("2"),
                    "username": .string("maya"),
                    "global_name": .string("Maya"),
                    "avatar": .null,
                ]),
                "content": .string("react here"),
                "timestamp": .string("2026-07-26T12:00:00.000Z"),
                "attachments": .array([]),
                "reactions": .array([]),
            ]),
            sequence: 2,
            eventName: "MESSAGE_CREATE"
        ))
        #expect(await created.value?.id == MessageID(rawValue: 300))

        let add = Task { () -> MessageReactionUpdate? in
            for await event in events {
                if case let .messageReactionUpdated(update) = event { return update }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "user_id": .string("2"),
                "channel_id": .string("200"),
                "message_id": .string("300"),
                "guild_id": .string("100"),
                "emoji": .object(["id": .null, "name": .string("🔥")]),
                "type": .number(0),
                "burst": .bool(false),
            ]),
            sequence: 3,
            eventName: "MESSAGE_REACTION_ADD"
        ))
        #expect(
            await add.value
                == .add(
                    channelID: ChannelID(rawValue: 200),
                    messageID: MessageID(rawValue: 300),
                    userID: UserID(rawValue: 2),
                    emoji: "🔥",
                    kind: .normal
                )
        )

        let currentUserAdd = Task { () -> MessageReactionUpdate? in
            for await event in events {
                if case let .messageReactionUpdated(update) = event { return update }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "user_id": .string("1"),
                "channel_id": .string("200"),
                "message_id": .string("300"),
                "emoji": .object(["id": .null, "name": .string("🔥")]),
                "type": .number(0),
                "burst": .bool(false),
            ]),
            sequence: 4,
            eventName: "MESSAGE_REACTION_ADD"
        ))
        #expect(
            await currentUserAdd.value
                == .add(
                    channelID: ChannelID(rawValue: 200),
                    messageID: MessageID(rawValue: 300),
                    userID: UserID(rawValue: 1),
                    emoji: "🔥",
                    kind: .normal
                )
        )

        let optimisticRemove = Task { () -> Message? in
            for await event in events {
                if case let .messageUpdated(message) = event, message.id == MessageID(rawValue: 300)
                {
                    return message
                }
            }
            return nil
        }
        try await provider.toggleReaction(
            "🔥",
            messageID: MessageID(rawValue: 300),
            channelID: ChannelID(rawValue: 200)
        )
        let removed = try #require(await optimisticRemove.value)
        #expect(removed.reactions.first?.count == 1)
        #expect(removed.reactions.first?.didCurrentUserReact == false)
        #expect(RateLimitURLProtocol.reactionMethods == ["DELETE"])

        let removeEcho = Task { () -> MessageReactionUpdate? in
            for await event in events {
                if case let .messageReactionUpdated(update) = event { return update }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "user_id": .string("1"),
                "channel_id": .string("200"),
                "message_id": .string("300"),
                "emoji": .object(["id": .null, "name": .string("🔥")]),
                "type": .number(0),
                "burst": .bool(false),
            ]),
            sequence: 5,
            eventName: "MESSAGE_REACTION_REMOVE"
        ))
        #expect(
            await removeEcho.value
                == .remove(
                    channelID: ChannelID(rawValue: 200),
                    messageID: MessageID(rawValue: 300),
                    userID: UserID(rawValue: 1),
                    emoji: "🔥",
                    kind: .normal
                )
        )

        let optimisticAdd = Task { () -> Message? in
            for await event in events {
                if case let .messageUpdated(message) = event, message.id == MessageID(rawValue: 300)
                {
                    return message
                }
            }
            return nil
        }
        try await provider.toggleReaction(
            "🔥",
            messageID: MessageID(rawValue: 300),
            channelID: ChannelID(rawValue: 200)
        )
        let readded = try #require(await optimisticAdd.value)
        #expect(readded.reactions.first?.count == 2)
        #expect(readded.reactions.first?.didCurrentUserReact == true)
        #expect(RateLimitURLProtocol.reactionMethods == ["DELETE", "PUT"])
        try await provider.setReaction(
            "🔥",
            reacted: true,
            messageID: MessageID(rawValue: 300),
            channelID: ChannelID(rawValue: 200)
        )
        #expect(RateLimitURLProtocol.reactionMethods == ["DELETE", "PUT"])

        let remove = Task { () -> MessageReactionUpdate? in
            for await event in events {
                if case let .messageReactionUpdated(update) = event { return update }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "user_id": .string("1"),
                "channel_id": .string("200"),
                "message_id": .string("300"),
                "emoji": .object([
                    "id": .string("999"),
                    "name": .string("party_blob"),
                    "animated": .bool(true),
                ]),
                "type": .number(1),
                "burst": .bool(true),
            ]),
            sequence: 6,
            eventName: "MESSAGE_REACTION_REMOVE"
        ))
        #expect(
            await remove.value
                == .remove(
                    channelID: ChannelID(rawValue: 200),
                    messageID: MessageID(rawValue: 300),
                    userID: UserID(rawValue: 1),
                    emoji: "<a:party_blob:999>",
                    kind: .burst
                )
        )

        let removeEmoji = Task { () -> MessageReactionUpdate? in
            for await event in events {
                if case let .messageReactionUpdated(update) = event { return update }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "channel_id": .string("200"),
                "message_id": .string("300"),
                "emoji": .object([
                    "id": .string("999"),
                    "name": .string("renamed_blob"),
                ]),
            ]),
            sequence: 7,
            eventName: "MESSAGE_REACTION_REMOVE_EMOJI"
        ))
        #expect(
            await removeEmoji.value
                == .removeEmoji(
                    channelID: ChannelID(rawValue: 200),
                    messageID: MessageID(rawValue: 300),
                    emoji: "<:renamed_blob:999>"
                )
        )

        let removeAll = Task { () -> MessageReactionUpdate? in
            for await event in events {
                if case let .messageReactionUpdated(update) = event { return update }
            }
            return nil
        }
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "channel_id": .string("200"),
                "message_id": .string("300"),
            ]),
            sequence: 8,
            eventName: "MESSAGE_REACTION_REMOVE_ALL"
        ))
        #expect(
            await removeAll.value
                == .removeAll(
                    channelID: ChannelID(rawValue: 200),
                    messageID: MessageID(rawValue: 300)
                )
        )

        await provider.disconnect()
        }
    }
}
