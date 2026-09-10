import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func publishSavedProfilePresentations(
        _ saved: ProfileEditingResponseDTO, stage: ProfileSaveStage, scope: ProfileEditingScope
    ) throws {
        guard let userID = currentUser?.id else { throw CancellationError() }
        var sources = profileResponses.filter { $0.key.userID == userID }
        sources[ProfileCacheKey(userID: userID, guildID: scope.guildID)] = saved.profile
        for (key, var dto) in sources {
            mergeSavedProfile(saved.profile, into: &dto, stage: stage, scope: scope, targetGuildID: key.guildID)
            sources[key] = dto
        }
        // Prepare all affected surfaces before publishing, using the same DTO
        // resolver and loaded assets. Saving requires no follow-up profile GET.
        var presentations: [ProfileCacheKey: UserProfile] = [:]
        for (key, dto) in sources {
            let effectID = dto.guildMemberProfile?.profileEffect?.resolvedID ?? dto.userProfile?.profileEffect?.resolvedID
            presentations[key] = try dto.domain(
                guildID: key.guildID, guilds: cachedGuilds,
                guildRoles: key.guildID.flatMap { cachedGuildRoles[$0] } ?? [],
                effectConfig: effectID.flatMap { profileEffects?[$0] },
                frame: resolvedProfileFrame(skuID: dto.frameSKUID)
            )
            presentations[key]?.widgetResources = cachedProfileWidgetResources(for: userID)
            if let profileStatusSettings {
                presentations[key]?.customStatus = DiscordSettingsProto.customStatus(in: profileStatusSettings)?.displayText
            }
        }
        invalidateSavedProfilePresentation(for: userID)
        for (key, dto) in sources { profileResponses[key] = dto }
        for (key, profile) in presentations {
            cachedProfiles[key] = profile
            continuation?.yield(.profileChanged(
                userID: userID, scope: key.guildID.map(ProfileEditingScope.server) ?? .main, profile: profile
            ))
        }
        for (targetScope, var response) in profileEditingResponses {
            if let dto = sources[ProfileCacheKey(userID: userID, guildID: targetScope.guildID)] {
                response.profile = dto
            }
            if stage == .widgets {
                response.profile.widgets = saved.profile.widgets
            } else if scope == .main || stage == .serverTag {
                if stage == .metadata { response.metadata = saved.metadata } else { response.identity = saved.identity }
            } else if scope == targetScope {
                if stage == .metadata { response.serverMetadata = saved.serverMetadata } else { response.serverIdentity = saved.serverIdentity }
            }
            profileEditingResponses[targetScope] = response
        }
        profileEditingResponses[scope] = saved
    }

    private func mergeSavedProfile(
        _ saved: UserProfileDTO, into target: inout UserProfileDTO,
        stage: ProfileSaveStage, scope: ProfileEditingScope, targetGuildID: GuildID?
    ) {
        if stage == .widgets { target.widgets = saved.widgets; return }
        if scope == .main || stage == .serverTag {
            if stage == .metadata {
                target.userProfile = saved.userProfile
                target.user.banner = saved.user.banner
                target.user.bio = saved.user.bio
                target.user.accentColor = saved.user.accentColor
            } else { target.user = saved.user }
        } else if scope.guildID == targetGuildID {
            if stage == .metadata {
                target.guildMemberProfile = saved.guildMemberProfile
                target.guildMember?.banner = saved.guildMember?.banner
                target.guildMember?.bio = saved.guildMember?.bio
            } else { target.guildMember = saved.guildMember }
        }
    }

    func invalidateGatewayProfile(for userID: UserID) {
        // These dispatches invalidate the full profile in the official client,
        // even when the user fields themselves did not change.
        invalidateSavedProfilePresentation(for: userID)
        continuation?.yield(.profileInvalidated(userID: userID))
    }

    func invalidateSavedProfilePresentation(for userID: UserID? = nil) {
        if let userID { profilePresentationRevisions[userID, default: 0] &+= 1 } else {
            profilePresentationGeneration &+= 1
            profilePresentationRevisions = [:]
        }
        let keys = profileTasks.keys.filter { userID == nil || $0.userID == userID }
        for key in keys { profileTasks.removeValue(forKey: key)?.cancel() }
        cachedProfiles = cachedProfiles.filter { userID != nil && $0.key.userID != userID }
        profileResponses = profileResponses.filter { userID != nil && $0.key.userID != userID }
    }
}
