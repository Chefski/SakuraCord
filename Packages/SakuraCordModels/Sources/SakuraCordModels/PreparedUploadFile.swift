import Foundation

/// An upload copy and the temporary directory owned by its preparation step.
public struct PreparedUploadFile: Sendable {
    public let url: URL
    private let temporaryDirectory: URL?

    public init(url: URL, temporaryDirectory: URL? = nil) {
        self.url = url
        self.temporaryDirectory = temporaryDirectory
    }

    public func discard() {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }
}
