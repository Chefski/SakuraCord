import DiscordProtocol
@testable import SakuraCord
import SakuraCordModels
import Testing

@MainActor
@Test func `clearing profile text preserves explicit empty values and restoring it removes the draft`() async throws {
    let model = AppModel(launchMode: .offlineTesting, provider: MockChatProvider())
    await model.start()
    let editor = ProfileEditorState(model: model)
    await editor.load()
    let snapshot = try #require(editor.snapshot)
    let name = try #require(snapshot.identity.name.value)
    let bio = try #require(snapshot.metadata.bio.value)
    let pronouns = try #require(snapshot.metadata.pronouns.value)
    try #require(!name.isEmpty && !bio.isEmpty && !pronouns.isEmpty)

    editor.name = ""
    editor.bio = ""
    editor.pronouns = ""
    #expect(editor.changes.identity.name == .set(""))
    #expect(editor.changes.metadata.bio == .set(""))
    #expect(editor.changes.metadata.pronouns == .set(""))
    #expect(editor.canSave)

    await editor.loadIfNeeded(refreshExisting: true)
    #expect(editor.name.isEmpty && editor.bio.isEmpty && editor.pronouns.isEmpty)
    #expect(editor.hasChanges)

    editor.name = name
    editor.bio = bio
    editor.pronouns = pronouns
    #expect(!editor.hasChanges)

    await editor.load(.server(GuildID(rawValue: 100)))
    _ = try #require(editor.snapshot)
    editor.name = ""
    editor.bio = ""
    editor.pronouns = ""
    #expect(!editor.hasChanges)
    await editor.loadIfNeeded(refreshExisting: true)
    #expect(editor.scope == .server(GuildID(rawValue: 100)))
    #expect(!editor.hasChanges)
}
