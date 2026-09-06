import Foundation

public struct ProfileIdentityFields: Hashable, Sendable {
    /// Global display name in the main scope; nickname in a server scope.
    public var name: ProfileStoredValue<String>
    public var avatarHash: ProfileStoredValue<String>
    public var decorationSKUID: ProfileStoredValue<String>
    public var nameplateSKUID: ProfileStoredValue<String>
    public var displayNameStyle: ProfileStoredValue<DisplayNameStyle>

    public init(
        name: ProfileStoredValue<String> = .missing,
        avatarHash: ProfileStoredValue<String> = .missing,
        decorationSKUID: ProfileStoredValue<String> = .missing,
        nameplateSKUID: ProfileStoredValue<String> = .missing,
        displayNameStyle: ProfileStoredValue<DisplayNameStyle> = .missing
    ) {
        self.name = name
        self.avatarHash = avatarHash
        self.decorationSKUID = decorationSKUID
        self.nameplateSKUID = nameplateSKUID
        self.displayNameStyle = displayNameStyle
    }
}

public struct ProfileMetadataFields: Hashable, Sendable {
    public var bio: ProfileStoredValue<String>
    public var pronouns: ProfileStoredValue<String>
    public var bannerHash: ProfileStoredValue<String>
    public var accentColor: ProfileStoredValue<UInt32>
    public var themeColors: ProfileStoredValue<ProfileThemeColors>
    public var collectibles: ProfileStoredValue<[ProfileCollectibleReference]>

    public init(
        bio: ProfileStoredValue<String> = .missing,
        pronouns: ProfileStoredValue<String> = .missing,
        bannerHash: ProfileStoredValue<String> = .missing,
        accentColor: ProfileStoredValue<UInt32> = .missing,
        themeColors: ProfileStoredValue<ProfileThemeColors> = .missing,
        collectibles: ProfileStoredValue<[ProfileCollectibleReference]> = .missing
    ) {
        self.bio = bio
        self.pronouns = pronouns
        self.bannerHash = bannerHash
        self.accentColor = accentColor
        self.themeColors = themeColors
        self.collectibles = collectibles
    }
}

public struct ProfileIdentityChanges: Hashable, Sendable {
    public var name: ProfileChange<String> = .unchanged
    public var avatar: ProfileChange<ProfileAvatarSelection> = .unchanged
    public var decorationSKUID: ProfileChange<String> = .unchanged
    public var nameplateSKUID: ProfileChange<String> = .unchanged
    public var displayNameStyle: ProfileChange<DisplayNameStyle> = .unchanged

    public init() {}

    public var hasChanges: Bool {
        name.isChanged || avatar.isChanged || decorationSKUID.isChanged
            || nameplateSKUID.isChanged || displayNameStyle.isChanged
    }
}

public struct ProfileMetadataChanges: Hashable, Sendable {
    public var bio: ProfileChange<String> = .unchanged
    public var pronouns: ProfileChange<String> = .unchanged
    public var banner: ProfileChange<ProfileImageUpload> = .unchanged
    public var accentColor: ProfileChange<UInt32> = .unchanged
    public var themeColors: ProfileChange<ProfileThemeColors> = .unchanged
    public var collectibleSKUIDs: ProfileChange<[String]> = .unchanged

    public init() {}

    public var hasChanges: Bool {
        bio.isChanged || pronouns.isChanged || banner.isChanged || accentColor.isChanged
            || themeColors.isChanged || collectibleSKUIDs.isChanged
    }
}
