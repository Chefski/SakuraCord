import Foundation

/// A value as returned by Discord, before resolving a server's inherited profile.
/// Absence and explicit null must survive loading an editor without becoming edits.
public enum ProfileStoredValue<Value: Hashable & Sendable>: Hashable, Sendable {
    case missing
    case null
    case value(Value)

    public var value: Value? {
        guard case let .value(value) = self else { return nil }
        return value
    }
}

/// An explicit editing intent. Reading a resolved preview never creates a change.
public enum ProfileChange<Value: Hashable & Sendable>: Hashable, Sendable {
    case unchanged
    case clear
    case set(Value)

    public var isChanged: Bool {
        if case .unchanged = self { return false }
        return true
    }

    public func applying(to original: ProfileStoredValue<Value>) -> ProfileStoredValue<Value> {
        switch self {
        case .unchanged: original
        case .clear: .null
        case let .set(value): .value(value)
        }
    }
}

public enum ProfileEditingScope: Hashable, Sendable {
    case main
    case server(GuildID)

    public var guildID: GuildID? {
        guard case let .server(id) = self else { return nil }
        return id
    }
}

/// Keep the two sRGB integers in their original order, including unset endpoints.
public struct ProfileThemeColors: Hashable, Sendable {
    public var primary: UInt32?
    public var accent: UInt32?

    public init(primary: UInt32?, accent: UInt32?) {
        self.primary = primary
        self.accent = accent
    }
}

public struct ProfileAvatarHistoryEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var storageHash: String
    public var description: String
    public var imageURL: URL
    public var cropImageURL: URL

    public init(id: String, storageHash: String, description: String, imageURL: URL, cropImageURL: URL? = nil) {
        self.id = id
        self.storageHash = storageHash
        self.description = description
        self.imageURL = imageURL
        self.cropImageURL = cropImageURL ?? imageURL
    }
}

/// Processed media is retained in the draft until its particular save succeeds.
public struct ProfileImageUpload: Hashable, Sendable {
    public var data: Data
    public var mediaType: String
    public var description: String
    public var originalMD5: String?
    public var isAnimated: Bool

    public init(data: Data, mediaType: String, description: String, originalMD5: String? = nil, isAnimated: Bool = false) {
        self.data = data
        self.mediaType = mediaType
        self.description = description
        self.originalMD5 = originalMD5
        self.isAnimated = isAnimated
    }
}

public enum ProfileAvatarSelection: Hashable, Sendable {
    /// An unchanged archive crop saves its existing ID; a changed crop becomes an upload.
    case history(ProfileAvatarHistoryEntry)
    case upload(ProfileImageUpload)
}

public struct ProfileCollectibleReference: Hashable, Sendable {
    public var skuID: String
    public var type: Int
    public var expiresAt: Date?

    public init(skuID: String, type: Int, expiresAt: Date? = nil) {
        self.skuID = skuID
        self.type = type
        self.expiresAt = expiresAt
    }
}

public struct ProfileWidgetEligibility: Hashable, Sendable {
    public var hasFullNitro: Bool
    public var hasPersonalWidgetAccess: Bool
    public var showsPersonalWidgetCreateEntrypoint: Bool
    public var showsDeveloperWidgets = false

    public init(
        hasFullNitro: Bool,
        hasPersonalWidgetAccess: Bool,
        showsPersonalWidgetCreateEntrypoint: Bool = false
    ) {
        self.hasFullNitro = hasFullNitro
        self.hasPersonalWidgetAccess = hasPersonalWidgetAccess
        self.showsPersonalWidgetCreateEntrypoint = showsPersonalWidgetCreateEntrypoint
    }

    public var canEditPersonalWidget: Bool {
        hasFullNitro && hasPersonalWidgetAccess
    }
}
