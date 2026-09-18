import Foundation

/// Only fixed, non-identifying fields cross into the diagnostic store. Never
/// retain the metrics object: its requests, responses, and addresses are private.
struct RESTConnectionMetrics: Sendable {
    let fields: [String: JSONValue]

    init(_ metrics: URLSessionTaskMetrics, generation: Int, taskIdentifier: Int) {
        fields = [
            "generation": .number(Double(generation)),
            "local_task_number": .number(Double(taskIdentifier)),
            "task_started_at": .string(metrics.taskInterval.start.ISO8601Format()),
            "duration_ms": .number(metrics.taskInterval.duration * 1_000),
            "redirect_count": .number(Double(metrics.redirectCount)),
            "transaction_count": .number(Double(metrics.transactionMetrics.count)),
            "transactions": .array(metrics.transactionMetrics.prefix(32).map {
                .object(Self.transaction($0, start: metrics.taskInterval.start))
            }),
        ]
    }

    private static func transaction(
        _ metrics: URLSessionTaskTransactionMetrics,
        start: Date
    ) -> [String: JSONValue] {
        let networkProtocol: JSONValue = switch metrics.networkProtocolName {
        case "h3": .string("h3")
        case "h2": .string("h2")
        case "http/1.1": .string("http/1.1")
        case "http/1.0": .string("http/1.0")
        case nil: .null
        default: .string("other")
        }
        let dates: [(String, Date?)] = [
            ("fetch_start_ms", metrics.fetchStartDate),
            ("dns_start_ms", metrics.domainLookupStartDate),
            ("dns_end_ms", metrics.domainLookupEndDate),
            ("connect_start_ms", metrics.connectStartDate),
            ("connect_end_ms", metrics.connectEndDate),
            ("tls_start_ms", metrics.secureConnectionStartDate),
            ("tls_end_ms", metrics.secureConnectionEndDate),
            ("request_start_ms", metrics.requestStartDate),
            ("request_end_ms", metrics.requestEndDate),
            ("response_start_ms", metrics.responseStartDate),
            ("response_end_ms", metrics.responseEndDate),
        ]
        // Offsets preserve incomplete phases and time before fetch begins.
        // Null means unreported, not zero (including on reused connections).
        var fields = Dictionary(uniqueKeysWithValues: dates.map { name, date in
            (name, date.map { JSONValue.number($0.timeIntervalSince(start) * 1_000) } ?? .null)
        })
        fields["protocol"] = networkProtocol
        fields["reused_connection"] = .bool(metrics.isReusedConnection)
        fields["proxy_connection"] = .bool(metrics.isProxyConnection)
        fields["fetch_type"] = .number(Double(metrics.resourceFetchType.rawValue))
        fields["expensive_network"] = .bool(metrics.isExpensive)
        fields["constrained_network"] = .bool(metrics.isConstrained)
        fields["multipath"] = .bool(metrics.isMultipath)
        fields["request_bytes_sent"] = .number(Double(metrics.countOfRequestHeaderBytesSent)
            + Double(metrics.countOfRequestBodyBytesSent))
        fields["response_bytes_received"] = .number(Double(metrics.countOfResponseHeaderBytesReceived)
            + Double(metrics.countOfResponseBodyBytesReceived))
        return fields
    }
}

final class RESTConnectionMetricsDelegate: NSObject, URLSessionTaskDelegate {
    private let store: DiscordAPIDiagnosticStore
    private let method: String
    private let path: String
    private let attempt: Int
    private let generation: Int

    init(store: DiscordAPIDiagnosticStore, method: String, path: String, attempt: Int, generation: Int) {
        self.store = store
        self.method = method
        self.path = path
        self.attempt = attempt
        self.generation = generation
    }

    func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard store.capturesConnectionMetrics else { return }
        store.recordHTTPConnectionMetrics(
            RESTConnectionMetrics(metrics, generation: generation, taskIdentifier: task.taskIdentifier),
            method: method,
            path: path,
            attempt: attempt
        )
    }
}
