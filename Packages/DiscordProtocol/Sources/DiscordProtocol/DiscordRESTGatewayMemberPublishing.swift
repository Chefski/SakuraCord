import SakuraCordModels

extension DiscordRESTProvider {
    func publishMemberChange(_ member: Member, guildID: GuildID) {
        let previous = cachedMembers[guildID]?.first { $0.id == member.id }
        cachedMembers[guildID] = DiscordMemberStoreOrdering.merging(
            existing: cachedMembers[guildID] ?? [], updates: [member]
        )
        let members = cachedMembers[guildID] ?? []
        if previous != members.first(where: { $0.id == member.id }) {
            continuation?.yield(
                .membersChanged(
                    guildID: guildID,
                    members: members,
                    groups: selectedMemberListGroups(guildID: guildID)
                )
            )
        }
        if member.id == currentUser?.id,
           previous?.roleIDs != member.roleIDs || previous?.isPending != member.isPending {
            continuation?.yield(
                .currentUserRolesChanged(guildID: guildID, roleIDs: member.roleIDs)
            )
            if var guild = cachedGuilds[guildID] {
                guild.currentUserPermissions = nil
                cachedGuilds[guildID] = guild
                continuation?.yield(.guildChanged(guild))
            }
        }
    }

    func removeMember(userID: UserID, guildID: GuildID) {
        cachedMembers[guildID]?.removeAll { $0.id == userID }
        let memberListIDs = cachedMemberListItems[guildID].map { Array($0.keys) } ?? []
        for memberListID in memberListIDs {
            cachedMemberListItems[guildID]?[memberListID]?.removeAll {
                $0?.member?.user.id == userID.description
            }
        }
        let members = cachedMembers[guildID] ?? []
        continuation?.yield(
            .membersChanged(
                guildID: guildID,
                members: members,
                groups: selectedMemberListGroups(guildID: guildID)
            )
        )
        if userID == currentUser?.id {
            continuation?.yield(.currentUserRolesChanged(guildID: guildID, roleIDs: []))
            clearCurrentUserPermissionSnapshot(guildID)
        }
    }
}
