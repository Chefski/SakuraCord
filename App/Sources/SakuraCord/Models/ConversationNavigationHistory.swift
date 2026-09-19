import Foundation
import SakuraCordModels

struct ConversationNavigationHistory {
    struct Destination: Equatable {
        let channelID: ChannelID
        fileprivate let index: Int
    }

    struct Navigation: Equatable {
        fileprivate let id = UUID()
        fileprivate let destination: Destination?
    }

    private struct Visit {
        let channelID: ChannelID
        let guildID: GuildID?
        let isTextChannel: Bool

        init(_ channel: Channel) {
            channelID = channel.id
            guildID = channel.guildID
            isTextChannel = channel.kind != .voice && channel.kind != .forum
        }
    }

    private var visits: [Visit] = []
    private var index = -1
    private var pendingNavigation: Navigation?
    private(set) var previousTextChannelID: ChannelID?
    private(set) var lastGuildID: GuildID?

    mutating func record(_ channel: Channel) {
        guard pendingNavigation == nil else { return }
        let visit = Visit(channel)
        guard index < 0 || visits[index].channelID != visit.channelID else { return }
        rememberPreviousVisit()
        visits = Array(visits.prefix(index + 1))
        visits.append(visit)
        if visits.count > 100 { visits.removeFirst() }
        index = visits.count - 1
        if let guildID = visit.guildID { lastGuildID = guildID }
    }

    func destination(direction: Int, isAvailable: (ChannelID) -> Bool) -> Destination? {
        guard direction == -1 || direction == 1 else { return nil }
        var target = index + direction
        while visits.indices.contains(target) {
            let channelID = visits[target].channelID
            if isAvailable(channelID),
               index < 0 || channelID != visits[index].channelID {
                return Destination(channelID: channelID, index: target)
            }
            target += direction
        }
        return nil
    }

    mutating func beginNavigation(to destination: Destination? = nil) -> Navigation {
        let navigation = Navigation(destination: destination)
        pendingNavigation = navigation
        return navigation
    }

    mutating func cancelNavigation() {
        pendingNavigation = nil
    }

    mutating func finishNavigation(_ navigation: Navigation, at channel: Channel?) {
        guard pendingNavigation == navigation else { return }
        pendingNavigation = nil
        guard let channel else { return }
        if let destination = navigation.destination,
           destination.channelID == channel.id {
            rememberPreviousVisit()
            index = destination.index
            if let guildID = channel.guildID { lastGuildID = guildID }
        } else {
            record(channel)
        }
    }

    private mutating func rememberPreviousVisit() {
        if visits.indices.contains(index), visits[index].isTextChannel {
            previousTextChannelID = visits[index].channelID
        }
    }
}
