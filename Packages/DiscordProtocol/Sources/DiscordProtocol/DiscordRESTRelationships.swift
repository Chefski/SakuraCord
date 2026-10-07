import Foundation
import SakuraCordModels

/// One relationship record from `RELATIONSHIP_ADD`, `RELATIONSHIP_UPDATE` or
/// `RELATIONSHIP_REMOVE`.
struct GatewayRelationshipDTO: Decodable {
    var id: String
    var type: Int?
    var nickname: String?
}

extension DiscordRESTProvider {
    static let maximumFriendNicknameLength = 32

    func handleGatewayRelationshipEvent(name: String, body: JSONValue) async -> Bool {
        switch name {
        case "RELATIONSHIP_ADD", "RELATIONSHIP_UPDATE", "RELATIONSHIP_REMOVE":
            guard let dto = try? JSONValueDecoder().decode(GatewayRelationshipDTO.self, from: body),
                  let userID = UserID(dto.id)
            else { return true }
            relationshipRevisions[userID, default: 0] &+= 1
            var friends = cachedFriendUserIDs
            var nicknames = cachedRelationshipNicknamesByUserID
            if let type = dto.type, name != "RELATIONSHIP_REMOVE" {
                if type == 1 { friends.insert(userID) } else { friends.remove(userID) }
            }
            // Discord's RelationshipStore keeps an existing nickname when an
            // add omits one, but an update without a nickname clears it.
            switch name {
            case "RELATIONSHIP_REMOVE":
                friends.remove(userID)
                nicknames[userID] = nil
            case "RELATIONSHIP_UPDATE":
                nicknames[userID] = Self.normalizedFriendNickname(dto.nickname)
            default:
                if let nickname = Self.normalizedFriendNickname(dto.nickname) { nicknames[userID] = nickname }
            }
            publishRelationships(friendUserIDs: friends, nicknames: nicknames)
            return true
        default:
            return false
        }
    }

    /// Sets or clears the private nickname shown only to the current account.
    /// One PATCH, never replayed; blank text clears it with `null`. A
    /// rejected value stays in the dialog, and `RELATIONSHIP_UPDATE`
    /// reconciles other sessions.
    public func setFriendNickname(_ nickname: String?, for userID: UserID) async throws -> String? {
        guard let user = currentUser else { throw ChatProviderError.unauthenticated }
        let value = Self.normalizedFriendNickname(nickname)
        guard (value?.utf16.count ?? 0) <= Self.maximumFriendNicknameLength else {
            throw ChatProviderError.invalidRequest("Friend nicknames must be 32 characters or fewer.")
        }
        let revision = relationshipRevisions[userID, default: 0]
        let generation = profileEditingGeneration
        let path = "/users/@me/relationships/\(userID)"
        let (data, response) = try await perform(
            path, method: "PATCH", query: [], body: ["nickname": value.map(JSONValue.string) ?? .null]
        )
        guard (200 ..< 300).contains(response.statusCode) else {
            if response.statusCode == 400,
               let error = Self.profileValidationError(data: data, method: "PATCH", path: path)
            { throw apiDiagnostics.coalescing(error, with: response) }
            if response.statusCode == 401 {
                authorizationValue = nil
                throw apiDiagnostics.coalescing(ChatProviderError.unauthenticated, with: response)
            }
            throw apiDiagnostics.coalescing(ChatProviderError.transport(
                status: response.statusCode, requestID: response.value(forHTTPHeaderField: "x-request-id")
            ), with: response)
        }
        // Only this friend's events supersede the save; the generation also
        // guards READY and disconnect, which clear the per-user revisions.
        guard currentUser?.id == user.id, profileEditingGeneration == generation,
              relationshipRevisions[userID, default: 0] == revision else { return value }
        var nicknames = cachedRelationshipNicknamesByUserID
        nicknames[userID] = value
        publishRelationships(friendUserIDs: cachedFriendUserIDs, nicknames: nicknames)
        return value
    }

    static func normalizedFriendNickname(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Decodes a DM or group DM with its friend-nickname title.
    func privateChannel(from dto: ChannelDTO) throws -> Channel {
        applyingFriendNicknames(to: try dto.domain(guildID: nil, knownUsersByID: cachedGatewayUsersByID))
    }

    /// Discord titles an unnamed DM or group DM from its recipients, using the
    /// friend nickname in place of that recipient's name.
    func applyingFriendNicknames(to channel: Channel) -> Channel {
        guard channel.guildID == nil, !channel.hasExplicitName else { return channel }
        var channel = channel
        if channel.recipients.isEmpty {
            // A group whose last other member left falls back like a new one.
            guard channel.kind == .groupDirectMessage else { return channel }
            let owner = channel.ownerID.flatMap { cachedGatewayUsersByID[$0.description] }.flatMap { try? $0.domain() }
            channel.name = owner.map { "\($0.displayName)'s Group" } ?? "Group Direct Message"
            return channel
        }
        channel.name = channel.recipients
            .map { cachedRelationshipNicknamesByUserID[$0.id] ?? $0.displayName }
            .joined(separator: ", ")
        return channel
    }

    private func publishRelationships(friendUserIDs: Set<UserID>, nicknames: [UserID: String]) {
        guard friendUserIDs != cachedFriendUserIDs || nicknames != cachedRelationshipNicknamesByUserID else { return }
        let nicknamesChanged = nicknames != cachedRelationshipNicknamesByUserID
        cachedFriendUserIDs = friendUserIDs
        cachedRelationshipNicknamesByUserID = nicknames
        continuation?.yield(.relationshipsChanged(friendUserIDs: friendUserIDs, nicknames: nicknames))
        guard nicknamesChanged else { return }
        if let channels = cachedChannels[nil] {
            let renamed = channels.map(applyingFriendNicknames)
            if renamed != channels {
                cachedChannels[nil] = renamed
                continuation?.yield(.channelsChanged(guildID: nil, channels: renamed))
            }
        }
        continuation?.yield(.privateMembersChanged(privateMembersInChannelOrder()))
    }
}
