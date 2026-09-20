import Foundation

enum GatewaySessionError: Error, Equatable, CustomNSError {
    case unsupportedWebSocketMessage
    case malformedPayload
    case compressedBufferLimitExceeded(limit: Int, observed: Int)
    case decompressedPayloadLimitExceeded(limit: Int, observed: Int)
    case decompressionFailed
    case stopped

    static var errorDomain: String { "DiscordProtocol.GatewaySessionError" }

    // Preserve the codes in existing support exports. Associated values must
    // not change Swift's formerly synthesized NSError case numbering.
    var errorCode: Int {
        switch self {
        case .unsupportedWebSocketMessage: 0
        case .malformedPayload: 1
        case .compressedBufferLimitExceeded: 2
        case .decompressedPayloadLimitExceeded: 3
        case .decompressionFailed: 4
        case .stopped: 5
        }
    }

    var diagnosticIntegers: [String: Int] {
        switch self {
        case let .compressedBufferLimitExceeded(limit, observed),
             let .decompressedPayloadLimitExceeded(limit, observed):
            // Observed bytes are a lower bound: decoding stops at the limit.
            ["payload_limit_bytes": limit, "observed_payload_bytes": observed]
        default: [:]
        }
    }

    var payloadLimitMessage: String? {
        switch self {
        case .compressedBufferLimitExceeded, .decompressedPayloadLimitExceeded:
            "SakuraCord couldn't load this account because Discord's data exceeded its size limit."
        default: nil
        }
    }
}
