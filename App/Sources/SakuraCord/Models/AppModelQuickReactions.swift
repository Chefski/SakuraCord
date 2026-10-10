import Foundation
import SakuraCordModels

extension AppModel {
    /// The hover toolbar's quick reactions, or none where Discord's hover bar
    /// would disable reaction creation for this message.
    func quickReactions(for message: Message) -> [QuickReaction] {
        guard let channel = quickReactionChannel(for: message) else { return [] }
        let permissions = channel.guildID == nil ? nil : effectiveMessagePermissions(in: channel)
        let rankedKeys = discordFrequentlyUsedReactionKeys
        let customKeys = Set(rankedKeys)
        let customEmojis = orderedCustomEmojis.filter { customKeys.contains($0.id) && canResolveFrequentlyUsedEmoji($0) }
        return QuickReactionPolicy.reactions(
            rankedKeys: rankedKeys,
            customEmojisByID: Dictionary(customEmojis.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            existingReactions: message.reactions,
            context: QuickReactionPolicy.Context(
                guildID: channel.guildID,
                hasNitro: DiscordEmojiPermissionPolicy.hasNitro(premiumType: snapshot?.currentUser.premiumType ?? 0),
                canUseExternalEmojis: (permissions ?? 0) & DiscordPermissionBits.useExternalEmojis != 0,
                roleIDsByGuild: currentUserRoleIDsByGuild,
                skinTone: NativeEmojiSkinTone(
                    rawValue: PRBuildProfile.defaults.string(forKey: "emojiSkinTone") ?? ""
                ) ?? .standard
            )
        )
    }

    /// Discord's `disableReactionCreates`: private channels other than the
    /// system DM, or guild channels where the member can chat and has
    /// ADD_REACTIONS, and threads that are active or can be unarchived.
    private func quickReactionChannel(for message: Message) -> Channel? {
        guard message.outboxState == .confirmed, !message.flags.contains(.ephemeral),
              let context = messagePermissionContext(for: message.channelID)
        else { return nil }
        let channel = context.channel
        guard let guildID = channel.guildID else {
            return channel.isOfficialSystemDirectMessage ? nil : channel
        }
        guard !requiresOnboarding(in: guildID), onboardingMember(in: guildID)?.isPending != true,
              let permissions = effectiveMessagePermissions(in: channel),
              permissions & DiscordPermissionBits.viewChannel != 0,
              permissions & DiscordPermissionBits.addReactions != 0
        else { return nil }
        if context.isThread, let thread = openThread, thread.id == message.channelID,
           thread.isArchived, thread.isLocked, permissions & DiscordPermissionBits.manageThreads == 0
        {
            return nil
        }
        return channel
    }
}
