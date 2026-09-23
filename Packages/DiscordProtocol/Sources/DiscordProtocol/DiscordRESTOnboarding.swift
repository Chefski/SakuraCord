import Foundation
import SakuraCordModels

public extension DiscordRESTProvider {
    func guildOnboarding(in guildID: GuildID) async throws -> GuildOnboarding {
        let value: GuildOnboarding = try await request("/guilds/\(guildID)/onboarding")
        guard value.guildID == guildID else { throw ChatProviderError.invalidRequest("Discord returned onboarding for a different server.") }
        return value
    }

    func refreshCurrentMember(in guildID: GuildID) async throws -> Member {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        // Bypass the normal member cache. Completion requires a fresh server flag,
        // including when a Gateway event raced the HTTP response or was missed.
        let members = try await requestMemberBatch([userID], guildID: guildID)
        guard let member = members.first(where: { $0.id == userID }) else {
            throw ChatProviderError.invalidRequest("Discord has not confirmed your server membership. Reconnect and try again.")
        }
        if cachedGuilds[guildID]?.features.contains("GUILD_ONBOARDING") == true, member.flags == nil {
            throw ChatProviderError.invalidRequest("Discord did not return your onboarding status. Reconnect to verify your membership.")
        }
        publishMemberChange(member, guildID: guildID)
        return member
    }

    func saveGuildOnboarding(in guildID: GuildID, responses: Set<String>, initial: Bool) async throws -> GuildOnboarding {
        let configuration = try await guildOnboarding(in: guildID)
        let valid = configuration.validResponses(responses, initial: initial)
        guard valid == responses else {
            throw ChatProviderError.invalidRequest("The server’s questions changed. Refresh and review your answers before saving.")
        }
        if let error = configuration.validationError(valid, initial: initial) {
            throw ChatProviderError.invalidRequest(error)
        }
        let member = try await refreshCurrentMember(in: guildID)
        guard !initial || member.requiresOnboarding else {
            throw ChatProviderError.invalidRequest("Your onboarding state changed. Refresh to continue.")
        }
        guard initial || !member.requiresOnboarding else {
            throw ChatProviderError.invalidRequest("Finish onboarding before changing your answers.")
        }
        let seen = JSONValue.number((Date.now.timeIntervalSince1970 * 1000).rounded())
        let prompts = configuration.questions(initial: initial)
        struct Confirmation: Decodable {
            var guildID: GuildID
            var userID: UserID
            var responses: [String]
            enum CodingKeys: String, CodingKey {
                case guildID = "guild_id", userID = "user_id", responses = "onboarding_responses"
            }
        }
        // Central transport never retries these mutations. A failed/ambiguous
        // response leaves the draft intact and requires fresh readback.
        let confirmation: Confirmation = try await request(
            "/guilds/\(guildID)/onboarding-responses", method: initial ? "POST" : "PUT",
            body: [
                "onboarding_responses": .array(valid.sorted().map(JSONValue.string)),
                "onboarding_prompts_seen": .object(Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, seen) })),
                "onboarding_responses_seen": .object(Dictionary(uniqueKeysWithValues: prompts.flatMap(\.options).map { ($0.id, seen) }))
            ]
        )
        guard confirmation.guildID == guildID, confirmation.userID == currentUser?.id,
              Set(confirmation.responses) == valid else {
            throw ChatProviderError.invalidRequest("Discord did not confirm all of your answers. Refresh before trying again.")
        }
        let confirmed = try await refreshCurrentMember(in: guildID)
        guard !initial || confirmed.flags.map({ $0 & 2 != 0 }) == true else {
            throw ChatProviderError.invalidRequest("Your answers were received, but Discord has not confirmed completion. Refresh to check again.")
        }
        let result = try await guildOnboarding(in: guildID)
        guard Set(result.responses) == valid else {
            throw ChatProviderError.invalidRequest("Your answers changed in another client. Refresh to review the latest choices.")
        }
        return result
    }

    func setGuildChannelSelected(_ selected: Bool, channelID: ChannelID, guildID: GuildID) async throws {
        let flags = cachedGuildNotificationSettings[guildID]?.channelOverrides.first { $0.channelID == channelID }?.flags ?? 0
        let updated = selected ? flags | GuildChannelSelection.selectedFlag : flags & ~GuildChannelSelection.selectedFlag
        try await updateGuildNotificationSettings(guildID: guildID, settings: [
            "channel_overrides": .object([channelID.description: .object(["flags": .number(Double(updated))])])
        ])
    }

    func setGuildChannelSelectionEnabled(_ enabled: Bool, guildID: GuildID) async throws {
        let flags = cachedGuildNotificationSettings[guildID]?.flags ?? 0
        let updated = enabled ? flags | GuildChannelSelection.enabledFlag : flags & ~GuildChannelSelection.enabledFlag
        try await updateGuildNotificationSettings(guildID: guildID, settings: ["flags": .number(Double(updated))])
    }
}
