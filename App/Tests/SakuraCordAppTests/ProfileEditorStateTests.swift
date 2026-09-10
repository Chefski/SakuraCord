import DiscordProtocol
import Foundation
@testable import SakuraCord
import SakuraCordModels
import Testing

@MainActor
@Test func `server tag drafts use the same account identity in main and server editors`() async throws {
    let model = AppModel(launchMode: .offlineTesting, provider: MockChatProvider())
    await model.start()
    let editor = ProfileEditorState(model: model)
    let tag = PrimaryGuildIdentity(guildID: GuildID(rawValue: 999), tag: "TEST")
    for scope in [ProfileEditingScope.main, .server(GuildID(rawValue: 100))] {
        await editor.load(scope)
        _ = try #require(editor.snapshot)
        editor.setServerTag(tag)
        #expect(editor.changes.serverTag == .set(GuildID(rawValue: 999)))
        #expect(editor.preview?.user.primaryGuild == tag)
        #expect(editor.canSave)
        editor.resetDraft()
        #expect(!editor.changes.serverTag.isChanged)
    }
}

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

@MainActor
@Test func `profile editing reuses fresh scopes and refreshes stale data without discarding edits`() async throws {
    let provider = ProfileEditorCacheProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()
    var time = ContinuousClock.now
    let editor = ProfileEditorState(model: model, now: { time })
    let server = ProfileEditingScope.server(GuildID(rawValue: 100))
    await editor.load()
    await editor.load(server)
    let initialGeneration = editor.draftGeneration
    await editor.loadIfNeeded(refreshExisting: true)
    #expect(editor.draftGeneration == initialGeneration)
    for _ in 0 ..< 5 {
        await editor.load(.main)
        await editor.load(server)
        await editor.loadIfNeeded(refreshExisting: true)
    }
    #expect(await provider.reads == [.main, server])
    time = time.advanced(by: .seconds(60))
    await provider.suspendNextRead()
    let refresh = Task { await editor.load(server) }
    await provider.waitForRead()
    #expect(editor.snapshot?.scope == server)
    #expect(!editor.isLoading)
    // Reentering the same scope during a refresh must not send another request.
    await editor.load(server)
    editor.name = "Unsaved nickname"
    // A late profile read must finish before a save can replace its baseline.
    #expect(!editor.canSave)
    await provider.resumeRead()
    await refresh.value
    #expect(editor.name == "Unsaved nickname")
    #expect(editor.canSave)
    #expect(editor.hasChanges)
    #expect(await provider.reads == [.main, server, server])
    await editor.load(.main)
    #expect(editor.scope == server)
    #expect(editor.showsUnsavedReminder)
    editor.resetDraft()
    await editor.load(server)
    #expect(!editor.hasChanges)
    #expect(await provider.reads == [.main, server, server])
}

@MainActor
@Test func `widget drafts remain removable and reordering preserves the exact save order`() async throws {
    let first = ProfileWidget(serverID: "1", content: .application(id: "10"))
    let second = ProfileWidget(serverID: "2", content: .application(id: "20"))
    let third = ProfileWidget(serverID: "3", content: .application(id: "30"))
    let provider = ProfileEditorCacheProvider(widgets: [first, second, third])
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()
    let editor = ProfileEditorState(model: model)
    await editor.load()
    let blank = ProfileWidget(content: .personal(ProfilePersonalWidget(sections: [.cover(ProfileWidgetCover())])))
    editor.addWidget(blank)
    #expect(editor.widgets.first?.id == blank.id)
    #expect(!editor.hasChanges)
    editor.removeWidget(id: blank.id)
    #expect(editor.widgets == [first, second, third])
    #expect(!editor.hasChanges)

    editor.addWidget(blank)
    editor.updateWidgetCover(id: blank.id, section: 0) { $0.title = "Partial content" }
    #expect(editor.hasChanges && !editor.canSave)
    editor.updatePersonalWidget(id: blank.id) { $0.header = "About" }
    #expect(editor.canSave)
    editor.moveWidgets([blank.id, third.id], before: second.id)
    #expect(editor.widgets.map(\.id) == [first.id, blank.id, third.id, second.id])
    #expect(editor.changes.widgets?.map(\.id) == editor.widgets.map(\.id))
    // Reordering back to the saved baseline removes the mutation, even when
    // the board still contains an empty local placeholder.
    editor.updateWidgetCover(id: blank.id, section: 0) { $0.title = "" }
    editor.moveWidgets([second.id], before: third.id)
    #expect(!editor.hasChanges)
    #expect(editor.widgets.contains { $0.id == blank.id })
    editor.moveWidgets([first.id], before: nil)
    #expect(editor.changes.widgets?.map(\.id) == [second.id, third.id, first.id])
    let beforeInvalidMove = editor.widgets
    editor.moveWidgets([third.id], before: "removed-during-drag")
    editor.moveWidgets([third.id], before: third.id)
    #expect(editor.widgets == beforeInvalidMove)
    editor.resetDraft()
    #expect(editor.widgets == [first, second, third])
    #expect(!editor.hasChanges)
}

@MainActor
@Test func `external profile changes refresh immediately while preserving the preview and unsaved edits`() async throws {
    let widget = ProfileWidget(serverID: "1", content: .application(id: "10"))
    let provider = ProfileEditorCacheProvider(widgets: [widget])
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()
    let editor = ProfileEditorState(model: model)
    await editor.load()
    let original = try #require(editor.preview)
    await provider.replaceWidgets([])
    await provider.suspendNextRead()
    editor.invalidateSnapshot()
    let refresh = Task { await editor.refreshIfNeeded() }
    await provider.waitForRead()
    #expect(editor.preview == original)
    #expect(!editor.isLoading)
    await provider.resumeRead()
    await refresh.value
    #expect(editor.widgets.isEmpty)
    #expect(await provider.reads == [.main, .main])

    editor.name = "Unsaved name"
    await provider.replaceWidgets([widget])
    editor.invalidateSnapshot()
    await editor.refreshIfNeeded()
    #expect(editor.name == "Unsaved name")
    #expect(await provider.reads == [.main, .main])
    editor.resetDraft()
    await editor.refreshIfNeeded()
    #expect(editor.widgets == [widget])
    #expect(await provider.reads == [.main, .main, .main])
    await editor.loadIfNeeded(refreshExisting: true)
    #expect(await provider.reads == [.main, .main, .main])

    // An unfinished widget has no saveable changes, but still belongs to the draft.
    let blank = ProfileWidget(content: .personal(ProfilePersonalWidget(sections: [.cover(ProfileWidgetCover())])))
    editor.addWidget(blank)
    #expect(!editor.hasChanges)
    editor.invalidateSnapshot()
    await editor.refreshIfNeeded()
    await editor.loadIfNeeded(refreshExisting: true)
    await editor.load(.main)
    #expect(editor.widgets == [blank, widget])
    #expect(await provider.reads == [.main, .main, .main])
    editor.removeWidget(id: blank.id)
    await editor.refreshIfNeeded()
    #expect(editor.widgets == [widget])
    #expect(await provider.reads == [.main, .main, .main, .main])
}

private actor ProfileEditorCacheProvider: ChatProvider {
    private let fixture = MockChatProvider()
    private var widgets: [ProfileWidget]?
    init(widgets: [ProfileWidget]? = nil) { self.widgets = widgets }
    private var cache: [ProfileEditingScope: ProfileEditingSnapshot] = [:]
    private(set) var reads: [ProfileEditingScope] = []
    private var suspendsRead = false
    private var pendingRead: CheckedContinuation<Void, Never>?
    private var readStarted: CheckedContinuation<Void, Never>?

    func suspendNextRead() { suspendsRead = true }
    func replaceWidgets(_ widgets: [ProfileWidget]) { self.widgets = widgets }
    func waitForRead() async {
        if pendingRead != nil { return }
        await withCheckedContinuation { readStarted = $0 }
    }
    func resumeRead() { pendingRead?.resume(); pendingRead = nil }
    func cachedProfileEditingSnapshot(in scope: ProfileEditingScope) async throws -> ProfileEditingSnapshot? { cache[scope] }
    func profileEditingSnapshot(in scope: ProfileEditingScope) async throws -> ProfileEditingSnapshot {
        reads.append(scope)
        if suspendsRead {
            suspendsRead = false
            await withCheckedContinuation {
                pendingRead = $0
                readStarted?.resume(); readStarted = nil
            }
        }
        var value = try await fixture.profileEditingSnapshot(in: scope)
        if let widgets {
            value.presentation.widgets = widgets
            value.mainPresentation.widgets = widgets
            value.widgetEligibility = ProfileWidgetEligibility(hasFullNitro: true, hasPersonalWidgetAccess: true)
        }
        cache[scope] = value
        return value
    }
    func bootstrap() async throws -> BootstrapSnapshot { try await fixture.bootstrap() }
    func channels(in guildID: GuildID?) async throws -> [Channel] { [] }
    func members(in guildID: GuildID?) async throws -> [Member] { [] }
    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile { try await fixture.profile(for: userID, in: guildID) }
    func currentStatus() async -> PresenceStatus { .offline }
    func updateStatus(_ status: PresenceStatus) async throws {}
    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage { MessagePage(messages: [], hasMoreBefore: false) }
    func send(_ draft: SendMessageDraft) async throws -> Message { throw ChatProviderError.invalidRequest("unused") }
    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message { throw ChatProviderError.invalidRequest("unused") }
    func delete(messageID: MessageID, channelID: ChannelID) async throws {}
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {}
    func eventStream() async -> AsyncStream<ClientEvent> { AsyncStream { $0.finish() } }
    func disconnect() async {}
}
