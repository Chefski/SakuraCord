import Foundation

/// Applies the same bounded redaction policy to parsed Gateway values and JSON
/// responses. Policy caches live only for one payload; no raw values are retained.
struct DiscordDiagnosticSanitizer {
    private enum ValuePolicy {
        case sensitive, identifier, safeString, other
    }

    private struct KeyPolicy {
        let value: ValuePolicy
        let isIdentifier: Bool
    }

    struct WebSocketPayload: Decodable {
        let value: JSONValue
        let operation: String?

        init(from decoder: any Decoder) throws {
            let raw = try JSONValue(from: decoder)
            if case let .object(fields) = raw, case let .string(op) = fields["op"] {
                operation = op
            } else {
                operation = nil
            }
            value = DiscordDiagnosticSanitizer.sanitize(raw)
        }
    }

    private var keyPolicies: [String: KeyPolicy] = [:]

    static func decode(_ data: Data) throws -> JSONValue {
        sanitize(try JSONDecoder().decode(JSONValue.self, from: data))
    }

    static func sanitize(_ value: JSONValue) -> JSONValue {
        var sanitizer = Self()
        return sanitizer.sanitize(value, policy: .other, depth: 0)
    }

    private static let sensitiveKeys: Set<String> = [
        "authorization", "cookie", "set_cookie", "token", "access_token",
        "refresh_token", "password", "login", "email", "phone", "content",
        "username", "global_name", "display_name", "nick", "nickname", "name",
        "topic", "title", "description", "bio", "state", "custom_status",
        "filename", "uploaded_filename", "url", "proxy_url", "avatar", "banner",
        "icon", "splash", "session_id", "resume_gateway_url", "fingerprint",
        "analytics_token", "captcha_key", "captcha_rqdata", "captcha_rqtoken",
        "captcha_session_id", "ticket", "secret", "secret_key", "key",
        "public_key", "private_key", "encryption_key", "reason", "message",
        "nonce_proof", "encrypted_nonce", "encrypted_user_payload",
        "encoded_public_key",
    ]

    private static let safeStringKeys: Set<String> = [
        "status", "type", "event", "locale", "method", "platform",
        "release_channel", "os", "browser", "device", "scope",
    ]

    private static let maximumCollectionCount = 100
    private static let maximumPayloadDepth = 10

    private mutating func keyPolicy(_ key: String) -> KeyPolicy {
        if let cached = keyPolicies[key] { return cached }
        let lowercased = key.lowercased()
        let normalized = lowercased.contains("-")
            ? lowercased.replacingOccurrences(of: "-", with: "_") : lowercased
        let value: ValuePolicy
        if Self.sensitiveKeys.contains(normalized) {
            value = .sensitive
        } else if Self.isIDKey(normalized) || normalized == "nonce" {
            value = .identifier
        } else if Self.safeStringKeys.contains(normalized) {
            value = .safeString
        } else {
            value = .other
        }
        let policy = KeyPolicy(value: value, isIdentifier: Self.isIdentifierString(key))
        keyPolicies[key] = policy
        return policy
    }

    private static func redaction(policy: ValuePolicy, depth: Int) -> JSONValue? {
        if depth >= maximumPayloadDepth { return .string("<truncated-depth>") }
        switch policy {
        case .sensitive: return .string("<redacted>")
        case .identifier: return .string("<redacted-id>")
        case .safeString, .other: return nil
        }
    }

    private static func string(_ value: String, policy: ValuePolicy) -> JSONValue {
        policy == .safeString ? .string(String(value.prefix(256))) : .string("<redacted>")
    }

    private mutating func sanitize(_ value: JSONValue, policy: ValuePolicy, depth: Int) -> JSONValue {
        if let redaction = Self.redaction(policy: policy, depth: depth) { return redaction }
        switch value {
        case let .object(object):
            let keys = object.keys.sorted().prefix(Self.maximumCollectionCount)
            var result: [String: JSONValue] = [:]
            result.reserveCapacity(keys.count)
            for (index, key) in keys.enumerated() {
                let keyPolicy = keyPolicy(key)
                let retainedKey = keyPolicy.isIdentifier ? "<redacted-id-key-\(index + 1)>" : key
                if let value = object[key] {
                    result[retainedKey] = sanitize(value, policy: keyPolicy.value, depth: depth + 1)
                }
            }
            Self.recordTruncatedFields(total: object.count, result: &result)
            return .object(result)
        case let .array(values):
            var retained = values.prefix(Self.maximumCollectionCount).map {
                sanitize($0, policy: policy, depth: depth + 1)
            }
            Self.recordTruncatedItems(total: values.count, result: &retained)
            return .array(retained)
        case let .string(value): return Self.string(value, policy: policy)
        case .number, .bool, .null: return value
        }
    }

    private static func recordTruncatedFields(total: Int, result: inout [String: JSONValue]) {
        if total > result.count {
            result["truncated_field_count"] = .number(Double(total - result.count))
        }
    }

    private static func recordTruncatedItems(total: Int, result: inout [JSONValue]) {
        if total > result.count {
            result.append(.object(["truncated_count": .number(Double(total - result.count))]))
        }
    }

    static func isIdentifierString(_ value: String) -> Bool {
        !value.isEmpty && (value.allSatisfy(\.isNumber) || UUID(uuidString: value) != nil)
    }

    static func isIDKey(_ key: String) -> Bool {
        key == "id" || key.hasSuffix("_id") || key.hasSuffix("_ids") || key == "sequence"
    }
}
