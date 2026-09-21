import Foundation

public struct AttachmentCompactionOptions: Equatable, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        case high, balanced, small

        var imageQuality: Double {
            switch self {
            case .high: 0.9
            case .balanced: 0.75
            case .small: 0.55
            }
        }

        var maximumImageDimension: Int {
            switch self {
            case .high: 4096
            case .balanced: 2560
            case .small: 1600
            }
        }
    }

    public var quality: Quality

    public init(quality: Quality = .balanced) {
        self.quality = quality
    }
}

public protocol AttachmentCompacting: Sendable {
    func compact(_ source: URL, in directory: URL, options: AttachmentCompactionOptions) async throws -> URL
}
