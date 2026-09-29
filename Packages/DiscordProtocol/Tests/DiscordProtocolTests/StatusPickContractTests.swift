@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Testing

/// Shares the serialized suite that owns `DirectMessageURLProtocol`'s state.
extension DirectMessageProviderContractTests {
    @Test func `status pick sends presence then one sibling preserving settings write and ignores its echo`() async throws {
        DirectMessageURLProtocol.reset()
        // StatusSettings: invisible, empty show_current_game, created-at, and a
        // custom status, all of which a pick other than status must preserve.
        let base = try #require(Data(base64Encoded: "CgsKCWludmlzaWJsZRoAKgcIxf7s0YU0"))
        let retained = try #require(DiscordSettingsProto.statusSettings(
            in: DiscordSettingsProto.updatingCustomStatus(ProfileCustomStatus(text: "Gardening"), in: base)
        ))
        let session = try await readyStatusPickProvider(
            settings: DiscordSettingsProto.protoLengthDelimitedField(11, retained)
        )
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider, socket = session.socket, events = session.events
        #expect(await provider.currentStatus() == .invisible)

        try await provider.updateStatus(.dnd)

        #expect(await socket.sentOpcodes() == [2, 4, 3, 41, 40, 3])
        let presence = try #require(await socket.sentPayload(opcode: 3))
        let presenceObject = try #require(JSONSerialization.jsonObject(with: presence) as? [String: Any])
        #expect((presenceObject["d"] as? [String: Any])?["status"] as? String == "dnd")
        #expect(DirectMessageURLProtocol.requests.count == 1)
        let request = try #require(DirectMessageURLProtocol.requests.first)
        #expect(request.method == "PATCH")
        #expect(request.encodedPath == "/api/v9/users/@me/settings-proto/1")
        #expect(request.hadAuthorization)
        #expect(request.body?.keys.sorted() == ["settings"])
        // The official presence updater sends opcode 3 before the settings save.
        #expect(try #require(await socket.sentInstants.last) < request.receivedAt)
        let body = try #require(Data(base64Encoded: request.body?["settings"] as? String ?? ""))
        let rootFields = protoFieldNumbers(body)
        #expect(rootFields == [11])
        let written = try #require(DiscordSettingsProto.statusSettings(in: body))
        #expect(DiscordSettingsProto.presenceStatus(in: written) == .dnd)
        #expect(DiscordSettingsProto.customStatus(in: written)?.text == "Gardening")
        #expect(protoFieldNumbers(written) == [1, 2, 3, 5])
        #expect(protoField(5, in: written) != protoField(5, in: retained))
        #expect(protoField(3, in: written) == protoField(3, in: retained))

        // The Gateway echo of the saved settings changes nothing and sends nothing.
        await provider.receiveGatewayDispatchForTesting(name: "USER_SETTINGS_PROTO_UPDATE", data: .object([
            "settings": .object(["type": .number(1), "proto": .string(request.body?["settings"] as? String ?? "")]),
            "partial": .bool(true),
        ]))
        #expect(await provider.currentStatus() == .dnd)
        #expect(await socket.sentPayloadCount(opcode: 3) == 2)
        #expect(DirectMessageURLProtocol.requests.count == 1)

        // Re-picking the same status keeps its original creation time.
        try await provider.updateStatus(.dnd)
        #expect(await socket.sentPayloadCount(opcode: 3) == 2)
        #expect(DirectMessageURLProtocol.requests.count == 2)
        let repeated = try #require(Data(base64Encoded: DirectMessageURLProtocol.requests.last?.body?["settings"] as? String ?? ""))
        #expect(protoField(5, in: try #require(DiscordSettingsProto.statusSettings(in: repeated))) == protoField(5, in: written))
        await provider.disconnect()
        #expect(await statusEvents(events) == [.dnd])
    }

    @Test func `account status follows settings updates and republishes only changed presence`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("dnd"))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider, socket = session.socket

        await settingsUpdate(provider, statusSettingsFixture("idle"))
        #expect(await provider.currentStatus() == .idle)
        #expect(await presenceStatuses(socket) == ["dnd", "idle"])

        // Unchanged or unrelated settings send nothing.
        await settingsUpdate(provider, DiscordSettingsProto.protoLengthDelimitedField(13, Data()))
        await settingsUpdate(provider, statusSettingsFixture("idle"), partial: false)
        #expect(await presenceStatuses(socket) == ["dnd", "idle"])

        // As in the official client, an absent or unknown status is online.
        let customStatusOnly = DiscordSettingsProto.updatingCustomStatus(ProfileCustomStatus(text: "away"), in: Data())
        await settingsUpdate(provider, customStatusOnly)
        #expect(await provider.currentStatus() == .online)
        await settingsUpdate(provider, statusSettingsFixture("unknown"), partial: false)
        await settingsUpdate(provider, Data(), partial: false)
        #expect(await presenceStatuses(socket) == ["dnd", "idle", "online"])
        #expect(DirectMessageURLProtocol.requests.isEmpty)
        await provider.disconnect()
        #expect(await statusEvents(session.events) == [.dnd, .idle, .online])
    }

    @Test func `presence beyond five sends in twenty seconds defers only the latest value`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("dnd"))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider, socket = session.socket
        // The post-READY presence and four changes fill the official window.
        for status in ["idle", "online", "idle", "online", "idle", "dnd"] {
            await settingsUpdate(provider, statusSettingsFixture(status))
        }
        #expect(await presenceStatuses(socket) == ["dnd", "idle", "online", "idle", "online"])
        #expect(await provider.hasDeferredPresenceForTesting())

        await provider.reopenPresenceSendWindowForTesting()
        #expect(await presenceStatuses(socket).last == "dnd")
        #expect(await socket.sentPayloadCount(opcode: 3) == 6)
        #expect(await provider.hasDeferredPresenceForTesting() == false)
        await provider.disconnect()
    }

    @Test func `queued status writes save only the newest pick and merge it into custom status writes`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("online"))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider, socket = session.socket
        await provider.holdStatusSettingsSaveForTesting()
        let custom = Task { try await provider.updateProfileCustomStatus(ProfileCustomStatus(text: "Gardening")) }
        #expect(await eventually { await provider.statusSettingsSaveWaiterCountForTesting() == 1 })
        let first = Task { try await provider.updateStatus(.idle) }
        #expect(await eventually { await provider.statusSettingsSaveWaiterCountForTesting() == 2 })
        let second = Task { try await provider.updateStatus(.dnd) }
        #expect(await eventually { await provider.statusSettingsSaveWaiterCountForTesting() == 3 })

        // A settings update that is not the pick's own save cannot replace it.
        await settingsUpdate(provider, statusSettingsFixture("online"))
        #expect(await provider.currentStatus() == .dnd)

        await provider.releaseStatusSettingsSaveForTesting()
        _ = try await custom.value
        try await first.value
        try await second.value
        let written = try DirectMessageURLProtocol.requests.map { try writtenStatusSettings($0) }
        // Whichever writer runs first carries the pending pick; the replaced
        // pick is never written.
        #expect((1 ... 2).contains(written.count))
        #expect(written.allSatisfy { DiscordSettingsProto.presenceStatus(in: $0) == .dnd })
        #expect(written.last.flatMap(DiscordSettingsProto.customStatus(in:))?.text == "Gardening")
        #expect(await provider.currentStatus() == .dnd)
        #expect(await provider.pendingStatusEditForTesting() == nil)
        #expect(await socket.sentPayloadCount(opcode: 3) == 3)
        await provider.disconnect()
    }

    @Test(arguments: [false, true])
    func `a failed status save stays pending across relaunch and is saved once per READY`(outOfDate: Bool) async throws {
        DirectMessageURLProtocol.reset()
        let first = try await readyStatusPickProvider(settings: statusSettingsFixture("online", dataVersion: 7))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: first.accountID) }
        DirectMessageURLProtocol.settingsReplies = [(500, "{}")]
        await #expect(throws: ChatProviderError.self) { try await first.provider.updateStatus(.dnd) }
        // The pick keeps its status without a retry, and a later settings
        // update neither replaces it nor saves it again.
        await settingsUpdate(first.provider, statusSettingsFixture("idle", dataVersion: 8))
        #expect(await first.provider.currentStatus() == .dnd)
        #expect(await first.provider.runScheduledStatusEditSaveForTesting() == false)
        #expect(DirectMessageURLProtocol.requests.count == 1)
        // Closing records the current data version with the persisted edit.
        await first.provider.disconnect()

        let second = try await readyStatusPickProvider(
            settings: statusSettingsFixture("idle", dataVersion: 8), accountID: first.accountID, restoresPendingEdit: true
        )
        let provider = second.provider
        #expect(await presenceStatuses(second.socket) == ["dnd"])
        #expect(DirectMessageURLProtocol.requests.count == 1)

        // Each READY schedules one silent attempt; a failure waits for the next.
        DirectMessageURLProtocol.settingsReplies = [(500, "{}")]
        #expect(await provider.runScheduledStatusEditSaveForTesting())
        #expect(await provider.runScheduledStatusEditSaveForTesting() == false)
        #expect(DirectMessageURLProtocol.requests.count == 2)
        await provider.receiveGatewayDispatchForTesting(name: "READY", data: .object([
            "user": .object(["id": .string("2"), "username": .string("maya")]),
            "guilds": .array([]),
            "user_settings_proto": .string(statusSettingsFixture("idle", dataVersion: 8).base64EncodedString()),
        ]))
        if outOfDate {
            DirectMessageURLProtocol.settingsReplies = [(200, try settingsResponse(statusSettingsFixture("online", dataVersion: 9), outOfDate: true))]
        }
        #expect(await provider.runScheduledStatusEditSaveForTesting())
        #expect(DirectMessageURLProtocol.requests.count == 3)
        for request in DirectMessageURLProtocol.requests.dropFirst() {
            #expect(request.body?["required_data_version"] as? Int == 8)
            #expect(DiscordSettingsProto.presenceStatus(in: try writtenStatusSettings(request)) == .dnd)
        }
        // Success and out_of_date both end the edit; out_of_date adopts the server's settings.
        #expect(await provider.pendingStatusEditForTesting() == nil)
        #expect(UserDefaults.standard.object(forKey: "dev.sakuracord.pending-status-edit.\(first.accountID)") == nil)
        #expect(await provider.currentStatus() == (outOfDate ? .online : .dnd))
        #expect(await presenceStatuses(second.socket) == (outOfDate ? ["dnd", "online"] : ["dnd"]))
        await provider.disconnect()
        #expect(await statusEvents(second.events) == (outOfDate ? [.dnd, .online] : [.dnd]))
    }

    @Test func `invalid settings data discards the pick and reloads the server settings`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("online", dataVersion: 3))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        DirectMessageURLProtocol.settingsReplies = [
            (400, #"{"code":50105,"message":"Invalid user settings data"}"#),
            (200, try settingsResponse(statusSettingsFixture("idle", dataVersion: 4))),
        ]
        await #expect(throws: ChatProviderError.self) { try await session.provider.updateStatus(.dnd) }
        #expect(DirectMessageURLProtocol.requests.map { "\($0.method) \($0.path)" } == [
            "PATCH /api/v9/users/@me/settings-proto/1", "GET /api/v9/users/@me/settings-proto/1",
        ])
        #expect(await session.provider.pendingStatusEditForTesting() == nil)
        #expect(await session.provider.currentStatus() == .idle)
        #expect(await presenceStatuses(session.socket) == ["online", "dnd", "idle"])
        #expect(await !session.provider.requestSafetyCircuitIsOpen)
        #expect(DiscordRESTProvider.isSafetyStop(
            status: 400, discordCode: 50105, method: "PATCH", data: Data(), path: "/users/@me/settings-proto/2"
        ))
        await session.provider.disconnect()
    }

    @Test func `a newer pick replaces a failed one`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("online", dataVersion: 5))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider
        DirectMessageURLProtocol.settingsReplies = [(500, "{}")]
        await #expect(throws: ChatProviderError.self) { try await provider.updateStatus(.idle) }
        try await provider.updateStatus(.dnd)
        #expect(DirectMessageURLProtocol.requests.count == 2)
        let request = try #require(DirectMessageURLProtocol.requests.last)
        #expect(request.body?.keys.sorted() == ["settings"])
        #expect(DiscordSettingsProto.presenceStatus(in: try writtenStatusSettings(request)) == .dnd)
        #expect(await provider.pendingStatusEditForTesting() == nil)
        // The replaced pick is not saved by a later session.
        await provider.receiveGatewayDispatchForTesting(name: "READY", data: .object([
            "user": .object(["id": .string("2"), "username": .string("maya")]),
            "guilds": .array([]),
            "user_settings_proto": .string(statusSettingsFixture("dnd", dataVersion: 6).base64EncodedString()),
        ]))
        #expect(await provider.runScheduledStatusEditSaveForTesting() == false)
        #expect(await provider.currentStatus() == .dnd)
        await provider.disconnect()
    }

    @Test func `a live pick drops a stale data version but a write carrying the offline edit keeps it`() async throws {
        DirectMessageURLProtocol.reset()
        let accountID = "status-stale-\(UUID().uuidString)"
        let key = "dev.sakuracord.pending-status-edit.\(accountID)"
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: accountID) }
        UserDefaults.standard.set(["status": "idle", "requiredDataVersion": 5], forKey: key)
        let session = try await readyStatusPickProvider(
            settings: statusSettingsFixture("online", dataVersion: 6), accountID: accountID, restoresPendingEdit: true
        )
        let provider = session.provider
        #expect(await provider.pendingStatusEditForTesting()?.requiredDataVersion == 5)

        // A pick on an open connection replaces the offline edit and its version.
        DirectMessageURLProtocol.settingsReplies = [(500, "{}")]
        await #expect(throws: ChatProviderError.self) { try await provider.updateStatus(.dnd) }
        #expect(DirectMessageURLProtocol.requests.last?.body?.keys.sorted() == ["settings"])
        #expect(await provider.pendingStatusEditForTesting()?.requiredDataVersion == nil)

        // A custom status carrying an offline edit keeps its version, and a
        // discarded user save is reported with the server's settings kept.
        UserDefaults.standard.set(["status": "invisible", "requiredDataVersion": 5], forKey: key)
        await provider.loadPendingStatusEdit()
        DirectMessageURLProtocol.settingsReplies = [
            (200, try settingsResponse(statusSettingsFixture("online", dataVersion: 7), outOfDate: true)),
        ]
        await #expect(throws: ChatProviderError.self) {
            try await provider.updateProfileCustomStatus(ProfileCustomStatus(text: "Gardening"))
        }
        let custom = try #require(DirectMessageURLProtocol.requests.last)
        #expect(custom.body?["required_data_version"] as? Int == 5)
        #expect(DiscordSettingsProto.presenceStatus(in: try writtenStatusSettings(custom)) == .invisible)
        #expect(DirectMessageURLProtocol.requests.count == 2)
        #expect(await provider.pendingStatusEditForTesting() == nil)
        #expect(await provider.currentStatus() == .online)
        await provider.disconnect()
    }

    @Test func `a resumed session saves a pending status edit once`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("online", dataVersion: 4))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider
        DirectMessageURLProtocol.settingsReplies = [(500, "{}")]
        await #expect(throws: ChatProviderError.self) { try await provider.updateStatus(.dnd) }
        await provider.handleGatewaySessionEvent(.stateChanged(.resuming))
        await provider.receiveGatewayDispatchForTesting(name: "RESUMED", data: .object([:]))
        #expect(await provider.runScheduledStatusEditSaveForTesting())
        #expect(await provider.runScheduledStatusEditSaveForTesting() == false)
        #expect(DirectMessageURLProtocol.requests.count == 2)
        let request = try #require(DirectMessageURLProtocol.requests.last)
        #expect(request.body?["required_data_version"] as? Int == 4)
        #expect(DiscordSettingsProto.presenceStatus(in: try writtenStatusSettings(request)) == .dnd)
        #expect(await provider.pendingStatusEditForTesting() == nil)
        await provider.disconnect()
    }

    @Test func `republished member lists carry the adopted account status`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("dnd"))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider
        let me = try #require(await provider.currentUser)
        let guildID = GuildID(rawValue: 10)
        // The member cache keeps whatever status the member was built with.
        await provider.publishMemberChange(Member(user: me, roleName: "Member", status: .online), guildID: guildID)
        await settingsUpdate(provider, statusSettingsFixture("idle"))
        let other = User(id: UserID(rawValue: 77), username: "other", displayName: "Other")
        await provider.publishMemberChange(Member(user: other, roleName: "Member", status: .online), guildID: guildID)
        await provider.disconnect()
        var selfStatuses: [PresenceStatus?] = []
        for await event in session.events {
            if case let .membersChanged(_, members, _) = event { selfStatuses.append(members.first { $0.id == me.id }?.status) }
        }
        #expect(selfStatuses == [.dnd, .idle])
    }

    @Test func `losing focus flushes a failed pick once`() async throws {
        DirectMessageURLProtocol.reset()
        let session = try await readyStatusPickProvider(settings: statusSettingsFixture("online", dataVersion: 1))
        defer { DiscordRESTProvider.removePendingStatusEdit(accountID: session.accountID) }
        let provider = session.provider
        DirectMessageURLProtocol.settingsReplies = [(500, "{}"), (500, "{}")]
        await #expect(throws: ChatProviderError.self) { try await provider.updateStatus(.dnd) }

        await provider.holdStatusSettingsSaveForTesting()
        await provider.updateClientAppState(isFocused: false)
        #expect(await eventually { await provider.statusSettingsSaveWaiterCountForTesting() == 1 })
        await provider.updateClientAppState(isFocused: true)
        await provider.updateClientAppState(isFocused: false)
        #expect(await provider.runScheduledStatusEditSaveForTesting() == false)
        await provider.releaseStatusSettingsSaveForTesting()
        #expect(await eventually { DirectMessageURLProtocol.requests.count == 2 })

        // The failed flush leaves the pick pending without another attempt.
        await provider.updateClientAppState(isFocused: true)
        await provider.updateClientAppState(isFocused: false)
        #expect(await provider.runScheduledStatusEditSaveForTesting() == false)
        #expect(await provider.pendingStatusEditForTesting()?.status == .dnd)
        #expect(DirectMessageURLProtocol.requests.count == 2)
        await provider.disconnect()
    }

    @Test(arguments: zip(["invisible", "online"], ["online", "invisible"]))
    func `only a device-only Invisible from earlier releases is carried over`(
        deviceStatus: String, accountStatus: String
    ) async throws {
        DirectMessageURLProtocol.reset()
        let accountID = "status-carry-over-\(UUID().uuidString)"
        let legacyKey = "dev.sakuracord.presence.\(accountID)"
        UserDefaults.standard.set(deviceStatus, forKey: legacyKey)
        defer {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            DiscordRESTProvider.removePendingStatusEdit(accountID: accountID)
        }
        let session = try await readyStatusPickProvider(
            settings: statusSettingsFixture(accountStatus, dataVersion: 11), accountID: accountID, restoresPendingEdit: true
        )
        let provider = session.provider
        #expect(UserDefaults.standard.object(forKey: legacyKey) == nil)
        // Invisible wins either way and is never exposed as online first.
        #expect(await presenceStatuses(session.socket) == ["invisible"])
        let carried = deviceStatus == "invisible"
        #expect(await provider.runScheduledStatusEditSaveForTesting() == carried)
        #expect(DirectMessageURLProtocol.requests.count == (carried ? 1 : 0))
        if let request = DirectMessageURLProtocol.requests.first {
            #expect(request.body?["required_data_version"] as? Int == 11)
            #expect(DiscordSettingsProto.presenceStatus(in: try writtenStatusSettings(request)) == .invisible)
        }
        #expect(await provider.pendingStatusEditForTesting() == nil)
        #expect(await provider.currentStatus() == .invisible)
        await provider.disconnect()
        #expect(await statusEvents(session.events).isEmpty)
    }

    private func settingsResponse(_ settings: Data, outOfDate: Bool = false) throws -> String {
        var object: [String: Any] = ["settings": settings.base64EncodedString()]
        if outOfDate { object["out_of_date"] = true }
        return try #require(String(bytes: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
    }

    private func settingsUpdate(_ provider: DiscordRESTProvider, _ proto: Data, partial: Bool = true) async {
        await provider.receiveGatewayDispatchForTesting(name: "USER_SETTINGS_PROTO_UPDATE", data: .object([
            "settings": .object(["type": .number(1), "proto": .string(proto.base64EncodedString())]),
            "partial": .bool(partial),
        ]))
    }

    private func writtenStatusSettings(_ request: CapturedDirectMessageRequest) throws -> Data {
        let body = try #require(Data(base64Encoded: request.body?["settings"] as? String ?? ""))
        return try #require(DiscordSettingsProto.statusSettings(in: body))
    }

    private func readyStatusPickProvider(
        settings: Data, accountID: String = "status-pick-\(UUID().uuidString)", restoresPendingEdit: Bool = false
    ) async throws -> StatusPickSession {
        let socket = ReadyGatewaySocket()
        await socket.push(gatewayMessage(op: 10, data: .object(["heartbeat_interval": .number(60_000)])))
        await socket.push(gatewayMessage(
            op: 0,
            data: .object([
                "session_id": .string("status-pick-session"),
                "resume_gateway_url": .string("wss://gateway.discord.gg"),
                "user": .object(["id": .string("2"), "username": .string("maya")]),
                "guilds": .array([]),
                "user_settings_proto": .string(settings.base64EncodedString()),
            ]),
            sequence: 1,
            eventName: "READY"
        ))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectMessageURLProtocol.self]
        let provider = DiscordRESTProvider(
            credentials: DirectMessageCredentialStore(),
            handle: CredentialHandle(accountID: accountID),
            session: URLSession(configuration: configuration),
            gatewayTransport: ReadyGatewayTransport(socket: socket),
            usesDesktopHeartbeat: true,
            installationID: "server-issued-installation"
        )
        if restoresPendingEdit { await provider.loadPendingStatusEdit() }
        let events = await provider.eventStream()
        try await provider.startGateway()
        #expect(await eventually { await socket.sentCount == 5 })
        return StatusPickSession(accountID: accountID, provider: provider, socket: socket, events: events)
    }

    private func protoFieldNumbers(_ data: Data) -> [Int] {
        var reader = ProtoReader(data: data)
        var numbers: [Int] = []
        while let field = reader.readRawField() { numbers.append(field.field) }
        return numbers
    }

    private func protoField(_ number: Int, in data: Data) -> Data? {
        var reader = ProtoReader(data: data)
        var result: Data?
        while let field = reader.readRawField() {
            if field.field == number { result = field.raw }
        }
        return result
    }
}

struct StatusPickSession {
    let accountID: String
    let provider: DiscordRESTProvider
    let socket: ReadyGatewaySocket
    let events: AsyncStream<ClientEvent>
}
