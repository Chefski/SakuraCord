import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func open(_ thread: MessageThreadSummary) {
        guard openThread?.id != thread.id else { return }
        let starter = messages.first { $0.thread?.id == thread.id }
        openThreadConversation(
            thread,
            starter: starter?.author,
            startedAt: starter?.timestamp,
            initialMessages: []
        )
    }

    func open(_ post: ForumPost) {
        guard openThread?.id != post.id else { return }
        readState.merge(forumPost: post)
        openThreadConversation(
            post.thread,
            starter: post.owner ?? post.firstMessage?.author,
            startedAt: post.firstMessage?.timestamp ?? post.createdAt,
            initialMessages: post.firstMessage.map { [$0] } ?? []
        )
    }

    func openThreadConversation(
        _ thread: MessageThreadSummary,
        starter: User?,
        startedAt: Date?,
        initialMessages: [Message]
    ) {
        threadLoadTask?.cancel()
        AppPerformanceSignposts.beginConversationNavigation(to: thread.id)
        readState.merge(thread: thread)
        openThread = thread
        recordForwardDestinationVisit(thread.id)
        _ = readState.updatePresentation(
            channelID: thread.id,
            isPresented: true,
            initialHistoryLoaded: false,
            initialPositionEstablished: false,
            windowIsActive: mainWindowIsActive,
            hasReachedReadBoundary: false,
            blocksAutomaticAcknowledgement: false
        )
        openThreadStarter = starter
        openThreadStartedAt = startedAt
        let cachedMessages = takeCachedMessages(for: thread.id)
        let cachedBoundary = hasMoreCache[thread.id]
        threadMessages = Self.merging(
            current: initialMessages,
            fresh: cachedMessages
        )
        threadDraft = ""
        threadReplyingTo = nil
        clearComposerAttachments(for: .thread)
        hasMoreThreadMessages = cachedBoundary ?? false
        beginInitialThreadLoad(thread)
    }

    func beginInitialThreadLoad(_ thread: MessageThreadSummary) {
        threadLoadTask?.cancel()
        threadErrorMessage = nil
        threadErrorScope = nil
        if hasMoreCache[thread.id] != nil {
            isLoadingThread = false
            hasCompletedInitialThreadLoad = true
            readState.observeLoadedMessages(
                channelID: thread.id,
                messages: threadMessages
            )
            reportConversationHistoryLoaded(channelID: thread.id)
            return
        }
        isLoadingThread = true
        hasCompletedInitialThreadLoad = false
        let account = accountSession()
        threadLoadTask = startAccountChildTask(account: account) { model, account in
            let refreshRevision = model.beginConversationRefresh(in: thread.id)
            defer {
                model.endConversationRefresh(
                    in: thread.id,
                    revision: refreshRevision
                )
            }
            let loadSignpost = AppPerformanceSignposts.signposter.beginInterval(
                "ThreadConversationLoad"
            )
            defer {
                AppPerformanceSignposts.signposter.endInterval(
                    "ThreadConversationLoad",
                    loadSignpost
                )
            }
            async let freshPage = account.provider.messages(
                in: thread.id,
                before: nil,
                limit: 100
            )
            do {
                let page = try await freshPage
                guard !Task.isCancelled,
                      model.isCurrentAccountSession(account),
                      model.openThread?.id == thread.id
                else { return }
                try await model.finishInitialThreadLoad(
                    page,
                    threadID: thread.id,
                    refreshRevision: refreshRevision,
                    session: account
                )
            } catch is CancellationError {
                return
            } catch {
                guard model.isCurrentAccountSession(account),
                      model.openThread?.id == thread.id
                else { return }
                model.threadErrorMessage = error.localizedDescription
                model.threadErrorScope = .initialPage
                model.isLoadingThread = false
                model.hasCompletedInitialThreadLoad = true
            }
        }
    }

    func finishInitialThreadLoad(
        _ page: MessagePage,
        threadID: ChannelID,
        refreshRevision: UInt64,
        session: AppModelAccountSession
    ) async throws {
        guard isCurrentAccountSession(session) else { return }
        let mutations = conversationRefreshMutations(
            in: threadID,
            revision: refreshRevision
        )
        let refreshedMessages = Self.applyingConversationRefreshMutations(
            mutations,
            to: page.messages
        )
        threadMessages = Self.reconcilingNewestPage(
            current: threadMessages,
            fresh: refreshedMessages,
            hasMoreBefore: page.hasMoreBefore,
            authoritativeOldestMessageID: page.messages.map(\.id).min()
        )
        hasMoreThreadMessages = page.hasMoreBefore
        threadErrorMessage = nil
        threadErrorScope = nil
        isLoadingThread = false
        hasCompletedInitialThreadLoad = true
        readState.observeLoadedMessages(
            channelID: threadID,
            messages: threadMessages
        )
        reportConversationHistoryLoaded(channelID: threadID)
        hasMoreCache[threadID] = page.hasMoreBefore
    }

    func closeThread() {
        if let threadID = openThread?.id {
            cancelConversationRefresh(in: threadID)
            storeCachedMessages(threadMessages, for: threadID)
            hasMoreCache[threadID] = hasMoreThreadMessages
            unreadDividerMessageIDs[threadID] = nil
            if conversationNewestRequest?.channelID == threadID {
                conversationNewestRequest = nil
            }
            _ = readState.updatePresentation(channelID: threadID, isPresented: false)
        }
        threadLoadTask?.cancel()
        threadLoadTask = nil
        openThread = nil
        openThreadStarter = nil
        openThreadStartedAt = nil
        threadMessages = []
        threadDraft = ""
        threadReplyingTo = nil
        clearComposerAttachments(for: .thread)
        isLoadingThread = false
        hasCompletedInitialThreadLoad = false
        isLoadingEarlierThread = false
        hasMoreThreadMessages = false
        threadErrorMessage = nil
        threadErrorScope = nil
    }

    func openVoiceChat(for channel: Channel) {
        guard channel.kind == .voice else { return }
        if selectedChannelID != channel.id {
            selectedChannelID = channel.id
        }
        guard selectedChannelID == channel.id, !isVoiceChatOpen else { return }
        isVoiceChatOpen = true
        beginSelectedChannelLoad()
    }

    func closeVoiceChat() {
        guard isVoiceChatOpen else { return }
        if let selectedChannelID {
            cancelConversationRefresh(in: selectedChannelID)
        }
        channelLoadTask?.cancel()
        channelLoadTask = nil
        channelLoadGeneration &+= 1
        isVoiceChatOpen = false
        isLoadingMessages = false
        isLoadingEarlier = false
        messageLoadError = nil
    }

    func loadEarlierThread(account: AppModelAccountSession? = nil) async {
        let session = account ?? accountSession()
        guard !Task.isCancelled, isCurrentAccountSession(session) else { return }
        guard let thread = openThread, let first = threadMessages.first, hasMoreThreadMessages,
              !isLoadingEarlierThread
        else { return }
        threadErrorMessage = nil
        threadErrorScope = nil
        isLoadingEarlierThread = true
        defer {
            if isCurrentAccountSession(session), openThread?.id == thread.id {
                isLoadingEarlierThread = false
            }
        }
        do {
            let page = try await session.provider.messages(
                in: thread.id,
                before: first.id,
                limit: 50
            )
            guard !Task.isCancelled,
                  isCurrentAccountSession(session),
                  openThread?.id == thread.id
            else { return }
            let ids = Set(threadMessages.map(\.id))
            threadMessages.insert(contentsOf: page.messages.filter { !ids.contains($0.id) }, at: 0)
            hasMoreThreadMessages = page.hasMoreBefore
            threadErrorMessage = nil
            threadErrorScope = nil
            hasMoreCache[thread.id] = page.hasMoreBefore
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentAccountSession(session),
                  openThread?.id == thread.id
            else { return }
            threadErrorMessage = error.localizedDescription
            threadErrorScope = .earlierPage
        }
    }

    func retryThreadLoad() {
        guard let thread = openThread else { return }
        switch threadErrorScope {
        case .initialPage:
            beginInitialThreadLoad(thread)
        case .earlierPage:
            threadErrorMessage = nil
            threadErrorScope = nil
            let account = accountSession()
            startAccountChildTask(account: account) { model, account in
                await model.loadEarlierThread(account: account)
            }
        case .action, nil:
            return
        }
    }

    @discardableResult
    func sendThreadMessage(attachments: [URL] = []) async -> Bool {
        await sendThreadComposerMessage(
            attachments: attachments.map { ForumPostAttachment(url: $0) }
        )
    }

    @discardableResult
    func sendThreadComposerMessage(attachments: [ForumPostAttachment]) async -> Bool {
        await submitThreadComposerMessage(attachments: attachments).serverConfirmed
    }

    func submitThreadComposerMessage(
        attachments: [ForumPostAttachment]
    ) async -> ComposerSubmissionResult {
        guard let thread = openThread, openThreadAccess.canSend else { return .rejected }
        let content = threadDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !attachments.isEmpty else { return .rejected }
        guard validateAttachmentCount(attachments) else { return .rejected }
        let replyTo = threadReplyingTo?.id
        let mentionsRepliedUser = threadReplyMentionsAuthor
        let confirmed = await sendThreadMessage(
            content: content,
            replyTo: replyTo,
            mentionsRepliedUser: mentionsRepliedUser,
            replyPreview: threadReplyingTo.map(MessageReplyPreview.init),
            attachments: attachments,
            thread: thread,
            clearsComposer: true
        )
        return .enqueued(serverConfirmed: confirmed)
    }

    @discardableResult
    func sendThreadMessage(
        content: String,
        replyTo: MessageID? = nil,
        mentionsRepliedUser: Bool = true,
        replyPreview: MessageReplyPreview? = nil,
        attachments: [ForumPostAttachment],
        thread: MessageThreadSummary,
        clearsComposer: Bool
    ) async -> Bool {
        let draft = SendMessageDraft(
            channelID: thread.id,
            content: content,
            replyTo: replyTo,
            mentionsRepliedUser: mentionsRepliedUser,
            attachments: attachments
        )
        let optimistic = optimisticMessage(
            for: draft,
            replyPreview: replyPreview
        )
        appendOutgoingMessage(optimistic)
        outgoingMessages.draftsByNonce[draft.nonce] = draft
        if clearsComposer {
            threadDraft = ""
            threadReplyingTo = nil
        }
        let didSend = await performOutgoingSend(draft, isRetry: false)
        if didSend {
            completeConversationReadingAndAdvance(channelID: thread.id)
        }
        return didSend
    }

}
