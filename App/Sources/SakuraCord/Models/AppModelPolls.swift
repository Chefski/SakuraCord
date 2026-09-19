import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func canCreatePoll(in channelID: ChannelID) -> Bool {
        let isThread = openThread?.id == channelID
        guard let channel = isThread ? selectedChannel : snapshot?.channels.first(where: { $0.id == channelID }),
              (isThread ? openThreadAccess : conversationAccess(for: channel)).canSend else { return false }
        guard let guildID = channel.guildID else { return true }
        guard let basis = conversationPermissionBasis(for: guildID),
              let permissions = ConversationPermissionResolver.effectivePermissions(
                guild: basis.guild, channel: channel,
                resolvedBasePermissions: basis.resolvedBasePermissions,
                overwritePrincipals: basis.overwritePrincipals,
                hasCurrentRoleIdentity: basis.hasCurrentRoleIdentity
              ) else { return false }
        return permissions & ((1 << 49) | DiscordPermissionBits.administrator) != 0
    }

    func createPoll(_ poll: PollDraft, in channelID: ChannelID) async -> ComposerSubmissionResult {
        guard canCreatePoll(in: channelID), allowSlowmodeSubmission(in: channelID) else { return .rejected }
        if let validationError = poll.validationError {
            errorMessage = validationError
            return .rejected
        }
        let session = accountSession()
        if channelID == selectedChannelID {
            guard await prepareChannelMessageSubmission(channelID: channelID, account: session) else { return .rejected }
        }
        guard isCurrentAccountSession(session), canCreatePoll(in: channelID) else { return .rejected }
        let confirmed = await sendChannelMessage(channelID: channelID, content: "", replyTo: nil,
                                        replyPreview: nil, attachments: [], clearsComposer: false, poll: poll)
        return .enqueued(serverConfirmed: confirmed)
    }

    func vote(on message: Message, answerIDs: Set<Int>) async -> Bool {
        let session = accountSession()
        do {
            try await session.provider.setPollAnswers(answerIDs.sorted(), messageID: message.id, channelID: message.channelID)
            return isCurrentAccountSession(session)
        } catch {
            guard isCurrentAccountSession(session) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func endPoll(_ message: Message) async {
        let session = accountSession()
        do {
            let updated = try await session.provider.endPoll(messageID: message.id, channelID: message.channelID)
            guard isCurrentAccountSession(session) else { return }
            let reconciled = reconcileVisibleOrCached(updated)
            recordAuthoritativeMessageUpsert(reconciled)
        } catch {
            guard isCurrentAccountSession(session) else { return }
            errorMessage = error.localizedDescription
        }
    }
}

extension AppModel {
    func reconcilePollSearchMessage(_ message: Message) {
        guard message.poll != nil, var page = messageSearch.page else { return }
        var changed = false
        for resultIndex in page.results.indices {
            for index in page.results[resultIndex].messages.indices
            where page.results[resultIndex].messages[index].id == message.id {
                guard page.results[resultIndex].messages[index].poll != message.poll else { continue }
                page.results[resultIndex].messages[index].poll = message.poll
                page.results[resultIndex].messages[index].hasPoll = true
                changed = true
            }
        }
        guard changed else { return }
        let oldRows = messageSearch.rows
        messageSearch.page = page
        messageSearch.rows = MessageSearchPresentation.rows(for: page, channelsByID: messageSearchChannelsByID(additionalChannels: page.channels))
        let revision = messageSearch.rowsRevision &+ 1
        messageSearch.rowsUpdateJournal.append(MessageRowsUpdateRecordBuilder.make(oldRows: oldRows, newRows: messageSearch.rows, revision: revision))
        messageSearch.rowsRevision = revision
    }

    func loadUnknownPollResults(_ message: Message) async {
        guard message.poll?.results == nil else { return }
        let session = accountSession()
        do {
            let page = try await session.provider.messages(in: message.channelID, anchoredAt: .around(message.id), limit: 1)
            guard isCurrentAccountSession(session), let updated = page.messages.first(where: { $0.id == message.id }) else { return }
            consumeImmediately(.messageUpdated(updated))
        } catch {
            guard isCurrentAccountSession(session) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
