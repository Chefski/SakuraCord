import DiscordProtocol
import Foundation
@testable import SakuraCord
import SakuraCordModels
import Testing

@MainActor
@Test func `poll votes apply before confirmation ignore their echo and roll back on failure`() async throws {
    let provider = PollVoteTestProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()
    let message = try #require(model.messages.first { $0.poll != nil })
    model.pinnedMessages.items = [PinnedMessage(pinnedAt: .now, message: message)]
    model.inbox.tab = .mentions
    let refresh = model.beginConversationRefresh(in: message.channelID)

    #expect(model.vote(on: message, answerIDs: [2]))
    var poll = try #require(model.messages.first?.poll)
    #expect(poll.selectedAnswerIDs == [2])
    #expect(poll.count(for: 2) == 2)
    model.presentInbox()
    await model.inbox.loadTask?.value
    #expect(model.inbox.mentions.first?.poll?.selectedAnswerIDs == [2])
    model.messageSearch.queryText = "Lunch"
    model.submitMessageSearch()
    await provider.waitForSearch()
    // An optimistic selection is presentation, not an authoritative history edit.
    let mutations = model.conversationRefreshMutations(in: message.channelID, revision: refresh)
    #expect(AppModel.applyingConversationRefreshMutations(mutations, to: [message]).first?.poll == message.poll)
    // A server snapshot arriving before the vote response must keep every
    // retained surface on the same pending selection.
    model.consumeImmediately(.messageUpdated(message))
    #expect(model.pinnedMessages.items.first?.message.poll == model.messages.first?.poll)
    #expect(model.inbox.mentions.first?.poll == model.messages.first?.poll)
    model.replaceSelectedMessages(with: [message])
    #expect(model.messages.first?.poll?.selectedAnswerIDs == [2])
    model.presentPinnedMessages()
    await model.pinnedMessages.loadTask?.value
    #expect(model.pinnedMessages.errorMessage == nil)
    #expect(model.pinnedMessages.items.first?.message.poll?.selectedAnswerIDs == [2])

    var echo = MessageUpdate(messageID: message.id, channelID: message.channelID)
    echo.pollUpdates = [.vote(answerID: 2, isAddition: true, isCurrentUser: true)]
    var otherVote = MessageUpdate(messageID: message.id, channelID: message.channelID)
    otherVote.pollUpdates = [.vote(answerID: 1, isAddition: true, isCurrentUser: false)]
    await provider.emit(.messagePatched(echo))
    await provider.emit(.messagePatched(otherVote))
    #expect(await eventually { model.messages.first?.poll?.count(for: 1) == 2 })
    await provider.resumeRequest()
    #expect(await eventually { model.pollVoteMutations.isEmpty })
    poll = try #require(model.messages.first?.poll)
    #expect(poll.selectedAnswerIDs == [2])
    #expect(poll.count(for: 2) == 2)
    await provider.resumeSearch()
    await model.messageSearch.requestTask?.value
    #expect(model.messageSearch.page?.messages.first?.poll?.selectedAnswerIDs == [2])
    #expect(model.messageSearch.rows.first?.message.poll?.count(for: 1) == 2)

    await provider.failNextRequest()
    #expect(model.vote(on: message, answerIDs: [1]))
    poll = try #require(model.messages.first?.poll)
    #expect(poll.selectedAnswerIDs == [1])
    #expect(poll.count(for: 1) == 3 && poll.count(for: 2) == 1)
    await provider.resumeRequest()
    #expect(await eventually { model.pollVoteMutations.isEmpty })
    poll = try #require(model.messages.first?.poll)
    #expect(poll.selectedAnswerIDs == [2])
    #expect(poll.count(for: 1) == 2 && poll.count(for: 2) == 2)
    let confirmedMutations = model.conversationRefreshMutations(in: message.channelID, revision: refresh)
    #expect(AppModel.applyingConversationRefreshMutations(confirmedMutations, to: [message]).first?.poll == poll)
    model.endConversationRefresh(in: message.channelID, revision: refresh)
    #expect(await provider.requests() == [[2], [1]])
}

@MainActor
@Test func `guide resource messages reconcile reactions and pending poll votes`() async throws {
    let provider = PollVoteTestProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()
    let message = try #require(model.messages.first { $0.poll != nil })
    let guildID = GuildID(rawValue: 99_003)
    model.replaceSelectedMessages(with: [])
    model.messageCache.removeAll()
    model.selectedGuildID = guildID
    model.onboarding.presentedGuildID = guildID
    model.onboarding.page = .guide
    model.onboarding.guides[guildID] = GuildGuideEntry(resource: GuildResourceState(
        channelID: message.channelID, messages: [message], rows: [MessageRowPresentation(
            message: message, startsGroup: false, startsDay: false,
            replyPreview: nil, isReplyAvailable: false, isResource: true
        )]
    ))
    func resourceMessage() throws -> Message {
        try #require(model.onboarding.guides[guildID]?.resource?.rows.first?.message)
    }
    // The resource pane is the only retained copy; account actions must use it.
    _ = try #require(model.retainedMessage(channelID: message.channelID, messageID: message.id))
    await model.toggleReaction("👍", on: message)
    #expect(try resourceMessage().reactions.first?.didCurrentUserReact == true)
    #expect(await eventually { model.reactionMutations.isEmpty })
    await model.toggleReaction("👍", on: message)
    #expect(await eventually { model.reactionMutations.isEmpty })
    #expect(await provider.reactionRequests() == [true, false])
    model.consumeImmediately(.messageReactionUpdated(.add(
        channelID: message.channelID, messageID: message.id,
        userID: UserID(rawValue: 99_004), emoji: "👍", kind: .normal
    )))
    #expect(try resourceMessage().reactions.first?.count == 1)
    #expect(try resourceMessage().reactions.first?.didCurrentUserReact == false)
    let reactor = ReactionReactor(id: UserID(rawValue: 99_004), displayName: "Resource reader", avatarURL: nil)
    model.inbox.isPresented = true
    model.inbox.tab = .mentions
    model.inbox.mentions = [try resourceMessage()]
    model.applyReactionReactors([reactor], for: .init(
        channelID: message.channelID, messageID: message.id, reactionID: Reaction(emoji: "👍", count: 0).id
    ))
    #expect(try resourceMessage().reactions.first?.reactors == [reactor])
    #expect(model.inbox.mentions.first?.reactions.first?.reactors == [reactor])

    #expect(model.vote(on: message, answerIDs: [2]))
    #expect(try resourceMessage().poll?.selectedAnswerIDs == [2])
    model.consumeImmediately(.messageUpdated(message))
    #expect(try resourceMessage().poll?.selectedAnswerIDs == [2])
    var echo = MessageUpdate(messageID: message.id, channelID: message.channelID)
    echo.pollUpdates = [.vote(answerID: 2, isAddition: true, isCurrentUser: true)]
    model.consumeImmediately(.messagePatched(echo))
    #expect(try resourceMessage().poll?.count(for: 2) == 2)
    await provider.resumeRequest()
    #expect(await eventually { model.pollVoteMutations.isEmpty })
    await provider.failNextRequest()
    #expect(model.vote(on: message, answerIDs: [1]))
    #expect(try resourceMessage().poll?.selectedAnswerIDs == [1])
    await provider.resumeRequest()
    #expect(await eventually { model.pollVoteMutations.isEmpty })
    #expect(try resourceMessage().poll?.selectedAnswerIDs == [2])
    #expect(try resourceMessage().poll?.count(for: 2) == 2)
}

private actor PollVoteTestProvider: ChatProvider {
    private let user = User(id: UserID(rawValue: 99_001), username: "poll-tester", displayName: "Poll Tester")
    private let channel = Channel(id: ChannelID(rawValue: 99_002), guildID: nil, name: "poll-tests")
    private var recordedRequests: [[Int]] = []
    private var recordedReactions: [Bool] = []
    private var failsNextRequest = false
    private var continuation: AsyncStream<ClientEvent>.Continuation?
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var searchContinuation: CheckedContinuation<Void, Never>?

    func bootstrap() async throws -> BootstrapSnapshot {
        BootstrapSnapshot(currentUser: user, guilds: [], channels: [channel], members: [])
    }

    func channels(in guildID: GuildID?) async throws -> [Channel] { [channel] }
    func members(in guildID: GuildID?) async throws -> [Member] { [] }

    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        throw ChatProviderError.invalidRequest("Profiles are not part of this test.")
    }

    func currentStatus() async -> PresenceStatus { .online }
    func updateStatus(_ status: PresenceStatus) async throws {}

    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        let poll = MessagePoll(question: "Lunch?", answers: [.init(id: 1, text: "Pizza"), .init(id: 2, text: "Sushi")],
                               expiry: .now.addingTimeInterval(3600),
                               results: PollResults(answerCounts: [.init(id: 1, count: 1), .init(id: 2, count: 1)]))
        return MessagePage(messages: [Message(id: MessageID(rawValue: 99_100), channelID: channel.id, author: user,
                                              content: "", isPinned: true, poll: poll)], hasMoreBefore: false)
    }

    func send(_ draft: SendMessageDraft) async throws -> Message {
        throw ChatProviderError.invalidRequest("Sending is not part of this test.")
    }

    func inboxMentions(_ query: InboxMentionQuery, before: MessageID?) async throws -> InboxMentionPage {
        let page = try await messages(in: channel.id, before: nil, limit: 25)
        return InboxMentionPage(messages: page.messages, nextBefore: nil, hasMore: false)
    }

    func searchMessages(_ query: MessageSearchQuery) async throws -> MessageSearchPage {
        let page = try await messages(in: channel.id, before: nil, limit: 25)
        await withCheckedContinuation { searchContinuation = $0 }
        return MessageSearchPage(messages: page.messages, totalResults: page.messages.count)
    }

    func waitForSearch() async {
        while searchContinuation == nil { await Task.yield() }
    }

    func resumeSearch() {
        searchContinuation?.resume()
        searchContinuation = nil
    }

    func pinnedMessages(in channelID: ChannelID, before: Date?, limit: Int) async throws -> PinnedMessagePage {
        let page = try await messages(in: channelID, before: nil, limit: limit)
        return PinnedMessagePage(items: page.messages.map { PinnedMessage(pinnedAt: .now, message: $0) }, hasMore: false)
    }

    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        throw ChatProviderError.invalidRequest("Editing is not part of this test.")
    }

    func delete(messageID: MessageID, channelID: ChannelID) async throws {}
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {}

    func setReaction(_ emoji: String, reacted: Bool, messageID: MessageID, channelID: ChannelID) async throws {
        recordedReactions.append(reacted)
    }

    func reactionRequests() -> [Bool] { recordedReactions }

    func setPollAnswers(_ answerIDs: [Int], messageID: MessageID, channelID: ChannelID) async throws {
        recordedRequests.append(answerIDs)
        await withCheckedContinuation { requestContinuation = $0 }
        if failsNextRequest {
            failsNextRequest = false
            throw ChatProviderError.invalidRequest("Synthetic vote failure.")
        }
    }

    func eventStream() async -> AsyncStream<ClientEvent> {
        AsyncStream { continuation = $0 }
    }

    func disconnect() async {
        searchContinuation?.resume()
        searchContinuation = nil
        requestContinuation?.resume()
        requestContinuation = nil
        continuation?.finish()
        continuation = nil
    }

    func resumeRequest() async {
        while requestContinuation == nil { await Task.yield() }
        requestContinuation?.resume()
        requestContinuation = nil
    }

    func failNextRequest() { failsNextRequest = true }
    func requests() -> [[Int]] { recordedRequests }
    func emit(_ event: ClientEvent) { continuation?.yield(event) }
}
