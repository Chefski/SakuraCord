import Foundation

extension DiscordSettingsProto {
    /// Each supplied top-level settings message replaces that field. A newer
    /// partial update must protect its fields without discarding older full
    /// snapshot fields that it never supplied.
    static func mergingRevisionedSettings(
        _ incoming: Data,
        into current: Data,
        isPartial: Bool,
        fieldVersions: inout [Int: UInt32]
    ) -> Data {
        let supplied = settingsFields(in: incoming)
        var result = settingsFields(in: current)
        let fields = isPartial ? Set(supplied.keys)
            : Set(supplied.keys).union(result.keys).union(fieldVersions.keys)
        let version = dataVersion(in: incoming)
        for field in fields {
            if let version, let existing = fieldVersions[field], version < existing { continue }
            result[field] = supplied[field]
            if let version { fieldVersions[field] = version }
        }
        return result.keys.sorted().reduce(into: Data()) { data, field in
            for raw in result[field] ?? [] { data.append(raw) }
        }
    }

    private static func settingsFields(in data: Data) -> [Int: [Data]] {
        var reader = ProtoReader(data: data)
        var result: [Int: [Data]] = [:]
        while let field = reader.readRawField() { result[field.field, default: []].append(field.raw) }
        return result
    }
}
