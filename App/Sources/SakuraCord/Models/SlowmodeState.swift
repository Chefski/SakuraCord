import Foundation
import Observation
import SakuraCordModels

/// Account-local confirmation state, shared by every way of sending a message.
@MainActor
@Observable
final class SlowmodeState {
    struct Confirmation {
        let messageID: MessageID
        let date: Date
        var deadline: Date
    }

    private var confirmations: [ChannelID: Confirmation] = [:]
    private var serverDeadlines: [ChannelID: Date] = [:]
    private(set) var pendingChannels: [ChannelID: Int] = [:]
    private(set) var rejectedAttempts: [ChannelID: UInt64] = [:]

    func remaining(in channelID: ChannelID, interval: Int, immune: Bool, now: Date = .now) -> Int {
        guard interval > 0, !immune else { return 0 }
        let confirmedDeadline = confirmations[channelID]?.deadline ?? .distantPast
        let deadline = serverDeadlines[channelID] ?? confirmedDeadline
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    func confirm(_ message: Message, interval: Int, at date: Date = .now) {
        guard message.outboxState == .confirmed,
              confirmations[message.channelID].map({ $0.messageID < message.id }) ?? true
        else { return }
        confirmations = confirmations.filter { $0.value.date > date.addingTimeInterval(-21600) }
        confirmations[message.channelID] = Confirmation(
            messageID: message.id, date: date, deadline: date.addingTimeInterval(Double(interval))
        )
        serverDeadlines[message.channelID] = nil
    }

    func updateIntervals(
        for channels: [Channel],
        replacing previousChannels: [Channel],
        now: Date = .now
    ) {
        let trackedIDs = Set(confirmations.keys).union(serverDeadlines.keys)
        guard !trackedIDs.isEmpty else { return }
        let trackedChannels = channels.filter { trackedIDs.contains($0.id) }
        guard !trackedChannels.isEmpty else { return }
        let previousIntervals = Dictionary(
            previousChannels.lazy.filter { trackedIDs.contains($0.id) }
                .map { ($0.id, $0.rateLimitPerUser) },
            uniquingKeysWith: { first, _ in first }
        )
        for channel in trackedChannels
        where previousIntervals[channel.id] != channel.rateLimitPerUser {
            updateInterval(in: channel.id, to: channel.rateLimitPerUser, now: now)
        }
    }

    /// A settings edit can shorten a running cooldown, but never extend it or
    /// create a fresh cooldown without another confirmed send.
    func updateInterval(in channelID: ChannelID, to interval: Int, now: Date = .now) {
        let maximumDeadline = now.addingTimeInterval(Double(max(0, interval)))
        if let confirmation = confirmations[channelID] {
            confirmations[channelID]?.deadline = min(confirmation.deadline, maximumDeadline)
        }
        if let deadline = serverDeadlines[channelID] {
            serverDeadlines[channelID] = min(deadline, maximumDeadline)
        }
    }

    func recover(channelID: ChannelID, retryAfter: TimeInterval, now: Date = .now) {
        guard retryAfter.isFinite, retryAfter > 0 else { return }
        serverDeadlines[channelID] = now.addingTimeInterval(retryAfter)
    }

    func begin(in channelID: ChannelID) { pendingChannels[channelID, default: 0] += 1 }
    func end(in channelID: ChannelID) {
        if pendingChannels[channelID, default: 0] <= 1 {
            pendingChannels[channelID] = nil
        } else {
            pendingChannels[channelID, default: 0] -= 1
        }
    }
    func reject(in channelID: ChannelID) { rejectedAttempts[channelID, default: 0] &+= 1 }

    func reset() {
        confirmations.removeAll()
        serverDeadlines.removeAll()
        pendingChannels.removeAll()
        rejectedAttempts.removeAll()
    }
}
