@testable import DiscordProtocol
import Foundation
import libzstd
import Testing

/// Flush each message without ending the connection's shared zstd frame.
final class GatewayTestZstdStream {
    private let context: OpaquePointer

    init() throws {
        context = try #require(ZSTD_createCCtx())
    }

    deinit { ZSTD_freeCCtx(context) }

    func compress(_ data: Data) throws -> Data {
        var output = Data(count: ZSTD_compressBound(data.count))
        let size = try data.withUnsafeBytes { source in
            try output.withUnsafeMutableBytes { destination in
                var input = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: 0)
                var buffer = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                let remaining = ZSTD_compressStream2(context, &buffer, &input, ZSTD_e_flush)
                try #require(ZSTD_isError(remaining) == 0 && remaining == 0 && input.pos == input.size)
                return buffer.pos
            }
        }
        output.count = size
        return output
    }
}

func largeGatewayReadyEnvelope() -> GatewayEnvelope {
    GatewayEnvelope(op: 0, data: .object([
        "session_id": .string("large-ready-session"),
        "resume_gateway_url": .string("wss://gateway.discord.gg"),
        "user": .object(["id": .string("1"), "username": .string("fixture"), "discriminator": .string("0")]),
        "guilds": .array([]),
        // Unknown fields still pass through the production ETF parser. Keep
        // each field small; the regression is the total bootstrap payload.
        "fixture_padding": .array(Array(repeating: .string(String(repeating: "x", count: 256 * 1024)), count: 80))
    ]), sequence: 1, eventName: "READY")
}
