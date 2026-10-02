import Foundation
import SakuraCordModels

public extension MockChatProvider {
    func applicationCommandCatalog(for target: ApplicationCommandIndexTarget) async throws
        -> ApplicationCommandCatalog
    {
        MockApplicationCommands.catalog(
            target: target,
            guildID: {
                if case .guild(let id) = target { return id }
                return nil
            }(),
            currentUser: currentUser
        )
    }

    func requestApplicationCommandAutocomplete(
        _ request: ApplicationCommandAutocompleteRequest
    ) async throws {
        _ = try ApplicationCommandPayloadBuilder.autocomplete(request)
        try await Task.sleep(for: .milliseconds(90))
        continuation?.yield(
            .applicationCommandAutocomplete(
                ApplicationCommandAutocompleteResult(
                    nonce: request.nonce,
                    choices: MockApplicationCommands.autocomplete(query: request.query)
                )
            )
        )
    }

    func executeApplicationCommand(
        _ invocation: ApplicationCommandInvocation,
        progress: @escaping @Sendable (ApplicationCommandProgress) -> Void
    ) async throws {
        let payload = try ApplicationCommandPayloadBuilder.execution(invocation)
        progress(.preparing)
        if !payload.attachmentURLs.isEmpty {
            progress(.reserving(files: payload.attachmentURLs.count))
            for url in payload.attachmentURLs {
                let size =
                    ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size])
                            as? NSNumber)?
                        .int64Value ?? 0
                progress(.uploading(fileName: url.lastPathComponent, completed: size, total: size))
            }
        }
        progress(.submitting(nonce: invocation.nonce))
        try await Task.sleep(for: .milliseconds(120))
        nextMessageID += 1
        continuation?.yield(
            .interaction(
                .created(nonce: invocation.nonce, interactionID: String(nextMessageID))
            )
        )
        progress(.awaitingResponse(nonce: invocation.nonce))
        let responseMode =
            invocation.command.name == "response"
                ? invocation.command.subcommandPath.last?.name
                : nil
        if responseMode == "failure" {
            continuation?.yield(
                .interaction(
                    .failed(
                        nonce: invocation.nonce,
                        message: "Synthetic interaction failure. No retry was attempted."
                    )
                )
            )
            return
        }
        let application = invocation.command.application
        let author =
            application.bot
                ?? User(
                    id: UserID(rawValue: 900_000_000_000_000_101), username: "verified",
                    displayName: application.name, isBot: true
                )
        let message = commandResponseMessage(
            for: invocation,
            responseMode: responseMode,
            application: application,
            author: author
        )
        messagesByChannel[invocation.channelID, default: []].append(message)
        continuation?.yield(.messageCreated(message))
        continuation?.yield(.interaction(.succeeded(nonce: invocation.nonce)))
        try await completeCommandResponse(
            message,
            invocation: invocation,
            responseMode: responseMode,
            application: application,
            author: author
        )
    }

    private func commandResponseMessage(
        for invocation: ApplicationCommandInvocation,
        responseMode: String?,
        application: ApplicationCommandApplication,
        author: User
    ) -> Message {
        Message(
            id: MessageID(rawValue: nextMessageID),
            channelID: invocation.channelID,
            author: author,
            content: responseMode == "deferred"
                ? "The offline app is working…"
                : "Offline command **/\(invocation.command.displayName)** completed successfully.",
            nonce: invocation.nonce,
            type: .chatInputCommand,
            flags: responseMode == "ephemeral"
                ? .ephemeral
                : (responseMode == "deferred" ? .loading : []),
            applicationID: ApplicationID(MockApplicationCommands.applicationID),
            application: application,
            interactionMetadata: MessageInteractionMetadata(
                id: String(nextMessageID), type: 2,
                name: invocation.command.displayName,
                user: currentUser,
                applicationID: invocation.command.applicationID
            ),
            guildID: invocation.guildID,
            components: [
                .container(
                    id: "offline-command-container", accentColor: 0x57F287, spoiler: false,
                    children: [
                        .textDisplay(
                            id: "offline-command-text",
                            content:
                            "### Verified\nThis response is a deterministic Components V2 fixture."
                        ),
                        .separator(id: "offline-command-separator", divider: true, spacing: 1),
                        .textDisplay(
                            id: "offline-command-state",
                            content: "No Discord request was made."
                        ),
                    ]
                )
            ],
            mentionedUsers: [currentUser]
        )
    }

    private func completeCommandResponse(
        _ initialMessage: Message,
        invocation: ApplicationCommandInvocation,
        responseMode: String?,
        application: ApplicationCommandApplication,
        author: User
    ) async throws {
        var message = initialMessage
        if responseMode == "deferred" {
            try await Task.sleep(for: .milliseconds(120))
            message.content = "The deferred offline response completed successfully."
            message.flags.remove(.loading)
            message.editedTimestamp = .now
            if let index = messagesByChannel[invocation.channelID]?.firstIndex(where: {
                $0.id == message.id
            }) {
                messagesByChannel[invocation.channelID]?[index] = message
            }
            continuation?.yield(.messageUpdated(message))
        } else if responseMode == "followup" {
            nextMessageID += 1
            let followup = Message(
                id: MessageID(rawValue: nextMessageID),
                channelID: invocation.channelID,
                author: author,
                content: "This is the synthetic follow-up response.",
                applicationID: ApplicationID(MockApplicationCommands.applicationID),
                application: application,
                guildID: invocation.guildID
            )
            messagesByChannel[invocation.channelID, default: []].append(followup)
            continuation?.yield(.messageCreated(followup))
        }
    }

    func submitComponentInteraction(_ submission: ComponentInteractionSubmission)
        async throws
    {
        if submission.customID == "offline-modal" {
            let modal = InteractionModal(
                customID: "offline-feedback", title: "Offline feedback",
                controls: [
                    .label(
                        id: "label", label: "Feedback",
                        description: "This synthetic modal never contacts Discord.",
                        child: .textInput(
                            id: "text", customID: "feedback", style: 2, label: nil, value: nil,
                            placeholder: "What should improve?", required: true, minLength: 3,
                            maxLength: 500
                        )
                    ),
                    .checkbox(
                        id: "checkbox", customID: "follow-up", label: "Allow a fictional follow-up",
                        value: false
                    ),
                ]
            )
            continuation?.yield(.interaction(.presentModal(nonce: submission.nonce, modal: modal)))
        } else {
            continuation?.yield(.interaction(.succeeded(nonce: submission.nonce)))
        }
    }

    func submitModal(_ submission: ModalSubmission, nonce: String) async throws {
        continuation?.yield(.interaction(.succeeded(nonce: nonce)))
    }

    func componentChoices(
        kind: ComponentSelectKind,
        query: String,
        guildID: GuildID?,
        channelID _: ChannelID
    ) async throws -> [ComponentSelectOption] {
        let members = try await members(in: guildID)
        let roles = Dictionary(
            members.flatMap(\.roles).map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        ).values
        let choices: [ComponentSelectOption]
        switch kind {
        case .string:
            choices = []
        case .user:
            choices = members.map(Self.componentChoice)
        case .role:
            choices = roles.map(Self.componentChoice)
        case .mentionable:
            choices =
                members.map(Self.componentChoice)
                + roles.map(Self.componentChoice)
        case .channel:
            choices = try await channels(in: guildID).map {
                ComponentSelectOption(
                    label: "#\($0.name)",
                    value: String($0.id.rawValue),
                    imageURL: $0.iconURL,
                    imageShape: .roundedRectangle
                )
            }
        }
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return choices
            .filter {
                normalizedQuery.isEmpty
                    || $0.label.localizedCaseInsensitiveContains(
                        normalizedQuery
                    )
                    || $0.description?.localizedCaseInsensitiveContains(
                        normalizedQuery
                    ) == true
            }
            .sorted {
                let comparison = $0.label.localizedCaseInsensitiveCompare(
                    $1.label
                )
                return comparison == .orderedSame
                    ? $0.value < $1.value
                    : comparison == .orderedAscending
            }
            .prefix(25)
            .map(\.self)
    }

    private static func componentChoice(
        for member: Member
    ) -> ComponentSelectOption {
        ComponentSelectOption(
            label: member.user.displayName,
            value: String(member.id.rawValue),
            description: "@\(member.user.username)",
            imageURL: member.user.avatarURL
        )
    }

    private static func componentChoice(
        for role: GuildRole
    ) -> ComponentSelectOption {
        ComponentSelectOption(
            label: "@\(role.name)",
            value: String(role.id.rawValue),
            imageURL: role.iconURL,
            imageShape: .roundedRectangle
        )
    }
}
