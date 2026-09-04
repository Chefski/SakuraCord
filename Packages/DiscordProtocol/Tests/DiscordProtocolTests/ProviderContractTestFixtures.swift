@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Testing

actor TestCredentialStore: CredentialStore {
    private(set) var credentialReadCount = 0

    func store(_ credential: Data, accountID: String) async throws -> CredentialHandle {
        CredentialHandle(accountID: accountID)
    }

    func credential(for handle: CredentialHandle) async throws -> Data {
        credentialReadCount += 1
        return Data("test-session-credential-value".utf8)
    }

    func remove(_ handle: CredentialHandle) async throws {}
    func handles() async throws -> [CredentialHandle] {
        [CredentialHandle(accountID: "1")]
    }
}

struct UnavailableGatewayTransport: GatewayTransport {
    func connect(to url: URL, maximumMessageSize: Int) async throws -> any GatewaySocket {
        throw URLError(.notConnectedToInternet)
    }
}

struct ReadyGatewayTransport: GatewayTransport {
    let socket: ReadyGatewaySocket

    func connect(to url: URL, maximumMessageSize: Int) async throws -> any GatewaySocket {
        socket
    }
}

private enum ReadyGatewayError: Error { case closed }

actor ReadyGatewaySocket: GatewaySocket {
    private var queued: [GatewaySocketMessage] = []
    private var receiver: CheckedContinuation<GatewaySocketMessage, any Error>?
    private(set) var sentCount = 0
    private(set) var sentPayloads: [Data] = []

    func receive() async throws -> GatewaySocketMessage {
        if !queued.isEmpty { return queued.removeFirst() }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }

    func send(_ data: Data) async throws {
        sentCount += 1
        sentPayloads.append(data)
    }

    func sentPayload(opcode: Int) -> Data? {
        sentPayloads.last { data in
            guard
                let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { return false }
            return (object["op"] as? NSNumber)?.intValue == opcode
        }
    }

    func sentPayloadCount(opcode: Int) -> Int {
        sentPayloads.count { data in
            guard
                let object = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else { return false }
            return (object["op"] as? NSNumber)?.intValue == opcode
        }
    }

    func sentOpcodes() -> [Int] {
        sentPayloads.compactMap { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return (object["op"] as? NSNumber)?.intValue
        }
    }

    func close(code: Int) async {
        receiver?.resume(throwing: ReadyGatewayError.closed)
        receiver = nil
    }

    func closeCode() async -> Int? { nil }

    func push(_ message: GatewaySocketMessage) {
        if let receiver {
            self.receiver = nil
            receiver.resume(returning: message)
        } else {
            queued.append(message)
        }
    }
}

func gatewayMessage(
    op: Int,
    data: JSONValue?,
    sequence: Int? = nil,
    eventName: String? = nil
) -> GatewaySocketMessage {
    let envelope = GatewayEnvelope(
        op: op, data: data, sequence: sequence, eventName: eventName
    )
    return .text(restrictionGatewayText(envelope))
}

private func restrictionGatewayText(_ envelope: GatewayEnvelope) -> String {
    let data: Data
    do {
        data = try JSONGatewayCodec().encode(envelope)
    } catch {
        preconditionFailure("Invalid test Gateway envelope: \(error)")
    }
    guard let text = String(data: data, encoding: .utf8) else {
        preconditionFailure("Gateway JSON encoder returned non-UTF-8 data")
    }
    return text
}

private enum RestrictionGatewayError: Error { case closed }

struct RestrictionGatewayTransport: GatewayTransport {
    let socket: RestrictionGatewaySocket

    func connect(to url: URL, maximumMessageSize: Int) async throws -> any GatewaySocket {
        socket
    }
}

actor RestrictionGatewaySocket: GatewaySocket {
    private var queued: [GatewaySocketMessage] = [
        gatewayMessage(
            op: 10, data: .object(["heartbeat_interval": .number(60_000)])
        ),
        gatewayMessage(
            op: 0,
            data: .object([
                "session_id": .string("restriction-session"),
                "resume_gateway_url": .string("wss://gateway.discord.gg"),
                "guilds": .array([]),
            ]),
            sequence: 1,
            eventName: "READY"
        ),
    ]
    private var receiver: CheckedContinuation<GatewaySocketMessage, any Error>?
    private(set) var receiveStarted = false
    private(set) var closeCodes: [Int] = []

    func receive() async throws -> GatewaySocketMessage {
        receiveStarted = true
        if !queued.isEmpty {
            return queued.removeFirst()
        }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }

    func send(_ data: Data) async throws {}

    func close(code: Int) async {
        closeCodes.append(code)
        receiver?.resume(throwing: RestrictionGatewayError.closed)
        receiver = nil
    }

    func closeCode() async -> Int? {
        nil
    }
}

actor ReactionProjectionEventRecorder {
    private(set) var reactionUpdateCount = 0
    private(set) var forumCataloguePublishCount = 0

    func record(_ event: ClientEvent) {
        switch event {
        case .messageReactionUpdated:
            reactionUpdateCount += 1
        case .forumPostsChanged:
            forumCataloguePublishCount += 1
        default:
            break
        }
    }
}

func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0 ..< 500 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}
