import Foundation
import Synchronization
import Testing
import SakuraCordModels
@testable import DiscordProtocol

struct OnboardingContractTests {
    @Test(arguments: ["complete", "unconfirmed", "failed", "edit"])
    func `answer writes are bounded and initial completion requires confirmed membership`(scenario: String) async throws {
        let capture = OnboardingRequestCapture()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OnboardingURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Onboarding-Test": capture.id, "X-Onboarding-Scenario": scenario]
        let socket = ReadyGatewaySocket()
        await socket.push(gatewayMessage(op: 10, data: .object(["heartbeat_interval": .number(60_000)])))
        await socket.push(gatewayMessage(op: 0, data: .object(["session_id": .string("onboarding-test"), "resume_gateway_url": .string("wss://gateway.discord.gg")]), sequence: 1, eventName: "READY"))
        let provider = DiscordRESTProvider(credentials: TestCredentialStore(), handle: .init(accountID: "1"),
            session: URLSession(configuration: configuration), gatewayTransport: ReadyGatewayTransport(socket: socket), installationID: "fixture")
        try await provider.startGateway()
        #expect(await eventually { await provider.gatewaySession?.snapshot().sessionID == "onboarding-test" })
        await provider.seedOnboardingContract()
        let initial = scenario != "edit"
        let saving = Task { try await provider.saveGuildOnboarding(in: .init(rawValue: 100), responses: ["11"], initial: initial) }
        #expect(await eventually { await socket.sentPayloadCount(opcode: 8) == 1 })
        await socket.push(Self.member(flags: initial ? 9 : 11, sequence: 2))
        if scenario != "failed" {
            #expect(await eventually { await socket.sentPayloadCount(opcode: 8) == 2 })
            await socket.push(Self.member(flags: scenario == "unconfirmed" ? 9 : 11, sequence: 3))
        }
        if ["failed", "unconfirmed"].contains(scenario) {
            await #expect(throws: (any Error).self) { _ = try await saving.value }
        } else {
            #expect(try await saving.value.responses == ["11"])
        }
        let writes = capture.requests.filter { $0.httpMethod != "GET" }
        #expect(writes.count == 1)
        let write = try #require(writes.first)
        #expect(write.httpMethod == (initial ? "POST" : "PUT"))
        #expect(write.url?.path == "/api/v9/guilds/100/onboarding-responses")
        let body = try #require(JSONSerialization.jsonObject(with: write.httpBody!) as? [String: Any])
        #expect(body["onboarding_responses"] as? [String] == ["11"])
        let seen = try #require(body["onboarding_prompts_seen"] as? [String: Double])
        #expect(Set(seen.keys) == (initial ? ["10"] : ["10", "20"]))
        #expect(seen.values.allSatisfy { $0 > 1_000_000_000_000 })
        #expect(await provider.cachedMembers[.init(rawValue: 100)]?.first?.requiresOnboarding == ["failed", "unconfirmed"].contains(scenario))
        await provider.disconnect()
    }

    @Test func `deleted options and changed required questions cannot be submitted`() throws {
        let value = try JSONDecoder().decode(GuildOnboarding.self, from: Data(OnboardingURLProtocol.configuration.utf8))
        #expect(value.validResponses(["11", "deleted", "21"], initial: true) == ["11"])
        #expect(value.validationError([], initial: true) != nil)
        #expect(value.validationError(["11"], initial: true) == nil)
        #expect(value.questions(initial: true).count == 1)
        let pending = try JSONDecoder().decode(GuildMemberDTO.self, from: Data(#"{"user":{"id":"1","username":"one"},"roles":[],"pending":false,"flags":9}"#.utf8))
            .domain(currentUserID: .init(rawValue: 1), currentStatus: .offline)
        #expect(pending.isPending == false)
        #expect(pending.requiresOnboarding)
        var sparse = pending
        sparse.flags = nil
        sparse.isPending = nil
        #expect(DiscordMemberStoreOrdering.merging(existing: [pending], updates: [sparse]).first?.requiresOnboarding == true)
    }

    private static func member(flags: Int, sequence: Int) -> GatewaySocketMessage {
        gatewayMessage(op: 0, data: .object([
            "guild_id": .string("100"), "chunk_index": .number(0), "chunk_count": .number(1),
            "members": .array([.object([
                "user": .object(["id": .string("1"), "username": .string("one")]),
                "roles": .array([]), "pending": .bool(false), "flags": .number(Double(flags))
            ])])
        ]), sequence: sequence, eventName: "GUILD_MEMBERS_CHUNK")
    }
}

private extension DiscordRESTProvider {
    func seedOnboardingContract() {
        currentUser = User(id: .init(rawValue: 1), username: "one", displayName: "One")
        cachedGuilds[.init(rawValue: 100)] = Guild(id: .init(rawValue: 100), name: "Test")
    }
}

private final class OnboardingRequestCapture {
    let id = UUID().uuidString
    private final class Storage: Sendable { let requests = Mutex<[URLRequest]>([]) }
    private let storage = Storage()
    private var observer: NSObjectProtocol?
    init() {
        let id = id, storage = storage
        observer = NotificationCenter.default.addObserver(forName: OnboardingURLProtocol.captured, object: nil, queue: nil) { note in
            guard let request = note.object as? URLRequest,
                  request.value(forHTTPHeaderField: "X-Onboarding-Test") == id else { return }
            storage.requests.withLock { $0.append(request) }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    var requests: [URLRequest] { storage.requests.withLock { $0 } }
}

private final class OnboardingURLProtocol: URLProtocol, @unchecked Sendable {
    static let captured = Notification.Name("OnboardingContract.request")
    static let configuration = #"""
    {"guild_id":"100","enabled":true,"default_channel_ids":["200"],"responses":["11"],
    "prompts":[{"id":"10","title":"Required","type":0,"single_select":true,"required":true,"in_onboarding":true,"options":[{"id":"11","title":"Role","role_ids":["101"],"channel_ids":[]}]},
    {"id":"20","title":"Optional","type":0,"single_select":false,"required":false,"in_onboarding":false,"options":[{"id":"21","title":"Channel","role_ids":[],"channel_ids":["200"]}]}]}
    """#
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            request.httpBody = data
        }
        NotificationCenter.default.post(name: Self.captured, object: request)
        let write = request.httpMethod != "GET"
        let failed = write && request.value(forHTTPHeaderField: "X-Onboarding-Scenario") == "failed"
        let body = failed ? #"{"message":"Try later"}"# : write
            ? #"{"guild_id":"100","user_id":"1","onboarding_responses":["11"]}"# : Self.configuration
        let response = HTTPURLResponse(url: request.url!, statusCode: failed ? 500 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
