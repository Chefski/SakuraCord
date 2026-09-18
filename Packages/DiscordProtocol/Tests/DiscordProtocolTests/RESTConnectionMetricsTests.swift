@testable import DiscordProtocol
import Foundation
import Testing

@Test func `connection diagnostics require opt in and discard private transport fields`() throws {
    let metrics = RESTConnectionMetrics(MetricsFixture(), generation: 3, taskIdentifier: 7)
    let store = DiscordAPIDiagnosticStore(capturesPayloadDetails: true)
    store.enablesPanicSave = true
    #expect(!store.capturesConnectionMetrics)
    store.recordHTTPConnectionMetrics(metrics, method: "GET", path: "/channels/123/messages", attempt: 1)
    #expect(store.retainedEntryCount == 0)

    store.capturesPayloadDetails = false
    store.capturesConnectionMetrics = true
    store.recordHTTPConnectionMetrics(metrics, method: "GET", path: "/channels/123/messages", attempt: 1)
    store.recordRESTSessionReplacement(previousGeneration: 3, generation: 4)
    let text = try #require(String(data: store.exportData(), encoding: .utf8))
    #expect(text.contains("http_connection"))
    #expect(text.contains("connection_pool_replaced"))
    #expect(text.contains(#""protocol":"other""#))
    #expect(text.contains(#""reused_connection":true"#))
    #expect(text.contains(#""dns_start_ms":250"#))
    #expect(text.contains(#""dns_end_ms":null"#))
    #expect(text.contains(#""generation":3"#))
    #expect(text.contains("/channels/<redacted-id>/messages"))
    #expect(!text.contains("private"))
    #expect(!text.contains("192.0.2."))
    #expect(!text.contains("/channels/123"))

    // An already-created delegate/snapshot cannot append after opt-out.
    store.capturesConnectionMetrics = false
    store.recordHTTPConnectionMetrics(metrics, method: "GET", path: "/auth/sessions", attempt: 2)
    store.recordRESTSessionReplacement(previousGeneration: 4, generation: 5)
    #expect(store.retainedEntryCount == 2)
}

private final class MetricsFixture: URLSessionTaskMetrics, @unchecked Sendable {
    override var taskInterval: DateInterval { DateInterval(start: Date(timeIntervalSince1970: 0), duration: 30) }
    override var redirectCount: Int { 0 }
    override var transactionMetrics: [URLSessionTaskTransactionMetrics] { [TransactionFixture()] }
}

private final class TransactionFixture: URLSessionTaskTransactionMetrics, @unchecked Sendable {
    override var request: URLRequest {
        var request = URLRequest(url: URL(string: "https://private.example/?token=private-token")!)
        request.setValue("private-credential", forHTTPHeaderField: "Authorization")
        return request
    }

    override var localAddress: String? { "192.0.2.1" }
    override var remoteAddress: String? { "192.0.2.2" }
    override var networkProtocolName: String? { "private-protocol-value" }
    override var isReusedConnection: Bool { true }
    override var domainLookupStartDate: Date? { Date(timeIntervalSince1970: 0.25) }
    override var domainLookupEndDate: Date? { nil }
}
