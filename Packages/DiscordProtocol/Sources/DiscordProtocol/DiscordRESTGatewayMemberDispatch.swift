import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayMemberEvent(
        name: String,
        body: JSONValue,
        data: Data
    ) async -> Bool {
        switch name {
        case "PRESENCE_UPDATE":
            await handlePresenceUpdateDispatch(name: name, body: body, data: data)
        case "VOICE_CHANNEL_STATUS_UPDATE", "VOICE_CHANNEL_START_TIME_UPDATE":
            await handleVoiceChannelStatusUpdateDispatch(name: name, body: body, data: data)
        case "VOICE_STATE_UPDATE":
            await handleVoiceStateUpdateDispatch(name: name, body: body, data: data)
        default:
            return false
        }
        return true
    }

    func handlePresenceUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(PresenceUpdateDTO.self, from: data)
        else { return }
        if update.guildID == nil {
            cachePrivatePresence(update)
            continuation?.yield(.privateMembersChanged(privateMembersInChannelOrder()))
            return
        }
        guard let guildID = update.guildID.flatMap(GuildID.init),
              let userID = UserID(update.user.id),
              let status = PresenceStatus(rawValue: update.status),
              var members = cachedMembers[guildID],
              let index = members.firstIndex(where: { $0.id == userID })
        else { return }
        members[index].status = status
        if let activities = update.activities {
            members[index].customStatus = activities.first(where: { $0.type == 4 })?.displayText
            members[index].activityText =
                activities.first(where: { $0.type != 4 })?.displayText
                    ?? members[index].customStatus
        }
        cachedMembers[guildID] = members
        if guildID == pendingMemberGuildID {
            continuation?.yield(
                .membersChanged(
                    guildID: guildID,
                    members: orderedMemberListMembers(guildID: guildID) ?? members,
                    groups: selectedMemberListGroups(guildID: guildID)
                )
            )
        }
    }

    func handleVoiceChannelStatusUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard
            let update = try? JSONDecoder().decode(
                GatewayVoiceChannelMetadataDTO.self, from: data
            ), let guildID = GuildID(update.guildID),
            cachedGuildChannelDTOs[guildID]?[update.id] != nil
        else { return }
        if name == "VOICE_CHANNEL_STATUS_UPDATE" {
            cachedGuildChannelDTOs[guildID]?[update.id]?.status = update.status
        } else {
            cachedGuildChannelDTOs[guildID]?[update.id]?.voiceStartTime =
                update.voiceStartTime
        }
        publishGuildChannels(guildID)
    }

    func handleVoiceStateUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let state = try? JSONDecoder().decode(VoiceStateUpdateDTO.self, from: data),
              let participant = state.domain()
        else { return }
        continuation?.yield(.voiceStateChanged(participant))
        reconcilePrivateCallVoiceState(participant)
        if participant.userID == currentUser?.id {
            if participant.channelID == nil {
                activeVoiceConnection = nil
            } else if participant.channelID == activeVoiceConnection?.channelID {
                activeVoiceConnection?.sessionID = participant.sessionID
            }
        }
        if participant.userID == currentUser?.id,
           participant.channelID == pendingVoiceNegotiation?.channelID
        {
            pendingVoiceNegotiation?.sessionID = participant.sessionID
            finishVoiceNegotiationIfReady()
        }
    }
}
