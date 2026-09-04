import Foundation
import SakuraCordModels

extension AppModel {
    func composerAttachments(
        for destination: MessageComposerDestination
    ) -> [ForumPostAttachment] {
        switch destination {
        case .channel: channelComposerAttachments
        case .thread: threadComposerAttachments
        }
    }

    func isComposerDropEligible(_ destination: MessageComposerDestination) -> Bool {
        switch destination {
        case .channel:
            guard commandComposer.activeCommand == nil,
                  selectedConversationAccess.canSend,
                  let kind = selectedChannel?.kind
            else { return false }
            return Self.supportsTyping(kind)
        case .thread:
            return openThread != nil && openThreadAccess.canSend
        }
    }

    @discardableResult
    func addPromisedComposerAttachments(
        _ batch: ComposerPromisedFileBatch,
        to destination: MessageComposerDestination
    ) -> Bool {
        let adoptedURLs = adoptPromisedFileBatch(batch)
        let didHandle = addComposerAttachments(adoptedURLs, to: destination)
        pruneOwnedPromisedAttachmentFiles()
        return didHandle
    }

    func preparePromisedAttachmentsForImmediateSend(
        _ batch: ComposerPromisedFileBatch,
        to destination: MessageComposerDestination
    ) -> [URL] {
        let adoptedURLs = adoptPromisedFileBatch(batch)
        guard isComposerDropEligible(destination) else {
            pruneOwnedPromisedAttachmentFiles()
            return []
        }
        let acceptedURLs = attachmentURLsWithinDiscordLimit(
            adoptedURLs,
            offeringExternalUploadFor: destination
        )
        let sentURLs = Array(
            acceptedURLs.prefix(SendMessageDraft.maximumAttachmentCount)
        )
        if acceptedURLs.count > sentURLs.count {
            errorMessage =
                "You can attach up to \(SendMessageDraft.maximumAttachmentCount) files to one message."
        }
        beginUsingOwnedPromisedFiles(sentURLs)
        pruneOwnedPromisedAttachmentFiles()
        return sentURLs
    }

    @discardableResult
    func addComposerAttachments(
        _ urls: [URL],
        to destination: MessageComposerDestination
    ) -> Bool {
        guard isComposerDropEligible(destination), !urls.isEmpty else { return false }
        let acceptedURLs = attachmentURLsWithinDiscordLimit(
            urls,
            offeringExternalUploadFor: destination
        )
        var attachments = composerAttachments(for: destination)
        let remaining = max(0, SendMessageDraft.maximumAttachmentCount - attachments.count)
        attachments.append(
            contentsOf: acceptedURLs.prefix(remaining).map { ForumPostAttachment(url: $0) }
        )
        setComposerAttachments(attachments, for: destination)
        if acceptedURLs.count > remaining {
            errorMessage =
                "You can attach up to \(SendMessageDraft.maximumAttachmentCount) files to one message."
        }
        // Claim a valid drop even when every file was rejected, preventing its path
        // from being inserted into the text field by the system fallback.
        return remaining > 0 || !urls.isEmpty
    }

    func removeComposerAttachment(
        _ id: UUID,
        from destination: MessageComposerDestination
    ) {
        var attachments = composerAttachments(for: destination)
        attachments.removeAll { $0.id == id }
        setComposerAttachments(attachments, for: destination)
    }

    func updateComposerAttachment(
        _ attachment: ForumPostAttachment,
        in destination: MessageComposerDestination
    ) {
        var attachments = composerAttachments(for: destination)
        guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return
        }
        attachments[index] = attachment
        setComposerAttachments(attachments, for: destination)
    }

    func toggleComposerAttachmentSpoiler(
        _ id: UUID,
        in destination: MessageComposerDestination
    ) {
        var attachments = composerAttachments(for: destination)
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[index].isSpoiler.toggle()
        setComposerAttachments(attachments, for: destination)
    }

    func clearComposerAttachments(for destination: MessageComposerDestination) {
        setComposerAttachments([], for: destination)
    }

    @discardableResult
    func consumeEscapeForComposerAttachments(
        in destination: MessageComposerDestination
    ) -> Bool {
        guard !composerAttachments(for: destination).isEmpty else { return false }
        clearComposerAttachments(for: destination)
        return true
    }

    @discardableResult
    func consumeEscapeForSupplementaryConversation() -> Bool {
        if openThread != nil {
            closeThread()
            return true
        }
        guard isVoiceChatOpen else { return false }
        closeVoiceChat()
        return true
    }

    func restoreComposerAttachments(
        _ restoredAttachments: [ForumPostAttachment],
        to destination: MessageComposerDestination
    ) {
        let current = composerAttachments(for: destination)
        var seen = Set(current.map(\.id))
        let restored = restoredAttachments.filter {
            seen.insert($0.id).inserted
        }
        setComposerAttachments(
            Array((restored + current).prefix(SendMessageDraft.maximumAttachmentCount)),
            for: destination
        )
    }

    @discardableResult
    func sendAttachmentsImmediately(
        _ attachments: [ForumPostAttachment],
        to destination: MessageComposerDestination
    ) async -> Bool {
        guard isComposerDropEligible(destination), !attachments.isEmpty,
              validateAttachmentCount(attachments)
        else { return false }
        switch destination {
        case .channel:
            guard let channelID = selectedChannelID else { return false }
            return await sendChannelMessage(
                channelID: channelID,
                content: "",
                replyTo: nil,
                replyPreview: nil,
                attachments: attachments,
                clearsComposer: false
            )
        case .thread:
            guard let thread = openThread else { return false }
            return await sendThreadMessage(
                content: "",
                attachments: attachments,
                thread: thread,
                clearsComposer: false
            )
        }
    }

    func setComposerAttachments(
        _ attachments: [ForumPostAttachment],
        for destination: MessageComposerDestination
    ) {
        switch destination {
        case .channel:
            channelComposerAttachments = attachments
        case .thread:
            threadComposerAttachments = attachments
        }
        pruneOwnedPromisedAttachmentFiles()
    }

    func validateAttachmentCount(_ attachments: [ForumPostAttachment]) -> Bool {
        guard attachments.count <= SendMessageDraft.maximumAttachmentCount else {
            errorMessage =
                "You can attach up to \(SendMessageDraft.maximumAttachmentCount) files to one message."
            return false
        }
        return true
    }
}
