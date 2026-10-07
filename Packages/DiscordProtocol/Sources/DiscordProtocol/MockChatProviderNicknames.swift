import Foundation
import SakuraCordModels

public extension MockChatProvider {
    func setMemberNickname(_ nickname: String, for userID: UserID, in guildID: GuildID) async throws -> String? {
        let value = nickname.isEmpty ? nil : nickname
        guard var members = membersByGuild[guildID], let index = members.firstIndex(where: { $0.id == userID }) else {
            throw ChatProviderError.invalidRequest("That demo member is unavailable.")
        }
        let globalName = members[index].globalDisplayName ?? members[index].user.displayName
        members[index].globalDisplayName = globalName
        members[index].guildNickname = value
        members[index].user.displayName = value ?? globalName
        membersByGuild[guildID] = members
        continuation?.yield(.membersChanged(guildID: guildID, members: members, groups: []))
        return value
    }

    func setFriendNickname(_ nickname: String?, for userID: UserID) async throws -> String? {
        let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.relationshipNicknamesByUserID[userID] = value?.isEmpty == false ? value : nil
        // Like the live provider, retitle unnamed DMs and group DMs.
        let nicknames = snapshot.relationshipNicknamesByUserID
        snapshot.channels = snapshot.channels.map { channel in
            guard channel.guildID == nil, !channel.hasExplicitName, !channel.recipients.isEmpty else { return channel }
            var channel = channel
            channel.name = channel.recipients.map { nicknames[$0.id] ?? $0.displayName }.joined(separator: ", ")
            return channel
        }
        continuation?.yield(.relationshipsChanged(friendUserIDs: snapshot.friendUserIDs, nicknames: nicknames))
        continuation?.yield(.channelsChanged(guildID: nil, channels: snapshot.channels.filter { $0.guildID == nil }))
        continuation?.yield(.privateMembersChanged(try await members(in: nil)))
        return nicknames[userID]
    }
}
