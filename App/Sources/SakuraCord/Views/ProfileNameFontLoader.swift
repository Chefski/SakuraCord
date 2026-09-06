import AppKit
import CoreText
import SakuraCordModels

/// Loads the captured first-party font bytes through the existing media cache.
/// Data-backed descriptors avoid installing or registering fonts on the Mac.
@MainActor
final class ProfileNameFontLoader {
    static let shared = ProfileNameFontLoader()

    private var descriptors: [URL: CTFontDescriptor] = [:]

    func font(_ definition: ProfileNameFont, size: CGFloat) async throws -> NSFont {
        guard let url = definition.assetURL else {
            return .systemFont(ofSize: size, weight: .bold)
        }
        let descriptor: CTFontDescriptor
        if let cached = descriptors[url] {
            descriptor = cached
        } else {
            // The media loader coalesces concurrent downloads. Recheck after
            // suspension so only one caller decodes a descriptor on this actor.
            let data = try await SharedMediaDataLoader.shared.data(for: url)
            try Task.checkCancellation()
            if let cached = descriptors[url] {
                descriptor = cached
            } else {
                let values = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor]
                guard let value = values?.first,
                      CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(value, 24, nil)) as String
                        == definition.postScriptName
                else { throw URLError(.cannotDecodeContentData) }
                descriptor = value
                descriptors[url] = value
            }
        }
        try Task.checkCancellation()
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
}
