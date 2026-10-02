import Foundation

/// A link to sakuracord.app/report with this Mac's diagnostics filled in.
/// Nothing is sent until the person reviews the form and submits it.
nonisolated struct IssueReportLink: Equatable, Sendable {
    enum Kind: String, Sendable {
        case bug
        case feature
    }

    static let trackerURL = URL(string: "https://sakuracord.app/tracker")!

    let kind: Kind
    let appVersion: String?
    let macOSVersion: String
    let macModel: String?

    var url: URL {
        var components = URLComponents(string: "https://sakuracord.app/report")!
        var items = [URLQueryItem(name: "type", value: kind.rawValue)]
        if let appVersion {
            items.append(URLQueryItem(name: "version", value: appVersion))
        }
        if kind == .bug {
            items.append(URLQueryItem(name: "macos", value: macOSVersion))
            if let macModel {
                items.append(URLQueryItem(name: "mac", value: macModel))
            }
        }
        components.queryItems = items
        return components.url!
    }

    @MainActor
    static func current(_ kind: Kind, processInfo: ProcessInfo = .processInfo) -> Self {
        let description = processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
        return Self(
            kind: kind,
            appVersion: AboutVersionInformation().displayVersion,
            macOSVersion: "macOS \(description)",
            macModel: CurrentMacHardware.modelIdentifier
        )
    }
}
