import DiscordProtocol
import Foundation
import Observation
import SakuraCordModels
import SakuraCordPersistence

@Observable
final class GuildOnboardingStore {
    struct Entry {
        var configuration: GuildOnboarding?
        var responses: Set<String> = []
        var promptID: String?
        var initial = false
        var isLoading = false
        var isSaving = false
        var needsRefresh = false
        var error: String?
        var notice: String?
        var revision = UUID()
    }

    var entries: [GuildID: Entry] = [:]
    var members: [GuildID: Member] = [:]
    var presentedGuildID: GuildID?
    var channelManagementEnabled = false
    var changingChannels: Set<ChannelID> = []
    var changingChannelMode = false
    @ObservationIgnored var generation = 0
    @ObservationIgnored var draftWrite: Task<Void, Never>?

    func reset() {
        generation += 1
        entries = [:]
        members = [:]
        presentedGuildID = nil
        channelManagementEnabled = false
        changingChannels = []
        changingChannelMode = false
    }

    func persist(_ draft: GuildOnboardingDraft?, guildID: GuildID, database: SakuraCordDatabase?) {
        let previous = draftWrite
        let generation = generation
        draftWrite = Task {
            await previous?.value
            do { try await database?.saveOnboardingDraft(draft, guildID: guildID) } catch {
                if self.generation == generation {
                    self.entries[guildID]?.notice = "Your draft could not be saved on this Mac. Keep this window open until you finish."
                }
            }
        }
    }
}

extension AppModel {
    nonisolated static func resolveConversationAccess(
        for channel: Channel,
        permissionBasis: ConversationPermissionBasis?
    ) -> ConversationAccess {
        guard channel.guildID != nil else {
            return .readable(canSend: !channel.isOfficialSystemDirectMessage)
        }
        guard let permissionBasis, permissionBasis.currentUserOnboardingIsKnown else { return .checking }
        let permissions = ConversationPermissionResolver.effectivePermissions(
            guild: permissionBasis.guild,
            channel: channel,
            resolvedBasePermissions: permissionBasis.resolvedBasePermissions,
            overwritePrincipals: permissionBasis.overwritePrincipals,
            hasCurrentRoleIdentity: permissionBasis.hasCurrentRoleIdentity
        )
        if permissionBasis.currentUserIsPending || permissionBasis.currentUserRequiresOnboarding {
            let access = ConversationPermissionResolver.channelAccess(effectivePermissions: permissions)
            return access.isReadable ? .readable(canSend: false) : access
        }
        if channel.kind == .voice {
            return ConversationPermissionResolver.voiceChannelAccess(
                effectivePermissions: permissions
            )
        }
        return ConversationPermissionResolver.channelAccess(effectivePermissions: permissions)
    }

    func onboardingMember(in guildID: GuildID) -> Member? {
        onboarding.members[guildID] ?? currentUser.flatMap { membersByGuildID[guildID]?[$0.id] }
    }

    func requiresOnboarding(in guildID: GuildID) -> Bool {
        serverRailGuildsByID[guildID]?.features.contains("GUILD_ONBOARDING") == true
            && onboardingMember(in: guildID)?.requiresOnboarding == true
    }

    func openChannelsAndRoles(in guildID: GuildID) {
        onboarding.presentedGuildID = guildID
        refreshOnboarding(in: guildID)
    }

    func refreshSelectedGuildOnboarding() {
        guard let guildID = selectedGuildID,
              serverRailGuildsByID[guildID]?.features.contains("GUILD_ONBOARDING") == true else { return }
        refreshOnboarding(in: guildID)
    }

    func refreshOnboarding(in guildID: GuildID) {
        guard !accountTransitionIsActive, let guild = serverRailGuildsByID[guildID], !guild.isUnavailable,
              onboarding.entries[guildID]?.isLoading != true,
              onboarding.entries[guildID]?.isSaving != true else { return }
        let store = onboarding
        var entry = store.entries[guildID] ?? .init()
        entry.revision = UUID()
        entry.isLoading = true
        entry.error = nil
        let revision = entry.revision
        store.entries[guildID] = entry
        if let userID = currentUser?.id {
            store.channelManagementEnabled = UserDefaults.standard.bool(forKey: channelManagementKey(userID))
        }
        startAccountChildTask(account: accountSession()) { model, account in
            do {
                async let configuration = account.provider.guildOnboarding(in: guildID)
                async let member = account.provider.refreshCurrentMember(in: guildID)
                let (value, confirmedMember) = try await (configuration, member)
                await store.draftWrite?.value
                let saved = try await account.database?.onboardingDraft(guildID: guildID)
                guard model.isCurrentAccountSession(account), !Task.isCancelled,
                      store.entries[guildID]?.revision == revision else { return }
                let initial = confirmedMember.requiresOnboarding && guild.features.contains("GUILD_ONBOARDING")
                var next = GuildOnboardingStore.Entry()
                next.configuration = value
                next.initial = initial
                next.responses = value.validResponses(Set(value.responses), initial: initial)
                if let saved, saved.initial == initial, saved.joinedAt == confirmedMember.joinedAt,
                   saved.baselineResponses == Set(value.responses) {
                    next.responses = value.validResponses(saved.responses, initial: initial)
                    next.promptID = saved.promptID
                    if next.responses != saved.responses { next.notice = "Some options were removed. Review your answers before continuing." }
                } else if saved != nil {
                    next.notice = "Your membership or answers changed in Discord. The latest answers are shown."
                    store.persist(nil, guildID: guildID, database: account.database)
                }
                let questions = value.questions(initial: initial)
                if !questions.contains(where: { $0.id == next.promptID }) { next.promptID = questions.first?.id }
                store.members[guildID] = confirmedMember
                store.entries[guildID] = next
            } catch {
                guard model.isCurrentAccountSession(account), store.entries[guildID]?.revision == revision else { return }
                store.entries[guildID]?.isLoading = false
                store.entries[guildID]?.needsRefresh = true
                store.entries[guildID]?.error = error.localizedDescription
            }
        }
    }

    func receiveOnboardingMember(_ member: Member, guildID: GuildID) {
        guard member.id == currentUser?.id else { return }
        let old = onboarding.members[guildID]
        onboarding.members[guildID] = member
        if let old, old.requiresOnboarding != member.requiresOnboarding,
           onboarding.entries[guildID]?.isSaving != true,
           onboarding.entries[guildID]?.isLoading != true,
           onboarding.presentedGuildID == guildID {
            refreshOnboarding(in: guildID)
        }
    }

    func selectOnboardingOption(_ option: GuildOnboardingOption, prompt: GuildOnboardingPrompt, guildID: GuildID) {
        guard var entry = onboarding.entries[guildID], !entry.isLoading, !entry.isSaving, !entry.needsRefresh else { return }
        if entry.responses.contains(option.id) {
            entry.responses.remove(option.id)
        } else {
            if prompt.singleSelect { entry.responses.subtract(prompt.options.map(\.id)) }
            entry.responses.insert(option.id)
        }
        entry.error = nil
        entry.revision = UUID()
        onboarding.entries[guildID] = entry
        persistOnboardingDraft(in: guildID)
    }

    func setOnboardingPrompt(_ promptID: String, guildID: GuildID) {
        onboarding.entries[guildID]?.revision = UUID()
        onboarding.entries[guildID]?.promptID = promptID
        persistOnboardingDraft(in: guildID)
    }

    private func persistOnboardingDraft(in guildID: GuildID) {
        guard let entry = onboarding.entries[guildID], let value = entry.configuration else { return }
        onboarding.persist(GuildOnboardingDraft(
            responses: entry.responses, baselineResponses: Set(value.responses), promptID: entry.promptID,
            joinedAt: onboardingMember(in: guildID)?.joinedAt, initial: entry.initial
        ), guildID: guildID, database: accountSession().database)
    }

    func saveOnboarding(in guildID: GuildID) {
        let store = onboarding
        guard let entry = store.entries[guildID], let configuration = entry.configuration,
              !entry.isLoading, !entry.isSaving, !entry.needsRefresh else { return }
        if let error = configuration.validationError(entry.responses, initial: entry.initial) {
            store.entries[guildID]?.error = error
            return
        }
        store.entries[guildID]?.isSaving = true
        store.entries[guildID]?.error = nil
        startAccountChildTask(account: accountSession()) { model, account in
            do {
                let saved = try await account.provider.saveGuildOnboarding(in: guildID, responses: entry.responses, initial: entry.initial)
                guard model.isCurrentAccountSession(account), !Task.isCancelled else { return }
                store.entries[guildID]?.configuration = saved
                store.entries[guildID]?.responses = Set(saved.responses)
                store.entries[guildID]?.isSaving = false
                store.entries[guildID]?.initial = false
                store.entries[guildID]?.notice = "Answers saved."
                store.persist(nil, guildID: guildID, database: account.database)
                if entry.initial { store.presentedGuildID = nil }
            } catch {
                guard model.isCurrentAccountSession(account) else { return }
                store.entries[guildID]?.isSaving = false
                store.entries[guildID]?.needsRefresh = true
                if case ChatProviderError.invalidRequest = error {
                    store.entries[guildID]?.error = error.localizedDescription
                } else {
                    store.entries[guildID]?.error = "\(error.localizedDescription) Refresh to check what Discord saved before trying again."
                }
            }
        }
    }

    private func channelManagementKey(_ userID: UserID) -> String { "dev.sakuracord.channel-management.\(userID)" }

    func setChannelManagementEnabled(_ enabled: Bool) {
        guard let userID = currentUser?.id else { return }
        onboarding.channelManagementEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: channelManagementKey(userID))
        reconcileSelectedOnboardingChannel()
    }

    func setChannelSelectionEnabled(_ enabled: Bool, guildID: GuildID) {
        guard onboarding.channelManagementEnabled, !onboarding.changingChannelMode else { return }
        onboarding.changingChannelMode = true
        startAccountChildTask(account: accountSession()) { model, account in
            do {
                try await account.provider.setGuildChannelSelectionEnabled(enabled, guildID: guildID)
            } catch {
                if model.isCurrentAccountSession(account) { model.onboarding.entries[guildID]?.error = error.localizedDescription }
            }
            guard model.isCurrentAccountSession(account) else { return }
            model.onboarding.changingChannelMode = false
        }
    }

    func setChannelSelected(_ selected: Bool, channelID: ChannelID, guildID: GuildID) {
        guard onboarding.channelManagementEnabled, onboarding.changingChannels.insert(channelID).inserted else { return }
        startAccountChildTask(account: accountSession()) { model, account in
            do {
                try await account.provider.setGuildChannelSelected(selected, channelID: channelID, guildID: guildID)
            } catch {
                if model.isCurrentAccountSession(account) { model.onboarding.entries[guildID]?.error = error.localizedDescription }
            }
            guard model.isCurrentAccountSession(account) else { return }
            model.onboarding.changingChannels.remove(channelID)
        }
    }

    func allowOnboardingSubmission(in channelID: ChannelID) -> Bool {
        let parentID = snapshot?.threads.first { $0.id == channelID }?.parentID
            ?? snapshot?.activeJoinedThreads.first { $0.id == channelID }?.parentID
            ?? (openThread?.id == channelID ? openThread?.parentID : nil)
            ?? channelID
        let channel = snapshot?.channels.first { $0.id == parentID }
            ?? visibleChannels.first { $0.id == parentID }
        guard let guildID = channel?.guildID else { return true }
        if requiresOnboarding(in: guildID) || (serverRailGuildsByID[guildID]?.features.contains("GUILD_ONBOARDING") == true && onboardingMember(in: guildID)?.flags == nil) {
            openChannelsAndRoles(in: guildID)
            return false
        }
        return onboardingMember(in: guildID)?.isPending != true
    }

    func reconcileSelectedOnboardingChannel() {
        guard onboarding.channelManagementEnabled, let guildID = selectedGuildID,
              let channelID = selectedChannelID else { return }
        let groups = ChannelGroup.make(from: visibleChannels)
        let channels = selectedChannelGroups(groups, guildID: guildID).flatMap(\.channels)
        guard !channels.contains(where: { $0.id == channelID }) else { return }
        if let next = channels.first(where: { conversationAccess(for: $0).isReadable }) { navigate(to: next.id) } else { selectedChannelID = nil }
    }

    func selectedChannelGroups(_ groups: [ChannelGroup], guildID: GuildID?) -> [ChannelGroup] {
        guard onboarding.channelManagementEnabled, let guildID else { return groups }
        let settings = readState.notificationSettings(guildID: guildID) ?? GuildNotificationSettings(guildID: guildID)
        guard settings.flags & GuildChannelSelection.enabledFlag != 0 else { return groups }
        return groups.compactMap { group in
            var group = group
            group.channels.removeAll {
                !GuildChannelSelection.isSelected($0.id, settings: settings)
                    && !(group.categoryID.map { GuildChannelSelection.isSelected($0, settings: settings) } ?? false)
                    && $0.id != activeVoiceChannel?.id
            }
            return group.channels.isEmpty ? nil : group
        }
    }
}
