import Foundation
import Observation
import SakuraCordModels

nonisolated struct InboxUnreadGroup: Equatable, Identifiable, Sendable {
    var id: ChannelID { channelID }
    let channelID: ChannelID
    let guildID: GuildID?
    let title: String
    let subtitle: String?
    let oldestReadMessageID: MessageID?
    let newestUnreadMessageID: MessageID
    let mentionCount: Int
    var isForum = false
    var isEvents = false
    var isAgeRestricted = false
    var events: [InboxScheduledEvent] = []
    var messages: [Message] = []
    var forumPosts: [ForumPost] = []
    var isLoaded = false
    var isCollapsed = false
    var errorMessage: String?
}

@MainActor
@Observable
final class InboxState {
    var scrollRequest = MessageTimelineScrollRequest(target: .top)
    var isPresented = false
    var selectedMessageID: MessageID?
    var tab = InboxTab.unread
    var query = InboxMentionQuery()
    var settings = InboxSettings()
    var scheduledEvents = InboxScheduledEvents()
    var selectedEvent: InboxScheduledEvent?
    var ageRestrictedGuildID: GuildID?
    var acceptedAgeRestrictedGuildIDs = Set((UserDefaults.standard.stringArray(forKey: "dev.sakuracord.inbox-age-agreements") ?? []).compactMap(GuildID.init))
    @ObservationIgnored var ageRestrictedAction: (@MainActor () -> Void)?
    @ObservationIgnored var eventMutationTasks: [GuildID: Task<Void, Never>] = [:]
    @ObservationIgnored var pendingEventAcknowledgements: [GuildID: ScheduledEventID] = [:]
    @ObservationIgnored var locallyUndoneEventGuilds: Set<GuildID> = []
    @ObservationIgnored var eventInterestTasks: [ScheduledEventID: Task<Void, Never>] = [:]
    var mentions: [Message] = []
    var hiddenMentionIDs: Set<MessageID> = []
    var obscuredMentionIDs: Set<MessageID> = []
    var visibleMentions: [Message] { mentions.filter { !hiddenMentionIDs.contains($0.id) } }
    var threads: [ChannelID: MessageThreadSummary] = [:]
    var groups: [InboxUnreadGroup] = []
    var undoGroups: [InboxUnreadGroup] = []
    @ObservationIgnored var unreadOrder: [ChannelID] = []
    @ObservationIgnored var pendingReadGroups: [ChannelID: InboxUnreadGroup] = [:]
    var isLoading = false
    var hasMore = false
    var errorMessage: String?
    var isSavingSettings = false
    var dismissingIDs: Set<MessageID> = []
    @ObservationIgnored var rows: [MessageRowPresentation] = []
    @ObservationIgnored var rowsRevision: UInt64 = 0
    @ObservationIgnored let rowsUpdateJournal = MessageRowsUpdateJournal()
    @ObservationIgnored var loadTask: Task<Void, Never>?
    @ObservationIgnored var generation: UInt64 = 0
    @ObservationIgnored var nextBefore: MessageID?
    // Tombstones and Gateway replacements win over an older in-flight page.
    @ObservationIgnored var removedIDs: Set<MessageID> = []
    @ObservationIgnored var deletedIDs: Set<MessageID> = []
    @ObservationIgnored var replacements: [MessageID: Message] = [:]
    @ObservationIgnored var metadataTasks: [ChannelID: Task<Void, Never>] = [:]
    @ObservationIgnored var mutationTasks: [MessageID: Task<Void, Never>] = [:]
    @ObservationIgnored var settingsSaveID = UUID()
    @ObservationIgnored var settingsTask: Task<Void, Never>?
    @ObservationIgnored var bulkTask: Task<Void, Never>?

    func rowInputs(channels: [Channel], guilds: [Guild]) -> [InboxMessageRowInput] {
        var messages = visibleMentions
        if tab == .unread {
            messages = []
            for group in groups where !group.isCollapsed {
                messages.append(contentsOf: group.messages)
                if !group.isLoaded { break }
            }
        }
        let channelsByID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let guildsByID = Dictionary(uniqueKeysWithValues: guilds.map { ($0.id, $0) })
        return messages.map { source in
            var message = source
            if tab == .mentions, obscuredMentionIDs.contains(message.id) {
                message.attachments = []
                message.embeds = []
                message.components = []
                message.stickers = []
                message.poll = nil
                message.hasPoll = false
                message.forwardedSnapshot = nil
            }
            let channel = channelsByID[message.channelID]
            let thread = threads[message.channelID]
            let isForumPost = groups.contains { $0.isForum && $0.channelID == thread?.parentID }
            let context: MessageSearchRowContext? = tab == .mentions || isForumPost ? MessageSearchRowContext(
                channelID: message.channelID,
                sectionTitle: thread?.name ?? channel?.name ?? "Conversation",
                sectionSubtitle: (message.guildID ?? channel?.guildID ?? thread?.guildID).flatMap { guildsByID[$0]?.name },
                systemImage: thread != nil ? "bubble.left.and.bubble.right" : channel?.guildID == nil ? "bubble.left" : "number",
                showsSectionHeader: true, isInbox: true
            ) : nil
            return InboxMessageRowInput(message: message, context: context)
        }
    }

    func publish(channels: [Channel], guilds: [Guild], preparedRows: [MessageRowPresentation]? = nil, notifying model: AnyObject) {
        let oldRows = rows
        rows = preparedRows ?? InboxMessageRowInput.reusingRows(rows, inputs: rowInputs(channels: channels, guilds: guilds))
        rowsRevision &+= 1
        rowsUpdateJournal.append(MessageRowsUpdateRecordBuilder.make(oldRows: oldRows, newRows: rows, revision: rowsRevision))
        NotificationCenter.default.post(name: .sakuracordMessageRowsDidChange, object: model)
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        generation &+= 1
        isLoading = false
    }

    func clear(notifying model: AnyObject) {
        cancelLoad()
        metadataTasks.values.forEach { $0.cancel() }
        metadataTasks = [:]
        mutationTasks.values.forEach { $0.cancel() }
        mutationTasks = [:]
        settingsTask?.cancel()
        settingsTask = nil
        bulkTask?.cancel()
        bulkTask = nil
        isPresented = false
        selectedMessageID = nil
        tab = .unread
        query = InboxMentionQuery()
        settings = InboxSettings()
        scheduledEvents = InboxScheduledEvents()
        selectedEvent = nil
        ageRestrictedGuildID = nil
        ageRestrictedAction = nil
        eventMutationTasks.values.forEach { $0.cancel() }
        eventMutationTasks = [:]
        eventInterestTasks.values.forEach { $0.cancel() }
        eventInterestTasks = [:]
        pendingEventAcknowledgements = [:]
        locallyUndoneEventGuilds = []
        mentions = []
        hiddenMentionIDs = []
        obscuredMentionIDs = []
        threads = [:]
        groups = []
        undoGroups = []
        unreadOrder = []
        pendingReadGroups = [:]
        nextBefore = nil
        hasMore = false
        errorMessage = nil
        isSavingSettings = false
        dismissingIDs = []
        removedIDs = []
        deletedIDs = []
        replacements = [:]
        publish(channels: [], guilds: [], notifying: model)
    }
}

nonisolated struct InboxMessageRowInput: Equatable, Sendable {
    let message: Message
    let context: MessageSearchRowContext?

    static func reusingRows(_ oldRows: [MessageRowPresentation], inputs: [Self]) -> [MessageRowPresentation] {
        let previous = Dictionary(uniqueKeysWithValues: oldRows.map { ($0.message.id, $0) })
        func continues(_ first: Self, _ second: Self) -> Bool {
            first.context == nil && second.context == nil && first.message.channelID == second.message.channelID
                && MessageGrouping.continuesGroup(from: first.message, to: second.message,
                                                  calendar: .autoupdatingCurrent,
                                                  continuationInterval: MessageGrouping.defaultContinuationInterval)
        }
        return inputs.enumerated().map { index, input in
            let message = input.message
            let startsGroup = index == 0 || !continues(inputs[index - 1], input)
            let endsGroup = index == inputs.count - 1 || !continues(input, inputs[index + 1])
            let startsDay = input.context == nil && (index == 0
                || inputs[index - 1].message.channelID != message.channelID
                || !Calendar.autoupdatingCurrent.isDate(inputs[index - 1].message.timestamp, inSameDayAs: message.timestamp))
            if let row = previous[message.id], row.message == message, row.searchContext == input.context,
               row.startsGroup == startsGroup, row.endsGroup == endsGroup, row.startsDay == startsDay { return row }
            return MessageRowPresentation(message: message, startsGroup: startsGroup, endsGroup: endsGroup, startsDay: startsDay,
                                          replyPreview: message.replyPreview, isReplyAvailable: message.replyPreview != nil,
                                          searchContext: input.context)
        }
    }
}
