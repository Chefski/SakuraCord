import Foundation

public struct ProfileValidationError: LocalizedError, Equatable, Sendable {
    public var fields: [String: [String]]

    public init(fields: [String: [String]]) { self.fields = fields }

    public var errorDescription: String? {
        fields.keys.sorted().flatMap { fields[$0] ?? [] }.joined(separator: "\n")
    }
}
