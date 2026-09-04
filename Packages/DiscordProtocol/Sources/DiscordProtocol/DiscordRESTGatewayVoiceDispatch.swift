import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayVoiceEvent(
        name: String,
        body: JSONValue,
        data: Data
    ) async -> Bool {
        switch name {
        case "VOICE_SERVER_UPDATE":
            await handleVoiceServerUpdateDispatch(name: name, body: body, data: data)
        case "STREAM_CREATE", "STREAM_UPDATE":
            await handleStreamCreateDispatch(name: name, body: body, data: data)
        case "STREAM_SERVER_UPDATE":
            await handleStreamServerUpdateDispatch(name: name, body: body, data: data)
        case "STREAM_DELETE":
            await handleStreamDeleteDispatch(name: name, body: body, data: data)
        case "CALL_CREATE":
            await handleCallCreateDispatch(name: name, body: body, data: data)
        case "CALL_UPDATE":
            await handleCallUpdateDispatch(name: name, body: body, data: data)
        case "CALL_DELETE":
            await handleCallDeleteDispatch(name: name, body: body, data: data)
        default:
            return false
        }
        return true
    }

    func handleVoiceServerUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(VoiceServerUpdateDTO.self, from: data)
        else {
            return
        }
        if let pending = pendingVoiceNegotiation, update.matches(guildID: pending.guildID) {
            pendingVoiceNegotiation?.token = update.token
            pendingVoiceNegotiation?.endpoint = update.resolvedEndpoint
            finishVoiceNegotiationIfReady()
            return
        }
        guard let activeVoiceConnection,
              let resolution = VoiceServerMigrationResolver.resolve(
                  update: update,
                  activeConnection: activeVoiceConnection
              )
        else { return }
        switch resolution {
        case .waitForAllocation:
            continuation?.yield(.voiceServerChanged(nil))
        case .reconnect(let info):
            self.activeVoiceConnection = info
            continuation?.yield(.voiceServerChanged(info))
        }
    }

    func handleStreamCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(ApplicationStreamDTO.self, from: data),
              let key = ApplicationStreamKey(rawValue: update.streamKey),
              let stream = update.merging(applicationStreams[key])
        else { return }
        reconcileApplicationStream(stream)
    }

    func handleStreamServerUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(
            ApplicationStreamServerUpdateDTO.self,
            from: data
        ) else { return }
        reconcileApplicationStreamServer(update)
    }

    func handleStreamDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let deletion = try? JSONDecoder().decode(
            ApplicationStreamDeleteDTO.self,
            from: data
        ), let key = ApplicationStreamKey(rawValue: deletion.streamKey)
        else { return }
        if deletion.unavailable != true {
            applicationStreams[key] = nil
        }
        applicationStreamConnections[key] = nil
        failApplicationStreamNegotiation(
            key: key,
            error: ChatProviderError.invalidRequest(
                deletion.reason ?? "Discord ended the screen share."
            )
        )
        continuation?.yield(
            .applicationStreamDeleted(
                key: key,
                unavailable: deletion.unavailable ?? false,
                reason: deletion.reason
            )
        )
    }

    func handleCallCreateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(PrivateCallDTO.self, from: data),
              let call = update.domain()
        else { return }
        privateCallsByChannel[call.channelID] = call
        continuation?.yield(.privateCallChanged(call))
    }

    func handleCallUpdateDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let update = try? JSONDecoder().decode(PrivateCallDTO.self, from: data),
              let incoming = update.domain()
        else { return }
        let existing = privateCallsByChannel[incoming.channelID]
        let merged = PrivateCall(
            channelID: incoming.channelID,
            messageID: incoming.messageID ?? existing?.messageID,
            region: incoming.region ?? existing?.region,
            ongoingRings: update.ongoingRings == nil
                ? (existing?.ongoingRings ?? [])
                : incoming.ongoingRings,
            voiceStates: incoming.voiceStates ?? existing?.voiceStates,
            isUnavailable: update.unavailable ?? existing?.isUnavailable ?? false
        )
        privateCallsByChannel[merged.channelID] = merged
        continuation?.yield(.privateCallChanged(merged))
    }

    func handleCallDeleteDispatch(
        name: String,
        body: JSONValue,
        data: Data
    ) async {
        guard let deletion = try? JSONDecoder().decode(PrivateCallDeleteDTO.self, from: data),
              let channelID = ChannelID(deletion.channelID)
        else { return }
        privateCallsByChannel[channelID] = nil
        continuation?.yield(
            .privateCallDeleted(
                channelID: channelID,
                unavailable: deletion.unavailable ?? false
            )
        )
    }
}
