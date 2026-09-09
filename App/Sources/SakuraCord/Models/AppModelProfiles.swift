import DiscordProtocol
import Foundation
import SakuraCordModels

extension AppModel {
    func consumeProfileWidgetConnectionsChanged(userID: UserID, connections: [String: ProfileWidgetConnection]) {
        guard userID == snapshot?.currentUser.id else { return }
        for key in profileCache.keys where key.userID == userID { profileCache[key]?.widgetResources?.connections = connections }
        for destination in [ProfilePresentationDestination.inspector, .contextual] {
            guard var presentation = profilePresentation(for: destination), presentation.member.id == userID else { continue }
            presentation.profile?.widgetResources?.connections = connections
            setProfilePresentation(presentation, for: destination)
        }
        profileWidgetConnectionsRevision = UUID()
    }

    func consumeProfileCustomStatusChanged(userID: UserID, status: ProfileCustomStatus?) {
        profileCustomStatus = status
        let text = status?.displayText
        for key in profileCache.keys where key.userID == userID { profileCache[key]?.customStatus = text }
        for guildID in membersByGuildID.keys { membersByGuildID[guildID]?[userID]?.customStatus = text }
        for index in members.indices where members[index].id == userID { members[index].customStatus = text }
        for destination in [ProfilePresentationDestination.inspector, .contextual] {
            guard var presentation = profilePresentation(for: destination), presentation.member.id == userID else { continue }
            presentation.member.customStatus = text
            presentation.profile?.customStatus = text
            setProfilePresentation(presentation, for: destination)
        }
    }

    func consumeProfileChanged(userID: UserID, scope: ProfileEditingScope, value: UserProfile?) {
        let key = ProfileCacheKey(userID: userID, guildID: scope.guildID)
        profileCache[key] = value
        guard selectedGuildID == scope.guildID else { return }
        for destination in [ProfilePresentationDestination.inspector, .contextual] {
            guard var presentation = profilePresentation(for: destination), presentation.member.id == userID else { continue }
            switch destination {
            case .inspector: inspectorProfileTask?.cancel()
            case .contextual: contextualProfileTask?.cancel()
            }
            if let value {
                presentation.member.user = value.user
                presentation.profile = profile(value, applyingPresenceFrom: presentation.member)
                presentation.errorMessage = nil
            } else {
                presentation.profile = nil
                presentation.errorMessage = "This profile changed. Reopen it to load the saved result."
            }
            presentation.isLoading = false
            setProfilePresentation(presentation, for: destination)
        }
    }

    func updateStatus(_ status: PresenceStatus) async {
        let session = accountSession()
        do {
            try await session.provider.updateStatus(status)
            guard isCurrentAccountSession(session) else { return }
            currentStatus = status
            members = members.map { member in
                guard member.user.id == snapshot?.currentUser.id else { return member }
                var updatedMember = member
                updatedMember.status = status
                return updatedMember
            }
        } catch {
            guard isCurrentAccountSession(session) else { return }
            DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
            errorMessage = error.localizedDescription
        }
    }

    func selectMember(_ member: Member) {
        if selectedMember?.id == member.id, isInspectorProfilePresented {
            dismissInspectorProfile()
            return
        }
        isInspectorProfilePresented = true
        if selectedMember?.id == member.id {
            return
        }
        presentProfile(for: member, destination: .inspector)
    }

    @discardableResult
    func showProfile(for user: User) -> UUID {
        let member =
            membersByID[user.id]
                ?? Member(user: user, roleName: "Member", status: .offline)
        return presentProfile(for: member, destination: .contextual)
    }

    func showSystemMessageProfile(
        userID: UserID,
        sourceMessage: Message? = nil
    ) {
        if let user = systemMessageUser(
            userID: userID,
            sourceMessage: sourceMessage
        ) {
            _ = showProfile(for: user)
        }
    }

    func navigateToSystemMessageTarget(
        guildID: GuildID?,
        channelID: ChannelID,
        messageID: MessageID
    ) {
        let isRootChannel = snapshot?.channels.contains { $0.id == channelID } == true
            || visibleChannels.contains { $0.id == channelID }
        if isRootChannel {
            navigate(to: guildID, channelID: channelID, messageID: messageID)
        } else {
            navigate(
                to: guildID,
                linkedChannelID: channelID,
                messageID: messageID
            )
        }
    }

    func showInspectorProfile(for user: User) {
        isInspectorProfilePresented = true
        let member =
            membersByID[user.id]
                ?? Member(
                    user: user,
                    roleName: "Direct Message",
                    status: .offline
                )
        presentProfile(for: member, destination: .inspector)
    }

    func authorPresentation(for message: Message) -> MessageAuthorPresentation {
        MessageAuthorPresentation.resolve(
            message: message,
            member: membersByID[message.author.id],
            roles: guildRoles
        )
    }

    func authorPresentation(
        for replyPreview: MessageReplyPreview
    ) -> MessageAuthorPresentation {
        MessageAuthorPresentation.resolve(
            replyPreview: replyPreview,
            member: membersByID[replyPreview.author.id],
            roles: guildRoles
        )
    }

    @discardableResult
    func presentProfile(
        for member: Member,
        destination: ProfilePresentationDestination
    ) -> UUID {
        let requestID = UUID()
        let guildID = selectedGuildID
        let cacheKey = ProfileCacheKey(
            userID: member.id,
            guildID: guildID
        )
        let cachedProfile = profileCache[cacheKey].map {
            profile($0, applyingPresenceFrom: member)
        }
        let presentation = ProfilePresentationState(
            requestID: requestID,
            member: member,
            profile: cachedProfile,
            isLoading: cachedProfile == nil,
            errorMessage: nil
        )
        switch destination {
        case .inspector:
            inspectorProfileTask?.cancel()
            inspectorProfilePresentation = presentation
        case .contextual:
            contextualProfileTask?.cancel()
            contextualProfilePresentation = presentation
        }
        guard cachedProfile == nil else { return requestID }
        let session = accountSession()

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await session.provider.profile(
                    for: member.id,
                    in: guildID
                )
                guard !Task.isCancelled,
                      isCurrentAccountSession(session),
                      selectedGuildID == guildID,
                      profilePresentation(
                          for: destination
                      )?.requestID == requestID
                else {
                    return
                }
                profileCache[cacheKey] = loaded
                var value = profilePresentation(for: destination)
                value?.member = member
                value?.profile = profile(
                    loaded,
                    applyingPresenceFrom: member
                )
                value?.isLoading = false
                value?.errorMessage = nil
                setProfilePresentation(value, for: destination)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      isCurrentAccountSession(session),
                      profilePresentation(
                          for: destination
                      )?.requestID == requestID
                else { return }
                var value = profilePresentation(for: destination)
                value?.isLoading = false
                DiscordAPIDiagnosticStore.shared.recordClientFailure(error)
                value?.errorMessage = error.localizedDescription
                setProfilePresentation(value, for: destination)
            }
        }
        switch destination {
        case .inspector:
            inspectorProfileTask = task
        case .contextual:
            contextualProfileTask = task
        }
        return requestID
    }

    func dismissInspectorProfile() {
        inspectorProfileTask?.cancel()
        inspectorProfileTask = nil
        inspectorProfilePresentation = nil
        isInspectorProfilePresented = false
    }

    func dismissContextualProfile(for userID: UserID? = nil) {
        if let userID,
           contextualProfilePresentation?.member.id != userID
        {
            return
        }
        contextualProfileTask?.cancel()
        contextualProfileTask = nil
        contextualProfilePresentation = nil
    }

    func dismissContextualProfile(requestID: UUID) {
        guard contextualProfilePresentation?.requestID == requestID else {
            return
        }
        dismissContextualProfile()
    }

    func dismissAllProfiles(clearsCache: Bool = false) {
        dismissInspectorProfile()
        dismissContextualProfile()
        if clearsCache {
            currentUserProfilePrefetch?.task.cancel()
            currentUserProfilePrefetch = nil
            profileCache.removeAll(keepingCapacity: false)
        }
    }

    func profilePresentation(
        for destination: ProfilePresentationDestination
    ) -> ProfilePresentationState? {
        switch destination {
        case .inspector:
            inspectorProfilePresentation
        case .contextual:
            contextualProfilePresentation
        }
    }

    func setProfilePresentation(
        _ value: ProfilePresentationState?,
        for destination: ProfilePresentationDestination
    ) {
        switch destination {
        case .inspector:
            inspectorProfilePresentation = value
        case .contextual:
            contextualProfilePresentation = value
        }
    }

    func profile(
        _ value: UserProfile,
        applyingPresenceFrom member: Member
    ) -> UserProfile {
        var result = value
        result.status = member.status
        result.customStatus = member.customStatus
        return result
    }

    func beginCurrentUserProfilePrefetch(
        in guildID: GuildID?,
        account session: AppModelAccountSession?
    ) {
        guard let session, let user = snapshot?.currentUser else { return }
        let cacheKey = ProfileCacheKey(userID: user.id, guildID: guildID)
        guard profileCache[cacheKey] == nil,
              currentUserProfilePrefetch?.key != cacheKey
        else { return }

        currentUserProfilePrefetch?.task.cancel()
        let task = startAccountChildTask(account: session) { model, session in
            defer {
                if model.currentUserProfilePrefetch?.key == cacheKey {
                    model.currentUserProfilePrefetch = nil
                }
            }
            do {
                let profile = try await session.provider.profile(
                    for: user.id,
                    in: guildID
                )
                guard !Task.isCancelled,
                      model.isCurrentAccountSession(session)
                else { return }
                model.profileCache[cacheKey] = profile
            } catch {
                // Prefetching is speculative. The normal profile presentation
                // path remains responsible for surfacing load failures.
            }
        }
        currentUserProfilePrefetch = CurrentUserProfilePrefetch(
            key: cacheKey,
            task: task
        )
    }
}
