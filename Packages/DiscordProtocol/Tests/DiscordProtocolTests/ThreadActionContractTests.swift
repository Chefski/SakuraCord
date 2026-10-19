@testable import DiscordProtocol
import Foundation
import SakuraCordModels
import Synchronization
import Testing

/// Thread rename, membership, message-thread and browser contracts, following
/// the official client (web build 641004, observed 19 October 2026).
struct ThreadActionContractTests {
    private let fixture = ThreadActionFixture()
    private let parent = Channel(
        id: ChannelID(rawValue: 7), guildID: GuildID(rawValue: 1), name: "general",
        defaultAutoArchiveDuration: 1_440
    )

    @Test func `rename sends only the name after unarchiving an archived thread`() async throws {
        let provider = await makeProvider()
        let archived = ForumPost(thread: thread(isArchived: true))
        fixture.enqueue(threadJSON(name: "Old name", archived: false), threadJSON(name: "New name", archived: false))

        let renamed = try await provider.updateForumPost(archived, mutation: .name("  New name "))

        #expect(renamed.thread.name == "New name" && !renamed.thread.isArchived)
        #expect(fixture.requests.withLock { $0.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } }
            == ["PATCH /api/v9/channels/42", "PATCH /api/v9/channels/42"])
        #expect(fixture.bodies.withLock { $0 } == [
            .object(["archived": .bool(false)]), .object(["name": .string("New name")]),
        ])
        #expect(await provider.cachedForumPostForTesting(threadID: archived.id)?.thread.name == "New name")
        await #expect(throws: ChatProviderError.self) {
            _ = try await provider.updateForumPost(renamed, mutation: .name(" \n "))
        }
        #expect(fixture.requests.withLock { $0.count } == 2)
        await provider.disconnect()
    }

    @Test func `join posts and leave deletes the current member with the surface location`() async throws {
        let provider = await makeProvider()
        fixture.enqueue("", "")

        try await provider.setThreadMembership(threadID: ChannelID(rawValue: 42), isJoined: true, location: .sidePaneMenu)
        #expect(await provider.activeJoinedThreadsForTesting().map(\.id) == [ChannelID(rawValue: 42)])
        try await provider.setThreadMembership(threadID: ChannelID(rawValue: 42), isJoined: false, location: .fullViewMenu)
        #expect(await provider.activeJoinedThreadsForTesting().isEmpty)

        let requests = fixture.requests.withLock { $0 }
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.absoluteString ?? "")" } == [
            "POST https://discord.com/api/v9/channels/42/thread-members/@me?location=Sidebar%20Overflow",
            "DELETE https://discord.com/api/v9/channels/42/thread-members/@me?location=Toolbar%20Overflow",
        ])
        #expect(fixture.bodies.withLock { $0.isEmpty })
        await provider.disconnect()
    }

    @Test func `a message thread posts the first-party body and gives its starter a thread card`() async throws {
        let provider = await makeProvider(seedsThread: false)
        let starter = Message(
            id: MessageID(rawValue: 500), channelID: parent.id,
            author: User(id: UserID(rawValue: 3), username: "author", displayName: "Author"),
            content: "Release notes\nmore", guildID: parent.guildID
        )
        await provider.seedMessageForTesting(starter)
        // Discord's starter update precedes the 201 and carries only the flag.
        await provider.receiveGatewayDispatchForTesting(name: "MESSAGE_UPDATE", data: .object([
            "id": .string("500"), "channel_id": .string("7"), "guild_id": .string("1"), "flags": .number(32),
        ]))
        fixture.enqueue(threadJSON(id: "500", name: "Release notes", archived: false, joined: true))

        let thread = try await provider.createThread(.startingFrom(starter, in: parent))

        #expect(thread.id == ChannelID(rawValue: 500) && thread.notificationSettings != nil)
        let request = try #require(fixture.requests.withLock { $0.first })
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://discord.com/api/v9/channels/7/messages/500/threads")
        #expect(fixture.bodies.withLock { $0 } == [.object([
            "name": .string("Release notes"), "type": .number(11),
            "auto_archive_duration": .number(1_440), "location": .string("Message"),
        ])])
        let card = await provider.cachedMessageForTesting(messageID: starter.id)
        #expect(card?.thread?.id == thread.id && card?.flags.contains(.hasThread) == true)
        #expect(await provider.activeJoinedThreadsForTesting().map(\.id) == [thread.id])
        await provider.disconnect()
    }

    @Test func `the thread browser pages archived threads and searches names with first-party queries`() async throws {
        let provider = await makeProvider(seedsThread: false)
        fixture.enqueue(
            #"{"threads":[\#(threadJSON(id: "60", name: "Archived notes", archived: true)),"#
                + #"\#(threadJSON(id: "61", name: "Old plans", archived: true))],"#
                + #""members":[{"id":"61","user_id":"9","join_timestamp":"2026-10-01T00:00:00+00:00","flags":1}],"#
                + #""has_more":true,"total_results":30}"#,
            #"{"threads":[\#(threadJSON(id: "61", name: "Old plans", archived: true))],"has_more":false,"total_results":1}"#
        )

        let page = try await provider.threadBrowserPage(in: parent.id, query: ThreadBrowserQuery())
        let search = try await provider.threadBrowserPage(in: parent.id, query: ThreadBrowserQuery(scope: .search(" plans ")))

        #expect(page.posts.map(\.thread.name) == ["Archived notes", "Old plans"])
        #expect(page.posts.map { $0.thread.notificationSettings != nil } == [false, true])
        #expect(page.hasMore && page.nextOffset == 2 && page.totalResults == 30)
        #expect(search.posts.map(\.id) == [ChannelID(rawValue: 61)] && search.totalResults == 1 && !search.hasMore)
        #expect(fixture.requests.withLock { $0.map { $0.url?.absoluteString ?? "" } } == [
            "https://discord.com/api/v9/channels/7/threads/search?archived=true&sort_by=last_message_time"
                + "&sort_order=desc&limit=25&tag_setting=match_some&offset=0",
            "https://discord.com/api/v9/channels/7/threads/search?name=plans&tag_setting=match_some",
        ])
        await provider.disconnect()
    }

    private func thread(isArchived: Bool) -> MessageThreadSummary {
        MessageThreadSummary(
            id: ChannelID(rawValue: 42), guildID: parent.guildID, parentID: parent.id, name: "Old name",
            isArchived: isArchived, ownerID: UserID(rawValue: 9)
        )
    }

    private func threadJSON(id: String = "42", name: String, archived: Bool, joined: Bool = false) -> String {
        let member = joined
            ? #","member":{"id":"\#(id)","user_id":"9","join_timestamp":"2026-10-19T00:30:00+00:00","flags":1}"#
            : ""
        return #"{"id":"\#(id)","guild_id":"1","parent_id":"7","type":11,"name":"\#(name)","owner_id":"9","#
            + #""thread_metadata":{"archived":\#(archived),"locked":false,"auto_archive_duration":1440}\#(member)}"#
    }

    private func makeProvider(seedsThread: Bool = true) async -> DiscordRESTProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ThreadActionURLProtocol.self]
        let provider = DiscordRESTProvider(
            credentials: TestCredentialStore(), handle: CredentialHandle(accountID: "thread-actions"),
            session: URLSession(configuration: configuration, delegate: fixture, delegateQueue: nil)
        )
        await provider.seedForumChannelForTesting(
            parent,
            posts: seedsThread ? [ForumPost(thread: thread(isArchived: false))] : [],
            currentUser: User(id: UserID(rawValue: 9), username: "me", displayName: "Me")
        )
        return provider
    }
}

private final class ThreadActionFixture: NSObject, URLSessionTaskDelegate {
    let requests = Mutex<[URLRequest]>([])
    let bodies = Mutex<[JSONValue]>([])
    let responses = Mutex<[String]>([])

    func enqueue(_ bodies: String...) {
        responses.withLock { $0 += bodies }
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        task.delegate = self
    }
}

private final class ThreadActionURLProtocol: URLProtocol, @unchecked Sendable {
    override static func canInit(with task: URLSessionTask) -> Bool { true }
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let fixture = task?.delegate as? ThreadActionFixture else {
            Issue.record("Thread transport is missing its test-owned fixture")
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        fixture.requests.withLock { $0.append(request) }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        if !body.isEmpty, let value = try? JSONDecoder().decode(JSONValue.self, from: body) {
            fixture.bodies.withLock { $0.append(value) }
        }
        let next = fixture.responses.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        guard let next else {
            Issue.record("Unexpected request \(request.url?.absoluteString ?? "")")
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let status = next.isEmpty ? 204 : (request.httpMethod == "POST" ? 201 : 200)
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Data(next.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
