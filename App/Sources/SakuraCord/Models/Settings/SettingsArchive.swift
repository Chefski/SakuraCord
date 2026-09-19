import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let sakuraSettings = UTType(exportedAs: "dev.sakuracord.settings", conformingTo: .data)
}

/// Each entry is decoded independently so future value types cannot discard supported settings.
nonisolated struct SettingsArchive: Codable, Sendable {
    static let schema = "dev.sakuracord.settings"
    static let currentVersion = 1
    static let maximumFileSize = 4 * 1_024 * 1_024

    var version = Self.currentVersion
    var values: [String: SettingsPreferenceValue]
    var unsupportedKeys: [String] = []

    private enum CodingKeys: String, CodingKey { case schema, version, values }

    private struct PreferenceKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(values: [String: SettingsPreferenceValue]) {
        self.values = values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .schema) == Self.schema else {
            throw SettingsArchiveError.invalidFile
        }
        version = try container.decode(Int.self, forKey: .version)
        guard version > 0 else { throw SettingsArchiveError.invalidFile }
        let entries = try container.nestedContainer(keyedBy: PreferenceKey.self, forKey: .values)
        values = [:]
        for key in entries.allKeys {
            if let value = try? entries.decode(SettingsPreferenceValue.self, forKey: key) {
                values[key.stringValue] = value
            } else {
                unsupportedKeys.append(key.stringValue)
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schema, forKey: .schema)
        try container.encode(version, forKey: .version)
        try container.encode(values, forKey: .values)
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileSize else { throw SettingsArchiveError.tooLarge }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as SettingsArchiveError {
            throw error
        } catch {
            throw SettingsArchiveError.invalidFile
        }
    }
}

nonisolated enum SettingsArchiveError: LocalizedError {
    case invalidFile, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFile: "This file is not a valid SakuraCord settings file. No settings were changed."
        case .tooLarge: "This settings file is too large to import. No settings were changed."
        }
    }
}

nonisolated struct SettingsArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sakuraSettings] }
    let data: Data

    init(archive: SettingsArchive) throws { data = try archive.encodedData() }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw SettingsArchiveError.invalidFile }
        _ = try SettingsArchive.decode(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated struct SettingsImportReport {
    var importedCount = 0
    var unsupportedKeys: [String] = []
    var newerVersion = false
    var notices: [String] = []
    var needsUpdate: Bool { newerVersion || !unsupportedKeys.isEmpty }

    var message: String {
        var paragraphs = [importedCount == 1 ? "Imported 1 setting." : "Imported \(importedCount) settings."]
        if needsUpdate {
            paragraphs.append(
                "Some options are not supported by this version of SakuraCord. Your other settings were preserved. "
                    + "Update SakuraCord, then import this file again to apply the remaining options."
            )
        }
        paragraphs.append(contentsOf: notices)
        return paragraphs.joined(separator: "\n\n")
    }
}
