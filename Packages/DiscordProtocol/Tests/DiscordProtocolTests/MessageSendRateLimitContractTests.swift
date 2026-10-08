@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Synchronization
import Testing

/// The fixture's counters are process-wide, so these cases cannot overlap.
@Suite(.serialized) struct MessageSendRateLimitContractTests {
    @Test func `rate-limited message send replays its nonce after the server cooldown`() async throws {
        MessageSendRateLimitURLProtocol.reset(rateLimitedAttempts: 2)
        let provider = MessageSendRateLimitURLProtocol.provider()
        let draft = SendMessageDraft(channelID: ChannelID(rawValue: 200), content: "queued")

        let message = try await provider.send(draft)

        #expect(message.nonce == draft.nonce)
        let bodies = MessageSendRateLimitURLProtocol.bodies.withLock { $0 }
        #expect(bodies.count == 3)
        #expect(bodies.allSatisfy { $0.nonce == draft.nonce && $0.enforcesNonce })
        await provider.disconnect()
    }

    @Test func `persistent message rate limit stops at the send attempt budget`() async throws {
        MessageSendRateLimitURLProtocol.reset(rateLimitedAttempts: .max)
        let provider = MessageSendRateLimitURLProtocol.provider()

        await #expect(throws: ChatProviderError.self) {
            try await provider.send(SendMessageDraft(channelID: ChannelID(rawValue: 200), content: "queued"))
        }
        #expect(
            MessageSendRateLimitURLProtocol.bodies.withLock { $0.count }
                == DiscordRESTProvider.maximumMessageSendAttempts
        )
        await provider.disconnect()
    }
}

private final class MessageSendRateLimitURLProtocol: URLProtocol, @unchecked Sendable {
    struct SentBody: Sendable {
        let nonce: String?
        let enforcesNonce: Bool
    }

    static let bodies = Mutex<[SentBody]>([])
    static let rateLimitedAttempts = Mutex(0)

    static func reset(rateLimitedAttempts count: Int) {
        bodies.withLock { $0 = [] }
        rateLimitedAttempts.withLock { $0 = count }
    }

    static func provider() -> DiscordRESTProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return DiscordRESTProvider(
            credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "1"),
            session: URLSession(configuration: configuration)
        )
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.requestBody(request)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let sent = SentBody(nonce: body["nonce"] as? String, enforcesNonce: body["enforce_nonce"] as? Bool == true)
        Self.bodies.withLock { $0.append(sent) }
        let isRateLimited = Self.rateLimitedAttempts.withLock { remaining in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        let nonce = sent.nonce ?? ""
        let (status, data) = isRateLimited
            ? (429, Data(#"{"message":"You are being rate limited.","retry_after":0.01,"global":false}"#.utf8))
            : (200, Data("""
            {"id":"50","channel_id":"200","author":{"id":"1","username":"tester","global_name":"Tester","avatar":null},
            "content":"queued","timestamp":"2026-10-09T12:00:00.000Z","edited_timestamp":null,
            "type":0,"flags":0,"attachments":[],"reactions":[],"nonce":"\(nonce)"}
            """.utf8))
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
