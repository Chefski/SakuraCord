import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func discardFailedOutgoingMessage(_ message: Message) {
        guard message.outboxState == .failed,
              let nonce = message.nonce,
              outgoingState(
                nonce: nonce,
                channelID: message.channelID
              ) == .failed
        else { return }
        outgoingMessages.draftsByNonce[nonce] = nil
        outgoingMessages.stickerUploadSourceURLByNonce[nonce] = nil
        removeOutgoingMessage(
            nonce: nonce,
            channelID: message.channelID
        )
        pruneOwnedPromisedAttachmentFiles()
    }

    func outgoingMediaPresentationPreserving(
        _ incoming: Message
    ) -> Message {
        let existing: Message? = {
            let matches: (Message) -> Bool = { message in
                message.id == incoming.id
                    || (incoming.nonce != nil && message.nonce == incoming.nonce)
            }
            if incoming.channelID == openThread?.id,
               let message = threadMessages.first(where: matches)
            {
                return message
            }
            if incoming.channelID == selectedChannelID,
               let message = messages.first(where: matches)
            {
                return message
            }
            return messageCache[incoming.channelID]?.first(where: matches)
        }()
        guard let existing else { return incoming }

        var resolved = incoming
        resolved.nonce = resolved.nonce ?? existing.nonce
        if !existing.attachments.isEmpty {
            for index in resolved.attachments.indices {
                let attachment = resolved.attachments[index]
                guard attachment.mediaKind == .image
                        || attachment.mediaKind == .animatedImage
                else { continue }
                let previous = existing.attachments.first(where: {
                    $0.id == attachment.id
                }) ?? (existing.attachments.indices.contains(index)
                    ? existing.attachments[index]
                    : nil)
                let preservedPreviewURL: URL? = if let proxyURL = previous?.proxyURL {
                    proxyURL
                } else if previous?.url.isFileURL == true {
                    previous?.url
                } else {
                    nil
                }
                if let preservedPreviewURL, !attachment.url.isFileURL {
                    resolved.attachments[index].proxyURL = preservedPreviewURL
                }
            }
        }
        if !existing.stickers.isEmpty {
            for index in resolved.stickers.indices {
                let sticker = resolved.stickers[index]
                let previous = existing.stickers.first(where: {
                    $0.id == sticker.id
                }) ?? (existing.stickers.indices.contains(index)
                    ? existing.stickers[index]
                    : nil)
                if let mediaURL = previous?.mediaURL {
                    resolved.stickers[index].assetURL = mediaURL
                }
            }
        }
        return resolved
    }

    @discardableResult
    func send(attachments: [URL] = []) async -> Bool {
        await sendComposerMessage(
            attachments: attachments.map { ForumPostAttachment(url: $0) }
        )
    }

    @discardableResult
    func sendComposerMessage(attachments: [ForumPostAttachment]) async -> Bool {
        await submitComposerMessage(attachments: attachments).serverConfirmed
    }

    func submitComposerMessage(
        attachments: [ForumPostAttachment]
    ) async -> ComposerSubmissionResult {
        guard let channelID = selectedChannelID, selectedConversationAccess.canSend else {
            return .rejected
        }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !attachments.isEmpty else { return .rejected }
        guard validateAttachmentCount(attachments) else { return .rejected }
        if hasMoreLaterMessages {
            guard await loadNewestMessageWindow() else { return .rejected }
        }
        let replyTo = replyingTo?.id
        let mentionsRepliedUser = replyMentionsAuthor
        let replyPreview = replyingTo.map {
            MessageReplyPreview(message: $0)
        }
        let confirmed = await sendChannelMessage(
            channelID: channelID,
            content: content,
            replyTo: replyTo,
            mentionsRepliedUser: mentionsRepliedUser,
            replyPreview: replyPreview,
            attachments: attachments,
            clearsComposer: true
        )
        return .enqueued(serverConfirmed: confirmed)
    }

    @discardableResult
    func sendChannelMessage(
        channelID: ChannelID,
        content: String,
        replyTo: MessageID?,
        mentionsRepliedUser: Bool = true,
        replyPreview: MessageReplyPreview?,
        attachments: [ForumPostAttachment],
        clearsComposer: Bool
    ) async -> Bool {
        let outgoing = SendMessageDraft(
            channelID: channelID,
            content: content,
            replyTo: replyTo,
            mentionsRepliedUser: mentionsRepliedUser,
            attachments: attachments
        )
        if clearsComposer {
            stopLocalTyping(clearThrottle: true)
        }
        let optimistic = optimisticMessage(
            for: outgoing,
            replyPreview: replyPreview
        )
        appendOutgoingMessage(optimistic)
        outgoingMessages.draftsByNonce[outgoing.nonce] = outgoing
        if clearsComposer {
            replyingTo = nil
            updateDraft("")
        }
        let didSend = await performOutgoingSend(outgoing, isRetry: false)
        if didSend {
            completeConversationReadingAndAdvance(channelID: channelID)
        }
        return didSend
    }

    @discardableResult
    func retrySending(_ message: Message) async -> Bool {
        guard message.outboxState == .failed,
              let nonce = message.nonce,
              outgoingState(nonce: nonce, channelID: message.channelID) == .failed,
              let outgoing = outgoingMessages.draftsByNonce[nonce]
        else { return false }
        if let sourceURL = outgoingMessages.stickerUploadSourceURLByNonce[nonce] {
            updateOutgoingState(.uploading, nonce: nonce, channelID: message.channelID)
            return await performStickerUpload(
                outgoing,
                sourceURL: sourceURL,
                isRetry: true
            )
        }
        updateOutgoingState(.sending, nonce: nonce, channelID: message.channelID)
        return await performOutgoingSend(outgoing, isRetry: true)
    }

    func performOutgoingSend(_ outgoing: SendMessageDraft, isRetry: Bool) async -> Bool {
        let session = accountSession()
        let attachmentURLs = outgoing.attachmentURLs
        beginUsingOwnedPromisedFiles(attachmentURLs)
        let securityScopedURLs = attachmentURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer {
            for url in securityScopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
            endUsingOwnedPromisedFiles(attachmentURLs)
        }
        Self.messageSendLogger.info(
            """
            Message send started channel=\(outgoing.channelID.description, privacy: .public) \
            nonce=\(outgoing.nonce, privacy: .public) attachments=\(outgoing.attachmentURLs.count) \
            stickers=\(outgoing.stickerIDs.count) retry=\(isRetry)
            """
        )
        do {
            let confirmed = try await session.provider.send(outgoing)
            guard isCurrentAccountSession(session) else { return false }
            let reconciled = reconcileVisibleOrCached(confirmed)
            outgoingMessages.draftsByNonce[outgoing.nonce] = nil
            outgoingMessages.stickerUploadSourceURLByNonce[outgoing.nonce] = nil
            journalAuthoritativeMessageUpsert(reconciled)
            guard isCurrentAccountSession(session) else { return false }
            Self.messageSendLogger.info(
                """
                Message send succeeded channel=\(outgoing.channelID.description, privacy: .public) \
                nonce=\(outgoing.nonce, privacy: .public) \
                message=\(confirmed.id.description, privacy: .public) retry=\(isRetry)
                """
            )
            return true
        } catch {
            guard isCurrentAccountSession(session) else { return false }
            let state: OutboxState
            if (error as? URLError)?.code == .timedOut {
                state = .awaitingReconciliation
                updateOutgoingState(state, nonce: outgoing.nonce, channelID: outgoing.channelID)
            } else {
                state = .failed
                updateOutgoingState(state, nonce: outgoing.nonce, channelID: outgoing.channelID)
            }
            let nsError = error as NSError
            Self.messageSendLogger.error(
                """
                Message send failed channel=\(outgoing.channelID.description, privacy: .public) \
                nonce=\(outgoing.nonce, privacy: .public) state=\(state.rawValue, privacy: .public) \
                retry=\(isRetry) errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code) \
                details=\(error.localizedDescription, privacy: .private(mask: .hash))
                """
            )
            return false
        }
    }

    func optimisticMessage(
        for outgoing: SendMessageDraft,
        replyPreview: MessageReplyPreview?,
        stickers: [MessageSticker] = []
    ) -> Message {
        let id = outgoingMessages.nextOptimisticMessageID()
        return Message(
            id: id,
            channelID: outgoing.channelID,
            author: snapshot?.currentUser
                ?? User(id: UserID(rawValue: 1), username: "me", displayName: "Me"),
            content: outgoing.content,
            replyTo: outgoing.replyTo,
            replyPreview: replyPreview,
            attachments: outgoing.attachments.enumerated().map {
                var presentation = OptimisticAttachmentPresentation.attachment(
                    for: $0.element.url,
                    index: $0.offset
                )
                presentation.filename = $0.element.filename
                presentation.description = $0.element.description
                presentation.isSpoiler = $0.element.isSpoiler
                return presentation
            },
            nonce: outgoing.nonce,
            outboxState: .sending,
            stickers: stickers
        )
    }

    func appendOutgoingMessage(_ message: Message) {
        if message.channelID == openThread?.id {
            var updated = threadMessages
            Self.insert(message, intoSorted: &updated)
            threadMessages = updated
        } else if message.channelID == selectedChannelID {
            appendSelectedMessage(message)
        } else {
            cache(message)
        }
    }
}
