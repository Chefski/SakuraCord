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

    #expect(model.vote(on: message, answerIDs: [2]))
    var poll = try #require(model.messages.first?.poll)
    #expect(poll.selectedAnswerIDs == [2])
    #expect(poll.count(for: 2) == 2)

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
    #expect(await provider.requests() == [[2], [1]])
}

private actor PollVoteTestProvider: ChatProvider {
    private let user = User(id: UserID(rawValue: 99_001), username: "poll-tester", displayName: "Poll Tester")
    private let channel = Channel(id: ChannelID(rawValue: 99_002), guildID: nil, name: "poll-tests")
    private var recordedRequests: [[Int]] = []
    private var failsNextRequest = false
    private var continuation: AsyncStream<ClientEvent>.Continuation?
    private var requestContinuation: CheckedContinuation<Void, Never>?

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
                                              content: "", poll: poll)], hasMoreBefore: false)
    }

    func send(_ draft: SendMessageDraft) async throws -> Message {
        throw ChatProviderError.invalidRequest("Sending is not part of this test.")
    }

    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        throw ChatProviderError.invalidRequest("Editing is not part of this test.")
    }

    func delete(messageID: MessageID, channelID: ChannelID) async throws {}
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {}

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
