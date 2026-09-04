import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func handleGatewayInteractionEvent(
        name: String,
        body: JSONValue
    ) async -> Bool {
        switch name {
        case "GUILD_APPLICATION_COMMAND_INDEX_UPDATE":
            await handleGuildApplicationCommandIndexUpdateDispatch(name: name, body: body)
        case "RATE_LIMITED":
            await handleRateLimitedDispatch(name: name, body: body)
        case "USER_APPLICATION_UPDATE", "USER_APPLICATION_REMOVE":
            await handleUserApplicationUpdateDispatch(name: name, body: body)
        case "APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE":
            await handleApplicationCommandAutocompleteResponseDispatch(name: name, body: body)
        case "INTERACTION_CREATE":
            await handleInteractionCreateDispatch(name: name, body: body)
        case "INTERACTION_SUCCESS":
            await handleInteractionSuccessDispatch(name: name, body: body)
        case "INTERACTION_FAILURE":
            await handleInteractionFailureDispatch(name: name, body: body)
        case "INTERACTION_MODAL_CREATE":
            await handleInteractionModalCreateDispatch(name: name, body: body)
        default:
            return false
        }
        return true
    }

    func handleGuildApplicationCommandIndexUpdateDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard
            let update = try? JSONValueDecoder().decode(
                GatewayApplicationCommandIndexUpdateDTO.self, from: body
            ), let guildID = GuildID(update.guildID)
        else { return }
        let target = ApplicationCommandIndexTarget.guild(guildID)
        if cachedApplicationCommandCatalogs[target]?.version != update.version?.value {
            invalidateApplicationCommandCatalog(target)
        }
    }

    func handleRateLimitedDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard let rateLimit = try? JSONValueDecoder().decode(
            GatewayRateLimitedDTO.self, from: body
        ) else { return }
        gatewayOpcodeRateLimitDates[rateLimit.opcode] = Date().addingTimeInterval(
            max(0, rateLimit.retryAfter)
        )
        failGatewayRequests(rateLimited: rateLimit)
    }

    func handleUserApplicationUpdateDispatch(
        name: String,
        body: JSONValue
    ) async {
        invalidateApplicationCommandCatalog(.user)
    }

    func handleApplicationCommandAutocompleteResponseDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard
            let response = try? JSONValueDecoder().decode(
                GatewayApplicationCommandAutocompleteDTO.self, from: body
            )
        else { return }
        let nonce = response.nonce.value
        guard let optionType = pendingAutocompleteTypes.removeValue(forKey: nonce) else {
            return
        }
        autocompleteTimeoutTasks.removeValue(forKey: nonce)?.cancel()
        let choices = response.choices.compactMap { $0.domain(optionType: optionType) }
        continuation?.yield(
            .applicationCommandAutocomplete(
                ApplicationCommandAutocompleteResult(nonce: nonce, choices: choices)
            )
        )
    }

    func handleInteractionCreateDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard
            let event = try? JSONValueDecoder().decode(
                GatewayInteractionLifecycleDTO.self, from: body),
            let nonce = event.nonce?.value, let interactionID = event.id
        else { return }
        continuation?.yield(
            .interaction(.created(nonce: nonce, interactionID: interactionID))
        )
    }

    func handleInteractionSuccessDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard
            let event = try? JSONValueDecoder().decode(
                GatewayInteractionLifecycleDTO.self, from: body),
            let nonce = event.nonce?.value
        else { return }
        if pendingAutocompleteTypes[nonce] == nil {
            continuation?.yield(.interaction(.succeeded(nonce: nonce)))
        }
    }

    func handleInteractionFailureDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard
            let event = try? JSONValueDecoder().decode(
                GatewayInteractionLifecycleDTO.self, from: body),
            let nonce = event.nonce?.value
        else { return }
        pendingAutocompleteTypes[nonce] = nil
        autocompleteTimeoutTasks.removeValue(forKey: nonce)?.cancel()
        continuation?.yield(
            .interaction(
                .failed(
                    nonce: nonce,
                    message: event.errorMessage
                        ?? event.errorCode.map {
                            "Discord rejected the interaction (code \($0))."
                        }
                        ?? "Discord rejected the interaction."
                )
            )
        )
    }

    func handleInteractionModalCreateDispatch(
        name: String,
        body: JSONValue
    ) async {
        guard
            let event = try? JSONValueDecoder().decode(
                GatewayInteractionModalDTO.self, from: body
            )
        else { return }
        pendingModalContexts[event.nonce.value] = event
        continuation?.yield(
            .interaction(.presentModal(nonce: event.nonce.value, modal: event.modal))
        )
    }
}
