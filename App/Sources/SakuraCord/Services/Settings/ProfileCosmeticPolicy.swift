import SakuraCordModels

nonisolated enum ProfileCosmetic: Sendable {
    case effect, nameplate, avatarDecoration, frame, nameStyle, gradient
}

/// Local presentation preferences never alter the underlying Discord profile.
nonisolated struct ProfileCosmeticPolicy: Equatable, Sendable {
    var settings: AccessibilitySettingsSnapshot = .defaults
    var currentUserID: UserID?

    func disables(_ cosmetic: ProfileCosmetic, for userID: UserID) -> Bool {
        guard userID != currentUserID || settings.disablesOwnCosmetics else { return false }
        return switch cosmetic {
        case .effect: settings.disablesProfileEffects
        case .nameplate: settings.disablesNameplates
        case .avatarDecoration: settings.disablesAvatarDecorations
        case .frame: settings.disablesProfileFrames
        case .nameStyle: settings.disablesNameStyles
        case .gradient: settings.disablesProfileGradients
        }
    }

    func user(_ source: User) -> User {
        var user = source
        if disables(.avatarDecoration, for: user.id) { user.avatarDecorationURL = nil }
        if disables(.nameplate, for: user.id) { user.nameplate = nil }
        if disables(.nameStyle, for: user.id) { user.displayNameStyle = nil }
        return user
    }

    func member(_ source: Member) -> Member {
        var member = source
        member.user = user(source.user)
        return member
    }
}
