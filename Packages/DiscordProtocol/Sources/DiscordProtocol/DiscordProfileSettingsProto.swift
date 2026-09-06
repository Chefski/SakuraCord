import Foundation

extension DiscordRESTProvider {
    func applyProfileSettingsProto(_ encoded: String?, isPartial: Bool) {
        guard let encoded, let data = Data(base64Encoded: encoded) else { return }
        if let status = DiscordSettingsProto.statusSettings(in: data) {
            profileStatusSettings = status
            publishProfileCustomStatus()
        } else if !isPartial {
            profileStatusSettings = Data()
            publishProfileCustomStatus()
        }
        if let value = DiscordSettingsProto.profileDeveloperMode(from: data) { profileDeveloperMode = value } else if !isPartial { profileDeveloperMode = false }
    }
}

extension DiscordSettingsProto {
    static func profileDeveloperMode(from data: Data) -> Bool? {
        // Official stable607562 module873298: settings.appearance (13),
        // AppearanceSettings.developer_mode (2). Preserve field absence in patches.
        var reader = ProtoReader(data: data)
        var result: Bool?
        while let field = reader.readRawField() {
            guard field.field == 13, let payload = field.payload else { continue }
            var appearance = ProtoReader(data: payload)
            while let setting = appearance.readRawField() {
                if setting.field == 2, let value = setting.varint { result = value != 0 }
            }
        }
        return result
    }
}
