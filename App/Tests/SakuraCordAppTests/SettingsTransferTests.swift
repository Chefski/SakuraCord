@testable import SakuraCord
import Foundation
import Testing

@MainActor
@Test func `settings file round trip preserves registered values and export selection`() throws {
    let source = SettingsPreferenceStore(defaults: InMemoryPreferences())
    source.set(.bool(false), for: .sendWithReturn)
    source.set(.double(0.73), for: .windowOpacity)
    source.set(.strings(["example.com"]), for: .trustedDomains)
    let transfer = SettingsTransferService(preferences: source)
    let archive = transfer.export(pages: Set(SettingsTransferService.pages))
    let decoded = try SettingsArchive.decode(archive.encodedData())
    let target = SettingsPreferenceStore(defaults: InMemoryPreferences())
    let report = SettingsTransferService(preferences: target).importPreferences(decoded)
    #expect(!report.needsUpdate)
    #expect(report.importedCount == archive.values.count)
    for (key, value) in archive.values {
        #expect(target.value(for: SettingsControlID(rawValue: key)) == value)
    }
    let selected = transfer.export(pages: [.appearance])
    #expect(selected.values[SettingsControlID.windowOpacity.rawValue] == .double(0.73))
    #expect(selected.values[SettingsControlID.sendWithReturn.rawValue] == nil)
    #expect(transfer.export(pages: []).values.isEmpty)
}

@MainActor
@Test func `future and malformed options do not block supported imports or overwrite existing settings`() throws {
    let defaults = InMemoryPreferences()
    defaults.set("private", forKey: "credential")
    let store = SettingsPreferenceStore(defaults: defaults)
    store.set(.double(0.6), for: .windowOpacity)
    store.set(.string(AppColorScheme.dark.rawValue), for: .appColorScheme)
    let values: [String: Any] = [
        SettingsControlID.sendWithReturn.rawValue: ["type": "bool", "value": false],
        SettingsControlID.windowOpacity.rawValue: ["type": "bool", "value": true],
        SettingsControlID.appColorScheme.rawValue: ["type": "string", "value": "future-theme"],
        SettingsControlID.voiceInputVolume.rawValue: ["type": "double", "value": 99],
        SettingsControlID.spellCheck.rawValue: ["type": "future-type", "value": [:]],
        "future-option": ["type": "bool", "value": true],
        "credential": ["type": "string", "value": "replacement"],
        SettingsControlID.mediaCacheLastCleared.rawValue: ["type": "double", "value": 10],
    ]
    let data = try JSONSerialization.data(withJSONObject: ["schema": SettingsArchive.schema, "version": 99, "values": values])
    let archive = try SettingsArchive.decode(data)
    let report = SettingsTransferService(preferences: store).importPreferences(archive)
    #expect(report.needsUpdate)
    #expect(report.importedCount == 1)
    #expect(report.unsupportedKeys.count == 7)
    #expect(store.value(for: .sendWithReturn) == .bool(false))
    #expect(store.value(for: .windowOpacity) == .double(0.6))
    #expect(store.value(for: .appColorScheme) == .string(AppColorScheme.dark.rawValue))
    #expect(defaults.string(forKey: "credential") == "private")
    #expect(defaults.object(forKey: "settings.storage.mediaCacheLastCleared") == nil)
    #expect(throws: SettingsArchiveError.self) { try SettingsArchive.decode(Data("{}".utf8)) }
    #expect(throws: SettingsArchiveError.self) { try SettingsArchive.decode(Data(repeating: 0, count: SettingsArchive.maximumFileSize + 1)) }
}

@MainActor
@Test func `shortcut imports allow swaps and preserve assignments when a merge conflicts`() throws {
    let store = SettingsPreferenceStore(defaults: InMemoryPreferences())
    let actions = KeyboardShortcutAction.allCases.filter { $0.defaultShortcut != nil }
    let first = try #require(actions.first)
    let second = try #require(actions.dropFirst().first)
    let firstChord = try #require(first.defaultShortcut)
    let secondChord = try #require(second.defaultShortcut)
    let service = SettingsTransferService(preferences: store)
    let conflict = service.importPreferences(SettingsArchive(values: [first.controlID.rawValue: .string(secondChord.storageValue)]))
    #expect(conflict.importedCount == 0)
    #expect(conflict.needsUpdate)
    #expect(store.value(for: first.controlID) == .string(firstChord.storageValue))
    let swap = service.importPreferences(SettingsArchive(values: [
        first.controlID.rawValue: .string(secondChord.storageValue),
        second.controlID.rawValue: .string(firstChord.storageValue),
    ]))
    #expect(swap.importedCount == 2)
    #expect(!swap.needsUpdate)
    let loaded = KeyboardShortcutSettingsStore(preferences: store)
    #expect(loaded.shortcut(for: first) == secondChord)
    #expect(loaded.shortcut(for: second) == firstChord)
}
