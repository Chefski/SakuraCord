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

    /// StatusSettings.status (1) is a StringValue wrapper and
    /// status_expires_at_ms (4) a fixed64. Like the first-party client, an
    /// unset, unrecognised or expired status resolves to Online.
    static func presenceStatus(in statusSettings: Data, now: Date = .now) -> PresenceStatus {
        var reader = ProtoReader(data: statusSettings)
        var status = PresenceStatus.online
        var expiresAtMs: UInt64 = 0
        while let tag = reader.readTag() {
            switch (tag.field, tag.wireType) {
            case (1, 2):
                var wrapper = ProtoReader(data: reader.readLengthDelimited() ?? Data())
                while let field = wrapper.readRawField() {
                    guard field.field == 1, let payload = field.payload else { continue }
                    status = String(data: payload, encoding: .utf8)
                        .flatMap(PresenceStatus.init(rawValue:)) ?? .online
                }
            case (4, 1): expiresAtMs = reader.readFixed64() ?? 0
            default: if !reader.skip(wireType: tag.wireType) { return .online }
            }
        }
        if status == .offline { return .online }
        if expiresAtMs != 0, Double(expiresAtMs) / 1000 <= now.timeIntervalSince1970 { return .online }
        return status
    }

    /// settings-proto/1 replaces the complete StatusSettings message. An
    /// untimed status omits status_expires_at_ms; status_created_at_ms (5, a
    /// varint wrapper) is renewed only when the stored status changes.
    static func updatingPresenceStatus(_ status: PresenceStatus, in current: Data, now: Date = .now) -> Data {
        var reader = ProtoReader(data: current)
        var fields: [(number: Int, bytes: Data)] = []
        var storedStatus: Data?
        var hasCreationTime = false
        while let field = reader.readRawField() {
            if field.field == 1 { storedStatus = field.payload }
            if field.field == 5 { hasCreationTime = true }
            if field.field != 1, field.field != 4 { fields.append((field.field, field.raw)) }
        }
        let wrapper = protoLengthDelimitedField(1, Data(status.rawValue.utf8))
        fields.append((1, protoLengthDelimitedField(1, wrapper)))
        if storedStatus != wrapper || !hasCreationTime {
            fields.removeAll { $0.number == 5 }
            let createdAt = protoVarintField(1, UInt64(now.timeIntervalSince1970 * 1000))
            fields.append((5, protoLengthDelimitedField(5, createdAt)))
        }
        return statusSettingsPatch(fields)
    }

    private static func statusSettingsPatch(_ fields: [(number: Int, bytes: Data)]) -> Data {
        protoLengthDelimitedField(11, fields.sorted { $0.number < $1.number }.reduce(into: Data()) { $0.append($1.bytes) })
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
        return statusSettingsPatch(fields)
    }

    private static func statusFixed64Field(_ field: Int, _ value: UInt64) -> Data {
        var result = Data([UInt8(field << 3 | 1)])
        for offset in 0 ..< 8 { result.append(UInt8(truncatingIfNeeded: value >> UInt64(offset * 8))) }
        return result
    }
}
