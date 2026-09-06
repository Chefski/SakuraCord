import Foundation

/// The official editor independently submits widgets after its profile fields.
/// Keep both failures visible when more than one save group fails.
public struct ProfileSaveFailure: LocalizedError, Sendable {
    public let messages: [String]
    public let fields: [String: [String]]
    public let requiresReload: Bool

    public init(messages: [String], fields: [String: [String]], requiresReload: Bool) {
        self.messages = messages
        self.fields = fields
        self.requiresReload = requiresReload
    }

    public var errorDescription: String? { messages.joined(separator: "\n") }
}
