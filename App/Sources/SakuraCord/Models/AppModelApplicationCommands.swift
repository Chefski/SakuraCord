import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func loadApplicationCommands() {
        guard supportedCapabilities.contains(.slashCommands),
              let channel = selectedChannel,
              channel.kind != .voice, channel.kind != .forum, channel.kind != .unknown
        else {
            commandComposer.failLoading(
                ChatProviderError.capabilityDisabled(.slashCommands).localizedDescription
            )
            return
        }
        let contextTarget: ApplicationCommandIndexTarget =
            channel.guildID.map {
                .guild($0)
            } ?? .channel(channel.id)
        let targets: Set<ApplicationCommandIndexTarget> = [contextTarget, .user]
        commandComposer.beginLoading(targets: targets)
        commandComposer.locale = Locale(identifier: Locale.preferredLanguages.first ?? "en-US")
        loadCommandFrecencyIfNeeded()
        commandLoadTask?.cancel()
        let account = accountSession()
        commandLoadTask = Task { [weak self] in
            guard let self,
                  !Task.isCancelled,
                  isCurrentAccountSession(account)
            else { return }
            do {
                async let context: ApplicationCommandCatalog? =
                    try? account.provider.applicationCommandCatalog(
                        for: contextTarget
                    )
                async let user: ApplicationCommandCatalog? =
                    try? account.provider.applicationCommandCatalog(
                        for: .user
                    )
                let catalogs = await [context, user].compactMap(\.self)
                guard !catalogs.isEmpty else {
                    throw ChatProviderError.invalidRequest(
                        "Discord did not return an application command index for this conversation."
                    )
                }
                guard !Task.isCancelled,
                      isCurrentAccountSession(account),
                      selectedChannelID == channel.id
                else { return }
                let roleIDs = Set(
                    (snapshot?.currentUser.id).flatMap { membersByID[$0] }?.roles.map(\.id) ?? []
                )
                commandComposer.replaceCatalogs(
                    catalogs,
                    channel: channel,
                    currentUserID: snapshot?.currentUser.id,
                    memberRoleIDs: roleIDs,
                    builtInContext: builtInCommandContext(for: channel)
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      isCurrentAccountSession(account),
                      selectedChannelID == channel.id
                else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                commandComposer.failLoading(error.localizedDescription)
            }
        }
    }

    /// Requests remote choices for the focused field when its query changed.
    /// Discord answers through the Gateway; results correlate by nonce.
    func refreshApplicationCommandAutocomplete() {
        guard let channelID = selectedChannelID else { return }
        let request = commandComposer.autocompleteRequest(channelID: channelID, guildID: selectedGuildID)
        if let nonce = commandAutocompleteDebounceNonce,
           !commandComposer.isAutocompleteRequestCurrent(nonce) {
            cancelApplicationCommandAutocompleteTask(resetTiming: false)
        }
        guard let request else { return }
        let session = accountSession()
        // Discord's desktop picker uses a 500 ms leading/trailing debounce:
        // an isolated query starts immediately, a burst sends its latest value
        // after typing settles. Keep dispatched requests alive for nonce routing.
        let now = ContinuousClock.now
        let delay: Duration = commandAutocompleteLastQueryTime.map {
            $0.duration(to: now) < .milliseconds(500) ? .milliseconds(500) : .zero
        } ?? .zero
        commandAutocompleteLastQueryTime = now
        commandAutocompleteDebounceNonce = request.nonce
        commandAutocompleteTask = startAccountChildTask(account: session) { model, session in
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                try Task.checkCancellation()
                guard model.commandComposer.isAutocompleteRequestCurrent(request.nonce) else {
                    model.commandComposer.abandonAutocomplete(nonce: request.nonce, message: "")
                    return
                }
                model.commandAutocompleteDebounceNonce = nil
                model.commandAutocompleteTask = nil
                try await AppPerformanceSignposts.measure("CommandAutocompleteRequest") {
                    try await session.provider.requestApplicationCommandAutocomplete(request)
                }
            } catch is CancellationError {
                guard model.isCurrentAccountSession(session) else { return }
                model.commandComposer.abandonAutocomplete(nonce: request.nonce, message: "")
                return
            } catch {
                guard model.isCurrentAccountSession(session) else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                model.commandComposer.abandonAutocomplete(
                    nonce: request.nonce, message: "Loading options failed"
                )
            }
        }
    }

    func cancelApplicationCommandAutocompleteTask(resetTiming: Bool = true) {
        if resetTiming { commandAutocompleteLastQueryTime = nil }
        commandAutocompleteTask?.cancel()
        commandAutocompleteTask = nil
        if let nonce = commandAutocompleteDebounceNonce {
            commandComposer.abandonAutocomplete(nonce: nonce, message: "")
        }
        commandAutocompleteDebounceNonce = nil
    }

    func requestApplicationCommandMemberSearch(query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let option = commandComposer.draft?.focusedField?.option,
              option.type == .user || option.type == .mentionable,
              let guildID = selectedGuildID,
              !normalized.isEmpty
        else {
            cancelApplicationCommandMemberSearch()
            return
        }
        let key = CommandMemberQuery(guildID: guildID, query: normalized.lowercased())
        if let cached = commandMemberSearchCache[key] {
            commandMemberSearchTask?.cancel()
            commandMemberSearchTask = nil
            commandMemberSearchQuery = nil
            commandMemberResults = cached
            return
        }
        guard commandMemberSearchQuery != key else { return }
        commandMemberSearchTask?.cancel()
        commandMemberSearchQuery = key
        commandMemberResults = []
        let session = accountSession()
        commandMemberSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                let results = try await session.provider.searchMembers(
                    in: guildID, query: normalized, limit: 20
                )
                guard !Task.isCancelled,
                      isCurrentAccountSession(session),
                      commandMemberSearchQuery == key,
                      selectedGuildID == guildID
                else { return }
                commandMemberSearchCache[key] = results
                commandMemberResults = results
                commandMemberSearchQuery = nil
                commandMemberSearchTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentAccountSession(session),
                      commandMemberSearchQuery == key
                else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                commandMemberSearchQuery = nil
                commandMemberSearchTask = nil
                commandMemberResults = []
            }
        }
    }

    func cancelApplicationCommandMemberSearch() {
        commandMemberSearchTask?.cancel()
        commandMemberSearchTask = nil
        commandMemberSearchQuery = nil
        commandMemberResults = []
    }

    func requestMentionMemberSearch(query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let guildID = selectedGuildID, !normalized.isEmpty else {
            mentionMemberSearchTask?.cancel()
            mentionMemberSearchTask = nil
            mentionMemberSearchQuery = nil
            mentionMemberResults = []
            return
        }
        let key = CommandMemberQuery(guildID: guildID, query: normalized.lowercased())
        if let cached = mentionMemberSearchCache[key],
           Date().timeIntervalSince(cached.storedAt) < 60
        {
            mentionMemberResults = cached.members
            return
        }
        mentionMemberSearchCache[key] = nil
        guard mentionMemberSearchQuery != key else { return }
        mentionMemberSearchTask?.cancel()
        mentionMemberSearchQuery = key
        mentionMemberResults = []
        let session = accountSession()
        mentionMemberSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                let results = try await session.provider.searchMembers(
                    in: guildID, query: key.query, limit: 10
                )
                let roles = try? await session.provider.roles(in: guildID)
                guard !Task.isCancelled,
                      isCurrentAccountSession(session),
                      mentionMemberSearchQuery == key,
                      selectedGuildID == guildID
                else { return }
                if let roles { applyGuildRoles(roles, to: guildID) }
                mentionMemberSearchCache[key] = MentionMemberSearchCacheEntry(
                    members: results,
                    storedAt: Date()
                )
                mentionMemberResults = results
                mergeMentionAutocompleteMembers(results)
                for member in results { knownMentionMembers[member.id] = member }
                mentionMemberSearchQuery = nil
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentAccountSession(session),
                      mentionMemberSearchQuery == key
                else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                mentionMemberSearchQuery = nil
                mentionMemberResults = []
            }
        }
    }

    func rememberMentionMember(_ member: Member) {
        knownMentionMembers[member.id] = member
    }

    func mergeMentionAutocompleteMembers(_ updates: [Member]) {
        var positions = Dictionary(
            uniqueKeysWithValues: mentionAutocompleteMembers.indices.map {
                (mentionAutocompleteMembers[$0].id, $0)
            }
        )
        for member in updates {
            if let index = positions[member.id] {
                mentionAutocompleteMembers[index] = member
            } else {
                positions[member.id] = mentionAutocompleteMembers.count
                mentionAutocompleteMembers.append(member)
            }
        }
    }

    func showMembers(withRole roleID: RoleID, in guildID: GuildID?) {
        roleMemberTask?.cancel()
        roleMemberResult = nil
        roleMemberErrorMessage = nil
        isLoadingRoleMembers = false
        guard let guildID else {
            roleMemberErrorMessage = "Role members are only available inside a server."
            return
        }
        isLoadingRoleMembers = true
        let session = accountSession()
        roleMemberTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await session.provider.members(withRole: roleID, in: guildID)
                guard !Task.isCancelled,
                      isCurrentAccountSession(session)
                else { return }
                roleMemberResult = result
                for member in result.members {
                    membersByGuildID[guildID, default: [:]][member.id] = member
                    if selectedGuildID == guildID { knownMentionMembers[member.id] = member }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      isCurrentAccountSession(session)
                else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                roleMemberErrorMessage = error.localizedDescription
            }
            if isCurrentAccountSession(session) {
                isLoadingRoleMembers = false
            }
        }
    }

    /// Sends the composed command. Like Discord, the composer clears at once
    /// and a private placeholder row tracks the app's answer.
    func executeApplicationCommand() {
        AppPerformanceSignposts.measureSync("CommandSubmit") { submitApplicationCommand() }
    }

    private func submitApplicationCommand() {
        guard let channelID = selectedChannelID,
              commandComposer.prepareSubmission(),
              let invocation = commandComposer.invocation(
                  channelID: channelID, guildID: selectedGuildID
              )
        else { return }
        guard allowSlowmodeSubmission(in: channelID) else { return }
        cancelApplicationCommandAutocompleteTask()
        let submittedDraft = commandComposer.draft
        stopLocalTyping(clearThrottle: true)
        commandComposer.recordUse(of: invocation.command, guildID: invocation.guildID)
        commandComposer.cancelActiveCommand()
        updateDraft("")
        if DiscordBuiltInCommands.isBuiltIn(invocation.command) {
            runBuiltInCommand(invocation)
        } else {
            runApplicationCommand(invocation, restoringDraftOnFailure: submittedDraft)
        }
    }

    /// Runs a user or message context-menu command against its target.
    func runContextMenuCommand(_ command: ApplicationCommand, targetID: String, in channelID: ChannelID) {
        guard supportedCapabilities.contains(.slashCommands) else { return }
        let guildID = visibleChannels.first { $0.id == channelID }?.guildID
            ?? snapshot?.channels.first { $0.id == channelID }?.guildID
        commandComposer.recordUse(of: command, guildID: guildID)
        runApplicationCommand(ApplicationCommandInvocation(
            command: command, channelID: channelID, guildID: guildID, values: [], targetID: targetID
        ))
    }

    private func runApplicationCommand(
        _ invocation: ApplicationCommandInvocation,
        restoringDraftOnFailure submittedDraft: ApplicationCommandDraft? = nil
    ) {
        let nonce = invocation.nonce
        let channelID = invocation.channelID
        trackInteraction(
            PendingInteractionRecord(kind: .command(
                channelID: channelID,
                commandName: invocation.command.displayName,
                application: invocation.command.application
            )),
            nonce: nonce
        )
        appendInteractionPlaceholder(for: invocation)
        let session = accountSession()
        let attachmentURLs = invocation.values.compactMap { value -> URL? in
            guard case let .attachment(url) = value.argument else { return nil }
            return url
        }
        // Lease before yielding: changing channels may prune the cleared draft.
        beginUsingOwnedPromisedFiles(attachmentURLs)
        startAccountChildTask(account: session) { [weak self] _, session in
            guard let self else { return }
            let uploadsAttachments = !attachmentURLs.isEmpty
            if uploadsAttachments { activeAttachmentUploadCount += 1 }
            defer { if uploadsAttachments { activeAttachmentUploadCount -= 1 } }
            let scoped = attachmentURLs.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                endUsingOwnedPromisedFiles(attachmentURLs)
            }
            do {
                try await session.provider.executeApplicationCommand(invocation) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.isCurrentAccountSession(session) else { return }
                        self.updateInteractionPlaceholder(
                            nonce: nonce, channelID: channelID, progress: progress
                        )
                    }
                }
                guard isCurrentAccountSession(session) else { return }
                startInteractionDeadline(nonce: nonce)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentAccountSession(session), finishPendingInteraction(nonce) != nil else { return }
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                // A definite request failure is final; it is never replayed.
                failInteractionPlaceholder(
                    nonce: nonce, channelID: channelID, message: error.localizedDescription
                )
                // Keep failed input available for editing without replacing a
                // newer draft or automatically repeating the account action.
                if let submittedDraft, selectedChannelID == channelID,
                   draft.isEmpty, commandComposer.draft == nil {
                    commandComposer.activate(submittedDraft.command)
                    commandComposer.applyEditorDraft(submittedDraft, caret: nil)
                }
            }
        }
    }

    /// Context-menu commands need the same catalogues as the slash picker.
    func ensureApplicationCommandsLoaded() {
        guard !commandComposer.hasLoadedCatalogs, !commandComposer.isLoading else { return }
        loadApplicationCommands()
    }

    /// What decides which Discord built-ins this conversation offers.
    func builtInCommandContext(for channel: Channel) -> DiscordBuiltInCommands.Context {
        let channelPermissions = effectiveMessagePermissions(in: channel)
        let guildPermissions = channel.guildID.flatMap { guildID -> UInt64? in
            guard let basis = conversationPermissionBasis(for: guildID) else { return nil }
            return basis.guild.isOwnedByCurrentUser == true ? .max : basis.resolvedBasePermissions
        }
        let createPublicThreads: UInt64 = 1 << 35
        let threadable = channel.kind == .text || channel.kind == .announcement
        let canCreateThread = threadable && channel.guildID != nil
            && (channelPermissions.map { $0 & (createPublicThreads | DiscordBuiltInCommands.Permission.administrator) != 0 } ?? false)
        return DiscordBuiltInCommands.Context(
            isPrivate: channel.guildID == nil,
            isGroupDirectMessage: channel.kind == .groupDirectMessage,
            channelPermissions: channelPermissions,
            guildPermissions: guildPermissions,
            canCreatePublicThread: canCreateThread,
            allowsTTSCommand: true
        )
    }

    // MARK: Discord built-ins

    /// Runs one of Discord's client-side commands the way the official client
    /// does: most become an ordinary message; none reach an application.
    func runBuiltInCommand(_ invocation: ApplicationCommandInvocation) {
        let session = accountSession()
        let channelID = invocation.channelID
        func string(_ name: String) -> String {
            for value in invocation.values where value.name == name {
                if case let .string(text) = value.argument { return text }
            }
            return ""
        }
        func user(_ name: String) -> UserID? {
            for value in invocation.values where value.name == name {
                if case let .user(id) = value.argument { return id }
            }
            return nil
        }
        let message = string("message")
        if let text = Self.builtInMessageText(command: invocation.command.name, message: message) {
            let isTTS = invocation.command.name == "tts"
            startAccountChildTask(account: session) { model, _ in
                await model.sendChannelMessage(
                    channelID: channelID, content: text, replyTo: nil, replyPreview: nil,
                    attachments: [], clearsComposer: false, isTTS: isTTS
                )
            }
            return
        }
        switch invocation.command.name {
        case "msg":
            guard let recipient = user("user") else { return }
            startAccountChildTask(account: session) { [weak self] _, session in
                do {
                    let channel = try await session.provider.ensurePrivateChannel(for: recipient)
                    guard let self, !Task.isCancelled, isCurrentAccountSession(session) else { return }
                    _ = try await session.provider.send(SendMessageDraft(channelID: channel.id, content: message))
                } catch {
                    guard let self, isCurrentAccountSession(session) else { return }
                    appendBuiltInNotice("Your message could not be delivered.", in: channelID)
                }
            }
        case "thread":
            let name = string("name")
            startAccountChildTask(account: session) { [weak self] _, session in
                do {
                    let thread = try await session.provider.createThread(CreateThreadDraft(channelID: channelID, name: name))
                    guard let self, !Task.isCancelled, isCurrentAccountSession(session) else { return }
                    _ = try await session.provider.send(SendMessageDraft(channelID: thread.id, content: message))
                } catch {
                    guard let self, isCurrentAccountSession(session) else { return }
                    appendBuiltInNotice("The thread could not be created.", in: channelID)
                }
            }
        case "gif":
            builtInExpressionPickerRequest = BuiltInExpressionPickerRequest(channelID: channelID, kind: .gif, query: string("query"))
        case "sticker":
            builtInExpressionPickerRequest = BuiltInExpressionPickerRequest(channelID: channelID, kind: .sticker, query: string("query"))
        default:
            appendBuiltInNotice("/\(invocation.command.name) isn’t available in SakuraCord yet.", in: channelID)
        }
    }

    /// The message Discord's text built-ins send, or nil for other built-ins.
    static func builtInMessageText(command: String, message: String) -> String? {
        switch command {
        case "shrug": "\(message) ¯\\_(ツ)_/¯".trimmingCharacters(in: .whitespacesAndNewlines)
        case "tableflip": "\(message) (╯°□°)╯︵ ┻━┻".trimmingCharacters(in: .whitespacesAndNewlines)
        case "unflip": "\(message) ┬─┬ノ( º _ ºノ)".trimmingCharacters(in: .whitespacesAndNewlines)
        case "me": "_\(message)_"
        case "spoiler": "||\(message)||"
        case "tts": message
        default: nil
        }
    }

    /// A private notice from a built-in, like Discord's local bot messages.
    func appendBuiltInNotice(_ text: String, in channelID: ChannelID) {
        appendInteractionFailureRow(
            nonce: ClientNonce.make(), channelID: channelID, application: DiscordBuiltInCommands.application,
            commandName: nil, message: text
        )
    }
}

struct BuiltInExpressionPickerRequest: Equatable {
    enum Kind { case gif, sticker }
    var channelID: ChannelID
    var kind: Kind
    var query: String
    var id = UUID()
}
