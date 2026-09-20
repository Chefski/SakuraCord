import DiscordProtocol
import Foundation
import SakuraCordModels
import Testing
@testable import SakuraCord

@MainActor
struct InboxTests {
    @Test func `opening paging and dismissing mentions never acknowledge a conversation`() async throws {
        let (model, provider) = await fixture()
        model.inbox.tab = .mentions
        model.presentInbox()
        await model.inbox.loadTask?.value
        #expect(model.inbox.mentions.count == 25)
        model.loadMoreInbox()
        await model.inbox.loadTask?.value
        #expect(model.inbox.mentions.count == 30)
        #expect(Set(model.inbox.mentions.map(\.id)).count == 30)
        let message = try #require(model.inbox.mentions.first)
        let unread = model.readState.entries[message.channelID]
        model.dismissInboxMention(message)
        await model.inbox.mutationTasks[message.id]?.value
        #expect(!model.inbox.mentions.contains { $0.id == message.id })
        #expect(model.readState.entries[message.channelID] == unread)
        #expect(await provider.acknowledgementRequests.isEmpty)
        #expect(await provider.bulkAcknowledgementRequests.isEmpty)
    }

    @Test func `Inbox marks only the captured boundary and undo uses the ordinary ACK contract`() async throws {
        let (model, provider) = await fixture()
        model.presentInbox()
        await model.inbox.loadTask?.value
        let group = try #require(model.inbox.groups.first)
        let sender = try #require(model.inbox.groups.first?.messages.first?.author)
        let incoming = Message(id: MessageID(rawValue: 900), channelID: group.id, author: sender, content: "arrived after opening", guildID: group.guildID)
        model.consumeImmediately(.messageCreated(incoming))
        #expect(model.inbox.groups.first?.newestUnreadMessageID == group.newestUnreadMessageID)
        model.markInboxGroupRead(group.id)
        await model.acknowledgementProcessorTask?.value
        #expect(await provider.acknowledgementRequests.last?.messageID == group.newestUnreadMessageID)
        #expect(model.readState.entries[group.id]?.latestKnownMessageID == incoming.id)
        #expect(model.readState.entries[group.id]?.isUnread == true)
        model.undoInboxRead()
        await model.acknowledgementProcessorTask?.value
        let undo = try #require(await provider.acknowledgementRequests.last)
        #expect(undo.messageID == group.oldestReadMessageID)
        #expect(!undo.manual)
        #expect(undo.mentionCount == nil)
        #expect(undo.lastViewed == 4200)
    }

    @Test(arguments: [false, true])
    func `bulk Inbox read respects its scope and account reset discards retained content`(serverOnly: Bool) async throws {
        let (model, provider) = await fixture()
        let guildID = GuildID(rawValue: 100)
        model.inbox.scheduledEvents = InboxScheduledEvents(
            events: [InboxScheduledEvent(id: ScheduledEventID(rawValue: 500), guildID: guildID,
                                         name: "Scheduled fixture", startTime: .now.addingTimeInterval(3600))],
            readStates: [guildID: InboxEventReadState(lastAcknowledgedID: ScheduledEventID(rawValue: 400),
                                                     latestID: ScheduledEventID(rawValue: 500), mentionCount: 1)]
        )
        model.presentInbox()
        await model.inbox.loadTask?.value
        let groups = model.inbox.groups
        #expect(groups.contains { $0.isEvents })
        if serverOnly {
            model.inbox.groups.append(InboxUnreadGroup(
                channelID: ChannelID(rawValue: 999), guildID: GuildID(rawValue: 998),
                title: "Unrelated server", subtitle: nil, oldestReadMessageID: nil,
                newestUnreadMessageID: MessageID(rawValue: 997), mentionCount: 1
            ))
            model.markInboxGuildRead(guildID)
        } else { model.markAllInboxRead() }
        await model.inbox.bulkTask?.value
        #expect(await provider.bulkAcknowledgementRequests.last == groups.map {
            BulkReadStateAcknowledgement(channelID: $0.id, messageID: $0.newestUnreadMessageID, readStateType: $0.isEvents ? 1 : 0)
        })
        #expect(await provider.acknowledgementRequests.isEmpty)
        #expect(model.inbox.groups.count == (serverOnly ? 1 : 0))
        model.inbox.clear(notifying: model)
        #expect(model.inbox.groups.isEmpty && model.inbox.mentions.isEmpty && model.inbox.rows.isEmpty)
        #expect(model.inbox.undoGroups.isEmpty && model.inbox.removedIDs.isEmpty)
        #expect(!model.inbox.isPresented)
        #expect(model.inbox.scheduledEvents.events.isEmpty && model.inbox.scheduledEvents.readStates.isEmpty)
    }

    @Test func `live mention filters edits and deletions preserve entry identity and never ACK`() async throws {
        let (model, provider) = await fixture()
        model.inbox.tab = .mentions
        model.presentInbox()
        await model.inbox.loadTask?.value
        let original = try #require(model.inbox.mentions.first)
        let unchangedRow = try #require(model.inbox.rows.last)
        var edited = original
        edited.content = "edited mention"
        model.consumeImmediately(.messageUpdated(edited))
        #expect(model.inbox.mentions.first?.content == "edited mention")
        #expect(model.inbox.rows.last === unchangedRow)
        model.consumeImmediately(.messageCreated(edited))
        #expect(model.inbox.mentions.filter { $0.id == edited.id }.count == 1)
        let selfMention = Message(id: MessageID(rawValue: 949), channelID: original.channelID,
                                  author: try #require(model.snapshot?.currentUser), content: "self mention",
                                  guildID: original.guildID, mentionedUsers: original.mentionedUsers)
        model.consumeImmediately(.messageCreated(selfMention))
        #expect(!model.inbox.mentions.contains { $0.id == selfMention.id })
        let everyone = Message(id: MessageID(rawValue: 950), channelID: original.channelID, author: original.author, content: "everyone", guildID: original.guildID, mentionsEveryone: true)
        model.inbox.query.includesEveryone = false
        model.consumeImmediately(.messageCreated(everyone))
        #expect(!model.inbox.mentions.contains { $0.id == everyone.id })
        model.consumeImmediately(.messageDeleted(channelID: original.channelID, messageID: original.id))
        #expect(!model.inbox.mentions.contains { $0.id == original.id })
        #expect(await provider.acknowledgementRequests.isEmpty)
    }

    @Test func `empty loaded groups acknowledge without undo but restricted headers remain unread`() async throws {
        let (model, provider) = await fixture()
        model.presentInbox()
        await model.inbox.loadTask?.value
        let group = try #require(model.inbox.groups.first)
        model.inbox.groups[0].messages = []
        model.inbox.groups[0].isAgeRestricted = true
        #expect(!model.dismissEmptyInboxGroups())
        #expect(await provider.acknowledgementRequests.isEmpty)
        model.inbox.groups[0].isAgeRestricted = false
        #expect(model.dismissEmptyInboxGroups())
        await model.acknowledgementProcessorTask?.value
        #expect(await provider.acknowledgementRequests.last?.messageID == group.newestUnreadMessageID)
        #expect(model.inbox.groups.isEmpty && model.inbox.undoGroups.isEmpty)
    }

    @Test func `Unread keeps server order and channel positions independent of categories`() async throws {
        let (model, _) = await fixture()
        var snapshot = try #require(model.snapshot)
        let firstGuild = GuildID(rawValue: 101)
        let secondGuild = GuildID(rawValue: 100)
        snapshot.guilds.append(Guild(id: firstGuild, name: "First server", isOwnedByCurrentUser: true))
        snapshot.guildRailItems = [.guild(firstGuild), .guild(secondGuild)]
        let newest = MessageID(rawValue: 500)
        let laterCategory = Channel(id: ChannelID(rawValue: 210), guildID: firstGuild, name: "Earlier channel",
                                    position: 1, categoryPosition: 9, lastMessageID: newest)
        let earlierCategory = Channel(id: ChannelID(rawValue: 211), guildID: firstGuild, name: "Later channel",
                                      position: 2, categoryPosition: 0, lastMessageID: newest)
        let thread = MessageThreadSummary(id: ChannelID(rawValue: 220), guildID: firstGuild,
                                          parentID: laterCategory.id, name: "Joined thread", lastMessageID: newest)
        snapshot.channels += [earlierCategory, laterCategory]
        snapshot.activeJoinedThreads = [thread]
        model.snapshot = snapshot
        model.readState.merge(guilds: snapshot.guilds)
        model.readState.merge(channels: snapshot.channels)
        model.readState.merge(thread: thread)
        for id in [laterCategory.id, earlierCategory.id, thread.id] {
            model.readState.applyRemote(ChannelReadState(channelID: id,
                lastAcknowledgedMessageID: MessageID(rawValue: 300), mentionCount: 1))
        }
        #expect(model.makeInboxUnreadGroups().map(\.id) == [laterCategory.id, thread.id, earlierCategory.id, ChannelID(rawValue: 200)])
        model.readState.applyRemote(ChannelReadState(channelID: laterCategory.id,
            lastAcknowledgedMessageID: MessageID(rawValue: 300), mentionCount: 1, flags: 4))
        #expect(model.makeInboxUnreadGroups().map(\.id) == [thread.id, earlierCategory.id, ChannelID(rawValue: 200), laterCategory.id])
        model.consumeImmediately(.messageCreated(Message(
            id: MessageID(rawValue: 600), channelID: laterCategory.id,
            author: try #require(snapshot.knownUsers.first { $0.id != snapshot.currentUser.id }),
            content: "A new direct mention promotes this channel", guildID: firstGuild,
            mentionedUsers: [snapshot.currentUser]
        )))
        #expect(model.makeInboxUnreadGroups().map(\.id) == [laterCategory.id, thread.id, earlierCategory.id, ChannelID(rawValue: 200)])
    }

    private func fixture() async -> (AppModel, MockChatProvider) {
        let user = User(id: UserID(rawValue: 1), username: "reader", displayName: "Reader")
        let sender = User(id: UserID(rawValue: 2), username: "sender", displayName: "Sender")
        let guildID = GuildID(rawValue: 100)
        let channelID = ChannelID(rawValue: 200)
        let messages = (1 ... 30).map { offset in
            Message(id: MessageID(rawValue: UInt64(300 + offset)), channelID: channelID,
                    author: sender, content: "Inbox \(offset)", guildID: guildID, mentionedUsers: [user])
        }
        let snapshot = BootstrapSnapshot(
            currentUser: user, knownUsers: [user, sender],
            guilds: [Guild(id: guildID, name: "Inbox fixture", isOwnedByCurrentUser: true)],
            channels: [Channel(id: channelID, guildID: guildID, name: "general", lastMessageID: messages.last?.id)],
            members: [], readStates: [ChannelReadState(channelID: channelID, lastAcknowledgedMessageID: MessageID(rawValue: 300), mentionCount: 30, flags: 1, lastViewed: 4200)]
        )
        let provider = MockChatProvider(snapshot: snapshot, messages: messages)
        let model = AppModel(launchMode: .offlineTesting, provider: provider)
        await model.start()
        return (model, provider)
    }
}
