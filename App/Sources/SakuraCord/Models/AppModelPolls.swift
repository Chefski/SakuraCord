import DiscordProtocol
import Foundation
import SakuraCordModels

/// The current user's poll selection while a vote request is pending.
struct PollVoteMutationState {
    var channelID: ChannelID
    var confirmed: Set<Int>
    var desired: Set<Int>
    var isSending: Bool
}

private extension Message {
    func selectingCurrentUserPollAnswers(_ answerIDs: Set<Int>) -> Message {
        guard let poll, poll.results != nil, poll.selectedAnswerIDs != answerIDs else { return self }
        var result = self
        for update in MessagePollUpdate.currentUserSelection(from: poll.selectedAnswerIDs, to: answerIDs) {
            update.apply(to: &result)
        }
        return result
    }
}

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
        // The poll appears as an outgoing message with retry, so the creator
        // does not wait for the server.
        startAccountChildTask(account: session) { model, _ in
            _ = await model.sendChannelMessage(channelID: channelID, content: "", replyTo: nil,
                                               replyPreview: nil, attachments: [], clearsComposer: false, poll: poll)
        }
        return .enqueued(serverConfirmed: false)
    }

    /// Shows the current user's selection immediately and coalesces requests.
    /// Gateway echoes of the current user's vote are idempotent.
    @discardableResult
    func vote(on message: Message, answerIDs: Set<Int>) -> Bool {
        guard let poll = (retainedMessage(channelID: message.channelID, messageID: message.id) ?? message).poll,
              !poll.isClosed(), poll.layoutType == 1, poll.allowsMultipleAnswers || answerIDs.count <= 1,
              answerIDs.allSatisfy({ id in poll.answers.contains { $0.id == id } }) else { return false }
        var state = pollVoteMutations[message.id] ?? PollVoteMutationState(
            channelID: message.channelID, confirmed: poll.selectedAnswerIDs, desired: poll.selectedAnswerIDs, isSending: false
        )
        state.desired = answerIDs
        pollVoteMutations[message.id] = state
        applyCurrentUserPollSelection(answerIDs, messageID: message.id, channelID: message.channelID)
        sendPollVoteMutation(messageID: message.id)
        return true
    }

    private func sendPollVoteMutation(messageID: MessageID) {
        guard var state = pollVoteMutations[messageID], !state.isSending else { return }
        guard state.desired != state.confirmed else {
            pollVoteMutations[messageID] = nil
            return
        }
        let answerIDs = state.desired
        let channelID = state.channelID
        state.isSending = true
        pollVoteMutations[messageID] = state
        startAccountChildTask(account: accountSession()) { model, session in
            do {
                try await session.provider.setPollAnswers(answerIDs.sorted(), messageID: messageID, channelID: channelID)
            } catch {
                guard model.isCurrentAccountSession(session),
                      let latest = model.pollVoteMutations.removeValue(forKey: messageID) else { return }
                model.applyCurrentUserPollSelection(latest.confirmed, messageID: messageID, channelID: channelID)
                model.errorMessage = error.localizedDescription
                return
            }
            guard model.isCurrentAccountSession(session), var latest = model.pollVoteMutations[messageID] else { return }
            latest.confirmed = answerIDs
            latest.isSending = false
            model.pollVoteMutations[messageID] = latest
            if let message = model.retainedMessage(channelID: channelID, messageID: messageID) {
                model.recordAuthoritativeMessageUpsert(message)
            }
            model.sendPollVoteMutation(messageID: messageID)
            guard let message = model.retainedMessage(channelID: channelID, messageID: messageID) else { return }
            if message.poll?.results == nil { await model.loadUnknownPollResults(message) }
        }
    }

    private func applyCurrentUserPollSelection(_ answerIDs: Set<Int>, messageID: MessageID, channelID: ChannelID) {
        guard let message = retainedMessage(channelID: channelID, messageID: messageID) else { return }
        let updated = message.selectingCurrentUserPollAnswers(answerIDs)
        guard updated != message else { return }
        consumeMessageUpdated(updated, preparedTextPlan: nil, recordsRefreshMutation: false)
    }

    func pollVotePresentationPreserving(_ incoming: Message) -> Message {
        guard let mutation = pollVoteMutations[incoming.id], mutation.channelID == incoming.channelID else { return incoming }
        return incoming.selectingCurrentUserPollAnswers(mutation.desired)
    }

    func pollVoteConfirmedSnapshot(_ message: Message) -> Message {
        guard let mutation = pollVoteMutations[message.id], mutation.channelID == message.channelID else { return message }
        return message.selectingCurrentUserPollAnswers(mutation.confirmed)
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
