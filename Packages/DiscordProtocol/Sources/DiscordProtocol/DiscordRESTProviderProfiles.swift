import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    public func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        let key = ProfileCacheKey(userID: userID, guildID: guildID)
        if let cached = cachedProfiles[key] {
            return cached
        }
        if let task = profileTasks[key] {
            return try await task.value
        }
        let task = Task { [self] in
            try await loadProfile(for: userID, in: guildID)
        }
        profileTasks[key] = task
        do {
            let profile = try await task.value
            profileTasks[key] = nil
            cachedProfiles[key] = profile
            return profile
        } catch {
            profileTasks[key] = nil
            throw error
        }
    }

    func loadProfile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        var query = [
            URLQueryItem(name: "with_mutual_guilds", value: "true"),
            URLQueryItem(name: "with_mutual_friends", value: "true"),
            URLQueryItem(name: "with_mutual_friends_count", value: "true"),
        ]
        if let guildID {
            query.append(URLQueryItem(name: "guild_id", value: guildID.description))
        }
        let dto: UserProfileDTO
        do {
            dto = try await request("/users/\(userID)/profile", query: query)
        } catch ChatProviderError.transport(status: 404, requestID: _) {
            throw ChatProviderError.invalidRequest(
                "This profile is unavailable. You may no longer share a server or friendship with this user."
            )
        }

        let effectID =
            dto.guildMemberProfile?.profileEffect?.resolvedID
                ?? dto.userProfile?.profileEffect?.resolvedID
        if effectID != nil, profileEffects == nil { profileEffects = [:] }
        if let effectID, profileEffects?[effectID] == nil {
            let product = await collectibleProduct(for: effectID)
            for effect in product?.items?.elements.filter({ $0.type == 1 }) ?? [] {
                if let id = effect.id {
                    profileEffects?[id] = effect
                }
                if let skuID = effect.skuID {
                    profileEffects?[skuID] = effect
                }
            }
        }

        let profile = try dto.domain(
            guildID: guildID,
            guilds: cachedGuilds,
            guildRoles: guildID.flatMap { cachedGuildRoles[$0] } ?? [],
            effectConfig: effectID.flatMap { profileEffects?[$0] }
        )
        gatewayLogger.debug(
            "Profile assets resolved; bio=\(profile.bio?.isEmpty == false), badges=\(profile.badges.count), effect=\(profile.effect != nil), animations=\(profile.effect?.animations.count ?? 0)"
        )
        return profile
    }

    func collectibleProduct(for effectID: String) async -> CollectibleProductDTO? {
        if let task = collectibleProductTasks[effectID] {
            return await task.value
        }
        let task = Task<CollectibleProductDTO?, Never> { [self] in
            try? await request(
                "/collectibles-products/\(effectID)",
                query: [URLQueryItem(name: "locale", value: clientMetadata.locale)]
            )
        }
        collectibleProductTasks[effectID] = task
        let product = await task.value
        collectibleProductTasks[effectID] = nil
        return product
    }
}
