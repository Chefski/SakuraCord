import AppKit
import Darwin

enum CurrentMacHardware {
    /// Read once locally; this identifier is never added to Discord account data.
    static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var value = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return nil }
        return String(bytes: value.prefix { $0 != 0 }, encoding: .utf8)
    }()

    /// Exact model identifiers share a resource when their supplied icons are identical.
    static let icon: NSImage? = {
        guard let modelIdentifier,
              let catalogURL = #bundle.url(forResource: "MacHardwareModels", withExtension: "json"),
              let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONDecoder().decode([String: String].self, from: data),
              let resourceName = catalog[modelIdentifier],
              let url = #bundle.url(forResource: resourceName, withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }()
}
