import Foundation

public struct ProfileEditChanges: Hashable, Sendable {
    public var identity: ProfileIdentityChanges
    public var metadata: ProfileMetadataChanges
    public var serverTag: ProfileChange<GuildID>
    public var widgets: [ProfileWidget]?

    public init(
        identity: ProfileIdentityChanges = ProfileIdentityChanges(),
        metadata: ProfileMetadataChanges = ProfileMetadataChanges(),
        serverTag: ProfileChange<GuildID> = .unchanged,
        widgets: [ProfileWidget]? = nil
    ) {
        self.identity = identity
        self.metadata = metadata
        self.serverTag = serverTag
        self.widgets = widgets
    }

    public var hasChanges: Bool {
        identity.hasChanges || metadata.hasChanges || serverTag.isChanged || widgets != nil
    }

    /// A successful stage is acknowledged before the next request can fail.
    public mutating func acknowledge(_ stage: ProfileSaveStage) {
        switch stage {
        case .identity: identity = ProfileIdentityChanges()
        case .metadata: metadata = ProfileMetadataChanges()
        case .serverTag: serverTag = .unchanged
        case .widgets: widgets = nil
        }
    }
}

public enum ProfileSaveStage: Hashable, Sendable {
    case identity
    case metadata
    case serverTag
    case widgets
}

public struct ProfileSaveConfirmation: Hashable, Sendable {
    public var stage: ProfileSaveStage
    /// Nil means the HTTP save succeeded but its response could not be reconciled.
    /// Acknowledge the stage and reload before accepting further edits.
    public var snapshot: ProfileEditingSnapshot?

    public init(stage: ProfileSaveStage, snapshot: ProfileEditingSnapshot?) {
        self.stage = stage
        self.snapshot = snapshot
    }
}
