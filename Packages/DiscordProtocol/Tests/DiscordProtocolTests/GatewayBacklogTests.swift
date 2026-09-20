@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Testing

@Test func `channel update bursts preserve final state and ordered message boundaries`() async throws {
    let provider = DiscordRESTProvider(
        credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "channel-burst"),
        session: URLSession(configuration: .ephemeral)
    )
    func channel(_ name: String, id: Int = 200, type: Int = 0, parent: String? = "100") -> JSONValue {
        .object([
            "id": .string(String(id)), "guild_id": .string("10"),
            "type": .number(Double(type)), "name": .string(name),
            "position": .number(Double(id)), "parent_id": parent.map(JSONValue.string) ?? .null,
            "permission_overwrites": .array([])
        ])
    }
    await provider.handleGatewayDispatch(name: "CHANNEL_CREATE", body: channel("Category", id: 100, type: 4, parent: nil))
    for id in 200 ..< 350 {
        await provider.handleGatewayDispatch(name: "CHANNEL_CREATE", body: channel("Channel", id: id))
    }
    let events = await provider.eventStream()
    // Keep the consumer paused across more updates than the queue's capacity.
    for index in 0 ..< 800 {
        await provider.handleGatewayDispatch(name: "CHANNEL_UPDATE", body: channel("Before \(index)"))
    }
    await provider.handleGatewayDispatch(name: "MESSAGE_DELETE", body: .object([
        "id": .string("999"), "channel_id": .string("200"), "guild_id": .string("10")
    ]))
    for index in 0 ..< 800 {
        await provider.handleGatewayDispatch(name: "CHANNEL_UPDATE", body: channel("After \(index)"))
    }
    // Category metadata must still be recomputed for every child.
    await provider.handleGatewayDispatch(name: "CHANNEL_UPDATE", body: channel("Renamed", id: 100, type: 4, parent: nil))
    await provider.continuation?.finish()
    var received: [ClientEvent] = []
    for await event in events { received.append(event) }
    #expect(received.count == 4)
    guard received.count == 4 else { return }
    guard case let .channelsChanged(_, before) = received[0],
          case let .channelsChanged(_, after) = received[3] else {
        Issue.record("Expected channel snapshots on either side of the message deletion")
        return
    }
    #expect(before.first?.name == "Before 799")
    #expect(received[1] == .messageDeleted(channelID: ChannelID(rawValue: 200), messageID: MessageID(rawValue: 999)))
    #expect(after.count == 150)
    #expect(after.first?.name == "After 799")
    #expect(after.allSatisfy { $0.category == "Renamed" })
    #expect(await provider.cachedChannels[GuildID(rawValue: 10)] == after)

    let unchanged = await provider.eventStream()
    for _ in 0 ..< 600 {
        await provider.handleGatewayDispatch(name: "CHANNEL_UPDATE", body: channel("After 799"))
    }
    await provider.continuation?.finish()
    var unchangedCount = 0
    for await _ in unchanged { unchangedCount += 1 }
    #expect(unchangedCount == 0, "Repeated identical updates must not republish the server")
    await provider.disconnect()
}

@Test func `large startup payloads preserve every guild and subsequent live events`() async throws {
    let provider = DiscordRESTProvider(
        credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "guild-burst"),
        session: URLSession(configuration: .ephemeral)
    )
    func guilds(roleName: String) -> [JSONValue] {
        (1 ... 200).map { id in
            .object([
                "id": .string(String(id)), "name": .string("Fixture"),
                "roles": .array([.object([
                    "id": .string(String(id)), "name": .string(roleName),
                    "position": .number(0), "hoist": .bool(false), "permissions": .string("0")
                ])]),
                "emojis": .array([]), "stickers": .array([])
            ])
        }
    }
    let events = await provider.eventStream()
    await provider.handleGatewayDispatch(name: "READY", body: .object([
        "user": .object(["id": .string("99999"), "username": .string("fixture"), "discriminator": .string("0")]),
        "guilds": .array(guilds(roleName: "Initial"))
    ]))
    await provider.handleGatewayDispatch(name: "READY_SUPPLEMENTAL", body: .object([
        "guilds": .array(guilds(roleName: "Supplemental"))
    ]))
    let deletion = ClientEvent.messageDeleted(channelID: ChannelID(rawValue: 200), messageID: MessageID(rawValue: 999))
    await provider.handleGatewayDispatch(name: "MESSAGE_DELETE", body: .object([
        "id": .string("999"), "channel_id": .string("200"), "guild_id": .string("10")
    ]))
    await provider.continuation?.finish()
    var roleNames: [GuildID: [String]] = [:]
    var emojiGuilds: Set<GuildID> = []
    var stickerGuilds: Set<GuildID> = []
    var last: ClientEvent?
    // The consumer starts only after both complete startup payloads and live traffic.
    for await event in events {
        last = event
        switch event {
        case let .guildRolesChanged(guildID, roles):
            roleNames[guildID, default: []].append(contentsOf: roles.map(\.name))
        case let .emojisChanged(guildID, _): emojiGuilds.insert(guildID)
        case let .stickersChanged(guildID, _): stickerGuilds.insert(guildID)
        case .sessionInvalidated: Issue.record("Initial metadata exhausted the event queue")
        default: break
        }
    }
    let expected = Set((1 ... 200).map { GuildID(rawValue: UInt64($0)) })
    #expect(Set(roleNames.keys) == expected)
    #expect(roleNames.values.allSatisfy { $0 == ["Initial", "Supplemental"] })
    #expect(emojiGuilds == expected)
    #expect(stickerGuilds == expected)
    #expect(last == deletion)
    await provider.disconnect()
}

@Test(arguments: ["READY", "READY_SUPPLEMENTAL", "GUILD_CREATE"])
func `large initial voice snapshot preserves session and later live updates`(dispatch: String) async throws {
    let provider = DiscordRESTProvider(
        credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "voice-burst"),
        session: URLSession(configuration: .ephemeral)
    )
    func voice(_ id: Int, channel: String?) -> JSONValue {
        .object([
            "user_id": .string(String(id)), "guild_id": .string("10"),
            "channel_id": channel.map(JSONValue.string) ?? .null, "session_id": .string("fixture"),
            "deaf": .bool(false), "mute": .bool(false), "self_deaf": .bool(false),
            "self_mute": .bool(false), "self_video": .bool(false), "suppress": .bool(false)
        ])
    }
    let events = await provider.eventStream()
    let guild: JSONValue = .object([
        "id": .string("10"), "name": .string("Fixture"),
        "voice_states": .array((1 ... 650).map { voice($0, channel: "20") })
    ])
    await provider.handleGatewayDispatch(
        name: dispatch,
        body: dispatch == "GUILD_CREATE" ? guild : .object(["guilds": .array([guild])])
    )
    await provider.handleGatewayDispatch(name: "VOICE_STATE_UPDATE", body: voice(650, channel: nil))
    await provider.continuation?.finish()
    var states: [UserID: VoiceParticipantState] = [:]
    var initialCount = 0
    var departures = 0
    for await event in events {
        switch event {
        case .voiceStatesReceived(let snapshot):
            initialCount += snapshot.count
            for state in snapshot { states[state.userID] = state }
        case .voiceStateChanged(let state):
            #expect(initialCount == 650)
            states[state.userID] = state.channelID == nil ? nil : state
            departures += 1
        case .sessionInvalidated:
            Issue.record("A valid initial voice snapshot overflowed the event queue")
        default: break
        }
    }
    #expect(initialCount == 650)
    #expect(departures == 1)
    #expect(states.count == 649)
    #expect(states[UserID(rawValue: 650)] == nil)
    await provider.disconnect()
}
