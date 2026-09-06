import Foundation

public struct ProfileServerTagFields: Hashable, Sendable {
    public var guildID: ProfileStoredValue<GuildID>
    public var isEnabled: ProfileStoredValue<Bool>

    public init(guildID: ProfileStoredValue<GuildID>, isEnabled: ProfileStoredValue<Bool>) {
        self.guildID = guildID
        self.isEnabled = isEnabled
    }
}

/// The editable source and its resolved presentation deliberately have separate owners.
/// In particular, a guild preview may use the main avatar while its raw avatar is null.
public struct ProfileEditingSnapshot: Hashable, Sendable {
    public let scope: ProfileEditingScope
    public var mainIdentity: ProfileIdentityFields
    public var mainMetadata: ProfileMetadataFields
    public var serverIdentity: ProfileIdentityFields?
    public var serverMetadata: ProfileMetadataFields?
    public var serverTag: ProfileStoredValue<ProfileServerTagFields>
    public var serverTagGuilds: [Guild]
    public var customStatus: ProfileCustomStatus?
    public var presentation: UserProfile
    public var mainPresentation: UserProfile
    public var widgetEligibility: ProfileWidgetEligibility

    public init(
        scope: ProfileEditingScope,
        mainIdentity: ProfileIdentityFields,
        mainMetadata: ProfileMetadataFields,
        serverIdentity: ProfileIdentityFields? = nil,
        serverMetadata: ProfileMetadataFields? = nil,
        serverTag: ProfileStoredValue<ProfileServerTagFields> = .missing,
        serverTagGuilds: [Guild] = [],
        customStatus: ProfileCustomStatus? = nil,
        presentation: UserProfile,
        mainPresentation: UserProfile? = nil,
        widgetEligibility: ProfileWidgetEligibility
    ) {
        self.scope = scope
        self.mainIdentity = mainIdentity
        self.mainMetadata = mainMetadata
        self.serverIdentity = serverIdentity
        self.serverMetadata = serverMetadata
        self.serverTag = serverTag
        self.serverTagGuilds = serverTagGuilds
        self.customStatus = customStatus
        self.presentation = presentation
        self.mainPresentation = mainPresentation ?? presentation
        self.widgetEligibility = widgetEligibility
    }

    public var identity: ProfileIdentityFields {
        switch scope {
        case .main: mainIdentity
        case .server: serverIdentity ?? ProfileIdentityFields()
        }
    }

    public var metadata: ProfileMetadataFields {
        switch scope {
        case .main: mainMetadata
        case .server: serverMetadata ?? ProfileMetadataFields()
        }
    }
}
