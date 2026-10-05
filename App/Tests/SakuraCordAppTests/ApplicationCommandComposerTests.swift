import AppKit
import Foundation
@testable import SakuraCord
import SakuraCordModels
import Testing

private func composerFixtureCommand(
    id: String,
    name: String,
    application: ApplicationCommandApplication,
    description: String = "",
    rank: Int? = nil,
    options: [ApplicationCommandOption] = []
) -> ApplicationCommand {
    ApplicationCommand(
        id: id, rootCommandID: id, applicationID: application.id, version: "1",
        name: name, description: description, application: application,
        options: options, globalPopularityRank: rank,
        rootCommandJSON: Data(
            "{\"id\":\"\(id)\",\"application_id\":\"\(application.id)\",\"name\":\"\(name)\"}"
                .utf8
        )
    )
}

@MainActor
@Test("command search ranks exact prefix fuzzy and application matches deterministically")
func commandSearchRanking() throws {
    let model = ApplicationCommandComposerModel()
    let verified = ApplicationCommandApplication(id: "100", name: "Verified")
    let utility = ApplicationCommandApplication(id: "101", name: "Utility")
    let exact = composerFixtureCommand(
        id: "200", name: "verify", application: verified, description: "Verify a member", rank: 8
    )
    let prefix = composerFixtureCommand(
        id: "201", name: "verifyforme", application: verified, rank: 1
    )
    let fuzzy = composerFixtureCommand(
        id: "202", name: "very-safe", application: utility, rank: 2
    )
    model.beginLoading(targets: [.user])
    model.replaceCatalogs([
        ApplicationCommandCatalog(
            target: .user, applications: [verified, utility], commands: [fuzzy, prefix, exact]
        )
    ])

    #expect(model.rankedCommands(query: "verify").map(\.id) == ["200", "201"])
    #expect(model.rankedCommands(query: "vys").map(\.id) == ["202"])
    #expect(model.rankedCommands(query: "utility").map(\.id) == ["202"])
    #expect(model.sections(query: "verify").flatMap(\.commands).map(\.id) == ["200", "201"])
}

@MainActor
@Test("command availability respects context and explicit permission precedence")
func commandAvailabilityFiltering() throws {
    let application = ApplicationCommandApplication(id: "100", name: "Utility")
    let userID = try #require(UserID("500"))
    let guildID = try #require(GuildID("600"))
    let channelID = try #require(ChannelID("700"))
    let roleID = try #require(RoleID("800"))
    let channel = Channel(id: channelID, guildID: guildID, name: "general")
    var command = composerFixtureCommand(id: "200", name: "verify", application: application)
    command.contexts = [0]
    command.permissions = [
        .init(id: guildID.description, type: 1, allows: false),
        .init(id: roleID.description, type: 1, allows: true),
        .init(id: userID.description, type: 2, allows: false)
    ]

    #expect(!ApplicationCommandAvailability.isAvailable(
        command, channel: channel, currentUserID: userID, memberRoleIDs: [roleID]
    ))
    command.permissions.removeAll { $0.type == 2 }
    #expect(ApplicationCommandAvailability.isAvailable(
        command, channel: channel, currentUserID: userID, memberRoleIDs: [roleID]
    ))
    command.contexts = [1, 2]
    #expect(!ApplicationCommandAvailability.isAvailable(
        command, channel: channel, currentUserID: userID, memberRoleIDs: [roleID]
    ))
    command.contexts = [0]
    command.integrationTypes = [1]
    #expect(!ApplicationCommandAvailability.isAvailable(
        command, channel: channel, currentUserID: userID, memberRoleIDs: [roleID],
        indexTarget: .guild(guildID)
    ))
    #expect(ApplicationCommandAvailability.isAvailable(
        command, channel: channel, currentUserID: userID, memberRoleIDs: [roleID],
        indexTarget: .user
    ))

    // Reusing a prepared catalog across conversations must still apply the
    // destination's permissions, and must not retain an old command definition.
    let model = ApplicationCommandComposerModel()
    command.integrationTypes = [0]
    command.permissions = [.init(id: channelID.description, type: 3, allows: false)]
    let otherChannel = Channel(id: ChannelID(rawValue: 701), guildID: guildID, name: "other")
    func load(in destination: Channel) {
        model.resetForChannelChange()
        model.replaceCatalogs([
            ApplicationCommandCatalog(target: .guild(guildID), applications: [application], commands: [command])
        ], channel: destination, currentUserID: userID)
    }
    load(in: otherChannel)
    #expect(model.rankedCommands(query: "verify").map(\.id) == [command.id])
    load(in: channel)
    #expect(model.rankedCommands(query: "verify").isEmpty)
    load(in: otherChannel)
    #expect(model.rankedCommands(query: "verify").map(\.id) == [command.id])
    command.name = "inspect"
    load(in: otherChannel)
    #expect(model.rankedCommands(query: "verify").isEmpty)
    #expect(model.rankedCommands(query: "inspect").map(\.id) == [command.id])
}

@MainActor
@Test("command availability distinguishes bot DMs from private channels")
func commandDirectMessageContextFiltering() {
    let bot = User(
        id: UserID(rawValue: 501), username: "utility", displayName: "Utility", isBot: true
    )
    let person = User(
        id: UserID(rawValue: 502), username: "person", displayName: "Person"
    )
    let application = ApplicationCommandApplication(id: "100", name: "Utility", bot: bot)
    var command = composerFixtureCommand(id: "200", name: "verify", application: application)
    let botDM = Channel(
        id: ChannelID(rawValue: 700), guildID: nil, name: "Utility",
        kind: .directMessage, recipients: [bot]
    )
    let privateDM = Channel(
        id: ChannelID(rawValue: 701), guildID: nil, name: "Person",
        kind: .directMessage, recipients: [person]
    )
    let groupDM = Channel(
        id: ChannelID(rawValue: 702), guildID: nil, name: "Group",
        kind: .groupDirectMessage, recipients: [bot, person]
    )

    command.contexts = [1]
    #expect(ApplicationCommandAvailability.isAvailable(
        command, channel: botDM, currentUserID: nil, memberRoleIDs: []
    ))
    #expect(!ApplicationCommandAvailability.isAvailable(
        command, channel: privateDM, currentUserID: nil, memberRoleIDs: []
    ))
    #expect(!ApplicationCommandAvailability.isAvailable(
        command, channel: groupDM, currentUserID: nil, memberRoleIDs: []
    ))

    command.contexts = [2]
    #expect(!ApplicationCommandAvailability.isAvailable(
        command, channel: botDM, currentUserID: nil, memberRoleIDs: []
    ))
    #expect(ApplicationCommandAvailability.isAvailable(
        command, channel: privateDM, currentUserID: nil, memberRoleIDs: []
    ))
    #expect(ApplicationCommandAvailability.isAvailable(
        command, channel: groupDM, currentUserID: nil, memberRoleIDs: []
    ))
}

private let composerApplication = ApplicationCommandApplication(id: "100", name: "Utility")

/// /research text:(required, 2-12) count:(optional integer -3...7) who:(optional user) note:(optional)
private func researchCommand() -> ApplicationCommand {
    composerFixtureCommand(
        id: "200", name: "research", application: composerApplication,
        options: [
            ApplicationCommandOption(
                id: "200/text", name: "text", type: .string, isRequired: true,
                minimumLength: 2, maximumLength: 12
            ),
            ApplicationCommandOption(
                id: "200/count", name: "count", type: .integer, minimumValue: -3, maximumValue: 7
            ),
            ApplicationCommandOption(id: "200/who", name: "who", type: .user),
            ApplicationCommandOption(id: "200/note", name: "note", type: .string)
        ]
    )
}

@MainActor
@Test("optional fields insert at the typed gap while values keep definition order")
func commandDraftFieldOrder() throws {
    var draft = ApplicationCommandDraft(command: researchCommand())
    #expect(draft.fields.map(\.option.name) == ["text"])
    #expect(draft.focus == .field("200/text"))

    draft.setText("hello", for: "200/text")
    draft.focus = draft.endGap
    let added = draft.addOptionalOption(try #require(draft.availableOptionalOptions.last))
    #expect(added)
    draft.setText("later", for: "200/note")
    // A name typed in the gap before `note` lands there, as in Discord.
    draft.focus = .gap(1)
    draft.gapText = "count:"
    let accepted = draft.acceptTypedOptionName()
    #expect(accepted)
    draft.setText("5", for: "200/count")

    #expect(draft.fields.map(\.option.name) == ["text", "count", "note"])
    #expect(draft.focus == .field("200/count"))
    #expect(draft.optionValues().map(\.name) == ["text", "count", "note"])
    #expect(draft.optionValues().map(\.argument) == [.string("hello"), .integer(5), .string("later")])
    #expect(draft.plainText == "/research text:hello count:5 note:later")
}

@MainActor
@Test("backspace from a gap follows Discord's chip semantics")
func commandDraftBackspaceSemantics() throws {
    var draft = ApplicationCommandDraft(command: researchCommand())
    draft.setText("ab", for: "200/text")
    let who = try #require(draft.availableOptionalOptions.first { $0.name == "who" })
    draft.focus = draft.endGap
    draft.addOptionalOption(who)
    draft.resolve("200/who", to: .user(UserID(rawValue: 123_456_789_012_345_678)), display: "@person")
    let note = try #require(draft.availableOptionalOptions.first { $0.name == "note" })
    draft.focus = draft.endGap
    draft.addOptionalOption(note)

    // An empty optional chip is removed and the caret stays in its gap.
    let removedEmpty = draft.deleteBackward(intoFieldBefore: 3)
    #expect(removedEmpty == .gap(2))
    #expect(draft.fields.map(\.option.name) == ["text", "who"])
    // A chosen entity is deleted as one token; the chip stays focused.
    let clearedToken = draft.deleteBackward(intoFieldBefore: 2)
    #expect(clearedToken == .field("200/who"))
    #expect(draft.field("200/who")?.text == "")
    #expect(draft.field("200/who")?.resolved == nil)
    // Text loses only its last character.
    let trimmed = draft.deleteBackward(intoFieldBefore: 1)
    #expect(trimmed == .field("200/text"))
    #expect(draft.field("200/text")?.text == "a")
    // Nothing precedes the first chip; that Backspace converts to plain text.
    let beforeFirst = draft.deleteBackward(intoFieldBefore: 0)
    #expect(beforeFirst == nil)
    #expect(draft.plainTextAfterDeletingCommand == "/researc text:a who:")
}

@MainActor
@Test("invalid fields block submission with Discord-style feedback and focus")
func commandDraftValidation() throws {
    let model = ApplicationCommandComposerModel()
    model.activate(researchCommand())
    #expect(!model.canSubmit)
    #expect(!model.prepareSubmission())
    #expect(model.fieldIssue == ApplicationCommandFieldIssue(fieldID: "200/text", message: "This option is required."))

    model.setText("a", for: .field("200/text"))
    #expect(!model.prepareSubmission())
    #expect(model.fieldIssue?.message == "Enter between 2 and 12 characters.")
    // Discord counts Unicode scalars, so a combined emoji can exceed the limit.
    model.setText("🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸", for: .field("200/text"))
    #expect(!model.prepareSubmission())
    model.setText("ok", for: .field("200/text"))
    #expect(model.fieldIssue == nil)

    model.setText("", for: .gap(1))
    model.setText("count:", for: .gap(1))
    #expect(model.draft?.focus == .field("200/count"))
    for (text, message) in [
        ("x", "Enter a whole number."),
        ("8", "Enter a number between -3 and 7."),
        ("99999999999999999", "This number is too large."),
        (String(Int64.min), "This number is too large.")
    ] {
        model.setText(text, for: .field("200/count"))
        #expect(!model.prepareSubmission())
        #expect(model.fieldIssue == ApplicationCommandFieldIssue(fieldID: "200/count", message: message))
        #expect(model.draft?.focus == .field("200/count"))
    }
    model.setText("-3", for: .field("200/count"))
    #expect(model.prepareSubmission())
    let invocation = try #require(model.invocation(channelID: ChannelID(rawValue: 300), guildID: nil))
    #expect(invocation.values.map(\.argument) == [.string("ok"), .integer(-3)])
}

@MainActor
@Test("autocomplete results are scoped by nonce to the field and query that asked")
func commandAutocompleteNonceScoping() throws {
    let model = ApplicationCommandComposerModel()
    let query = ApplicationCommandOption(
        id: "300/query", name: "query", type: .string, isRequired: true, usesAutocomplete: true
    )
    model.activate(composerFixtureCommand(id: "300", name: "find", application: composerApplication, options: [query]))
    let channelID = ChannelID(rawValue: 400)
    let choice = { (name: String) in ApplicationCommandChoice(name: name, value: .string(name)) }

    let first = try #require(model.autocompleteRequest(channelID: channelID, guildID: nil))
    #expect(first.query == "")
    #expect(model.autocompleteRequest(channelID: channelID, guildID: nil) == nil)
    model.setText("al", for: .field("300/query"))
    let second = try #require(model.autocompleteRequest(channelID: channelID, guildID: nil))
    #expect(second.query == "al")
    #expect(model.autocompleteStatus.isLoading)

    // A superseded answer is cached but never replaces the current list.
    model.receiveAutocomplete(.init(nonce: first.nonce, choices: [choice("stale")]))
    #expect(model.autocompleteStatus.isLoading)
    // A failure for an unrelated nonce is not an autocomplete failure.
    #expect(!model.failAutocomplete(nonce: "other", failure: InteractionFailure(reasonCode: 2)))
    model.receiveAutocomplete(.init(nonce: second.nonce, choices: [choice("alpha")]))
    #expect(model.autocompleteStatus == .loaded([choice("alpha")]))

    // Returning to the earlier query uses the cached answer without a request.
    model.setText("", for: .field("300/query"))
    #expect(model.autocompleteRequest(channelID: channelID, guildID: nil) == nil)
    #expect(model.autocompleteStatus == .loaded([choice("stale")]))
}

@MainActor
@Test("attachment paste fills the right option and ignores outdated targets")
func attachmentPasteTargetLifecycle() throws {
    let model = ApplicationCommandComposerModel()
    let first = ApplicationCommandOption(id: "200/first", name: "first", type: .attachment, isRequired: true)
    let second = ApplicationCommandOption(id: "200/second", name: "second", type: .attachment, isRequired: true)
    let command = composerFixtureCommand(id: "200", name: "files", application: composerApplication, options: [first, second])
    let oldURL = URL(fileURLWithPath: "/old.txt")
    let newURL = URL(fileURLWithPath: "/new.txt")
    model.activate(command)
    #expect(model.pastedAttachmentOption?.id == first.id)

    let changedFocus = try #require(model.attachmentPasteTarget())
    model.focusField(second.id)
    #expect(!model.finishAttachmentPaste(oldURL, target: changedFocus))
    #expect(model.attachmentURLs.isEmpty)

    let changedCommand = try #require(model.attachmentPasteTarget())
    model.cancelActiveCommand()
    model.activate(command)
    #expect(!model.finishAttachmentPaste(oldURL, target: changedCommand))

    let current = try #require(model.attachmentPasteTarget())
    #expect(model.finishAttachmentPaste(newURL, target: current))
    #expect(model.draft?.field(first.id)?.resolved == .attachment(newURL))
    // The caret moves on, and the next paste targets the empty option.
    #expect(model.draft?.focus == .gap(1))
    #expect(model.pastedAttachmentOption?.id == second.id)

    var optional = second
    optional.isRequired = false
    model.activate(composerFixtureCommand(id: "201", name: "optional", application: composerApplication, options: [optional]))
    #expect(model.draft?.fields.isEmpty == true)
    let optionalTarget = try #require(model.attachmentPasteTarget())
    #expect(model.finishAttachmentPaste(newURL, target: optionalTarget))
    #expect(model.draft?.field(optional.id)?.resolved == .attachment(newURL))
}

@MainActor
@Test("autocomplete retries failures and isolates new drafts and conversations")
func commandAutocompleteLifecycle() throws {
    let model = ApplicationCommandComposerModel()
    let option = ApplicationCommandOption(id: "300/query", name: "query", type: .string, isRequired: true, usesAutocomplete: true)
    let command = composerFixtureCommand(id: "300", name: "find", application: composerApplication, options: [option])
    let channel = ChannelID(rawValue: 400)
    model.activate(command)
    let first = try #require(model.autocompleteRequest(channelID: channel, guildID: nil))
    #expect(model.failAutocomplete(nonce: first.nonce, failure: InteractionFailure(reasonCode: 2)))
    model.setText("changed", for: .field(option.id))
    _ = model.autocompleteRequest(channelID: channel, guildID: nil)
    model.setText("", for: .field(option.id))
    let retry = try #require(model.autocompleteRequest(channelID: channel, guildID: nil))
    model.receiveAutocomplete(.init(nonce: first.nonce, choices: [.init(name: "obsolete", value: .string("obsolete"))]))
    #expect(model.autocompleteStatus.isLoading)
    #expect(model.isAutocompleteRequestCurrent(retry.nonce))
    model.abandonAutocomplete(nonce: retry.nonce, message: "Cancelled")
    let afterDebounceCancellation = try #require(model.autocompleteRequest(channelID: channel, guildID: nil))
    model.cancelActiveCommand()
    model.activate(command)
    #expect(!model.isAutocompleteRequestCurrent(afterDebounceCancellation.nonce))
    _ = try #require(model.autocompleteRequest(channelID: channel, guildID: nil))
    let differentChannel = try #require(model.autocompleteRequest(channelID: ChannelID(rawValue: 401), guildID: nil))
    #expect(differentChannel.invocation.channelID != channel)
}

@MainActor
@Test("command copying and submission preserve literal Unicode and whitespace values")
func commandLiteralTextPreservation() throws {
    var draft = ApplicationCommandDraft(command: researchCommand())
    let value = " 🌸  e\u{301} "
    draft.setText(value, for: "200/text")
    let document = ApplicationCommandEditorDocument(draft: draft)
    let span = try #require(document.span("200/text"))
    #expect(document.plainText(in: span.value) == value)
    #expect(document.plainText(in: NSRange(location: 0, length: document.length)) == "/research text:" + value + " ")
    #expect(draft.optionValues().first?.argument == .string(value))
}

@MainActor
@Test("returned modals settle their opener and late successes cannot close another form")
func commandInteractionModalOrdering() throws {
    let model = AppModel(launchMode: .offlineTesting)
    let channel = ChannelID(rawValue: 400)
    model.trackInteraction(.init(kind: .command(channelID: channel, commandName: "find", application: composerApplication)), nonce: "opening")
    #expect(model.interactionDeadlineTasks.isEmpty)
    model.startInteractionDeadline(nonce: "opening")
    #expect(model.interactionDeadlineTasks.count == 1)
    let modal = InteractionModal(interactionID: "modal-one", openingNonce: "opening", application: composerApplication,
        channelID: channel, guildID: nil, customID: "form", title: "Form", nodes: [])
    model.consumeInteraction(.presentModal(modal))
    #expect(model.pendingInteractions["opening"]?.isFinished == true)
    #expect(model.interactionDeadlineTasks.isEmpty)
    let form = try #require(model.interactionModalForm)
    model.consumeInteraction(.failed(nonce: "opening", failure: .init(reasonCode: 2)))
    #expect(model.interactionModalForm === form)
    model.trackInteraction(.init(kind: .modalSubmission(channelID: channel, application: composerApplication, formID: "older-form")), nonce: "older-submit")
    model.consumeInteraction(.succeeded(nonce: "older-submit", interactionID: "old"))
    #expect(model.interactionModalForm === form)
    model.trackInteraction(.init(kind: .modalSubmission(channelID: channel, application: composerApplication, formID: form.id)), nonce: "submit")
    form.beginSubmitting()
    model.consumeInteraction(.succeeded(nonce: "submit", interactionID: "current"))
    #expect(model.interactionModalForm == nil)
    #expect(model.finishPendingInteraction("submit") == nil)
}
