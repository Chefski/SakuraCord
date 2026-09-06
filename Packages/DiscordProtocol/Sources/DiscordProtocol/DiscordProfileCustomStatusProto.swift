import Foundation
import SakuraCordModels

extension DiscordSettingsProto {
    static func statusSettings(in data: Data) -> Data? {
        var reader = ProtoReader(data: data)
        var result: Data?
        while let field = reader.readRawField() {
            if field.field == 11 { result = field.payload }
        }
        return result
    }

    static func customStatus(in statusSettings: Data) -> ProfileCustomStatus? {
        var statusReader = ProtoReader(data: statusSettings)
        var payload: Data?
        while let field = statusReader.readRawField() {
            if field.field == 2 { payload = field.payload }
        }
        guard let payload else { return nil }
        var reader = ProtoReader(data: payload)
        var status = ProfileCustomStatus(text: "")
        while let tag = reader.readTag() {
            switch (tag.field, tag.wireType) {
            case (1, 2): status.text = reader.readLengthDelimited().flatMap { String(data: $0, encoding: .utf8) } ?? ""
            case (2, 1): status.emojiID = reader.readFixed64().flatMap { $0 == 0 ? nil : String($0) }
            case (3, 2): status.emojiName = reader.readLengthDelimited().flatMap { String(data: $0, encoding: .utf8) }
            case (4, 1): status.expiresAt = reader.readFixed64().flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: Double($0) / 1000) }
            case (5, 1): status.createdAt = reader.readFixed64().flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: Double($0) / 1000) }
            default: if !reader.skip(wireType: tag.wireType) { return nil }
            }
        }
        return status
    }

    /// settings-proto/1 replaces the complete StatusSettings message. Retain
    /// presence, its independent expiry/creation time, game visibility and unknown
    /// fields. Clearing omits custom_status rather than sending an empty message.
    static func updatingCustomStatus(_ status: ProfileCustomStatus?, in current: Data) -> Data {
        var reader = ProtoReader(data: current)
        var fields: [(number: Int, bytes: Data)] = []
        while let field = reader.readRawField() {
            if field.field != 2 { fields.append((field.field, field.raw)) }
        }
        if let status {
            var payload = Data()
            if !status.text.isEmpty { payload.append(protoLengthDelimitedField(1, Data(status.text.utf8))) }
            if let emojiID = status.emojiID.flatMap(UInt64.init), emojiID != 0 { payload.append(statusFixed64Field(2, emojiID)) }
            if let name = status.emojiName, !name.isEmpty { payload.append(protoLengthDelimitedField(3, Data(name.utf8))) }
            if let expiry = status.expiresAt { payload.append(statusFixed64Field(4, UInt64(expiry.timeIntervalSince1970 * 1000))) }
            if let createdAt = status.createdAt { payload.append(statusFixed64Field(5, UInt64(createdAt.timeIntervalSince1970 * 1000))) }
            fields.append((2, protoLengthDelimitedField(2, payload)))
        }
        return protoLengthDelimitedField(11, fields.sorted { $0.number < $1.number }.reduce(into: Data()) { $0.append($1.bytes) })
    }

    private static func statusFixed64Field(_ field: Int, _ value: UInt64) -> Data {
        var result = Data([UInt8(field << 3 | 1)])
        for offset in 0 ..< 8 { result.append(UInt8(truncatingIfNeeded: value >> UInt64(offset * 8))) }
        return result
    }
}
