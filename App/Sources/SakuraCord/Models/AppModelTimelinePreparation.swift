import Foundation
import SakuraCordModels

extension AppModel {
    func messagePresentationChannel(_ channelID: ChannelID) -> Channel? {
        if let channels = snapshot?.channels {
            // Keep positions, never channel values. Revalidate the identity
            // after every reorder or replacement and read the current value,
            // including renamed channels and channels from a new account.
            if let index = messagePresentationChannelPositions[channelID],
               channels.indices.contains(index), channels[index].id == channelID {
                return channels[index]
            }
            if let index = channels.firstIndex(where: { $0.id == channelID }) {
                if messagePresentationChannelPositions.count >= 512 {
                    messagePresentationChannelPositions.removeAll(keepingCapacity: true)
                }
                messagePresentationChannelPositions[channelID] = index
                return channels[index]
            }
        }
        return visibleChannels.first { $0.id == channelID }
    }

    func restoreSelectedMessages(
        _ restoredMessages: [Message],
        preparedRows: [MessageRowPresentation]?
    ) {
        let oldMessages = messages
        messages = restoredMessages
        rebuildSelectedMessageIndexes()
        if let preparedRows,
           Self.rows(preparedRows, match: restoredMessages)
        {
            messageRows = preparedRows
        } else {
            messageRows = MessageGrouping.updating(
                existing: messageRows,
                oldMessages: oldMessages,
                newMessages: restoredMessages
            )
        }
        publishMessageRowsUpdate(invalidatesAllRows: true)
        messageRowsNonAppendRevision &+= 1
    }

    func prepareTimelineRows(
        for messages: [Message],
        priority: TaskPriority
    ) async -> [MessageRowPresentation] {
        let rows = await AppPerformanceSignposts.measure(
            "TimelineRowGrouping"
        ) {
            await Task.detached(priority: priority) {
                await MessageGrouping.rowsCooperatively(
                    for: messages
                )
            }.value
        }
        let preparations = rows.compactMap { row in
            NativeTimelineTextPresentation.preparation(
                message: row.message,
                plan: row.textPlan,
                model: self,
                baseFontSize: row.message.type.hasGeneratedContent
                    ? row.textPlan.baseFontSize
                    : InterfaceTypographyMetrics.messageTextSize
            )
        }
        let replyPreparations = rows.compactMap { row -> String? in
            guard let preview = row.replyPreview else { return nil }
            return MessageReplySummary.preparation(
                content: preview.content,
                mentionLabel: MessageMentionResolver(model: self, message: row.message).label
            )
        }
        guard !preparations.isEmpty || !replyPreparations.isEmpty else { return rows }
        let preparedReplies = await AppPerformanceSignposts.measure(
            "TimelineResolvedTextPrewarming"
        ) {
            await Task.detached(priority: priority) { () -> [MessageReplySummary.Prepared] in
                for (index, preparation) in preparations.enumerated() {
                    guard !Task.isCancelled else { return [] }
                    _ = autoreleasepool {
                        NativeTimelineTextPresentation.prewarm(preparation)
                    }
                    if (index + 1).isMultiple(of: 4),
                       index + 1 < preparations.endIndex
                    {
                        await Task.yield()
                    }
                }
                var replies: [MessageReplySummary.Prepared] = []
                for (index, source) in replyPreparations.enumerated() {
                    guard !Task.isCancelled else { return [] }
                    replies.append(MessageReplySummary.prepare(source))
                    if (index + 1).isMultiple(of: 4) {
                        await Task.yield()
                    }
                }
                return replies
            }.value
        }
        for prepared in preparedReplies {
            MessageReplySummary.install(prepared)
        }
        return rows
    }
}
