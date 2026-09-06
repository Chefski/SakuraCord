import Foundation
import SakuraCordModels

/// Ordinary profile presentation tolerates unknown cosmetics. When this is our
/// own profile, retain its stricter editable form too, without another GET.
struct ProfileResponseDTO: Decodable {
    let profile: UserProfileDTO
    let editable: ProfileEditingResponseDTO?

    init(from decoder: any Decoder) throws {
        profile = try UserProfileDTO(from: decoder)
        editable = try? ProfileEditingResponseDTO(from: decoder)
    }
}

struct ProfileEditingResponseDTO: Decodable {
    var profile: UserProfileDTO
    var identity: ProfileEditingIdentityDTO
    var metadata: ProfileEditingMetadataDTO?
    var serverIdentity: ProfileEditingIdentityDTO?
    var serverMetadata: ProfileEditingMetadataDTO?

    private enum CodingKeys: String, CodingKey {
        case user
        case metadata = "user_profile"
        case serverIdentity = "guild_member"
        case serverMetadata = "guild_member_profile"
    }

    init(from decoder: any Decoder) throws {
        profile = try UserProfileDTO(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identity = try values.decode(ProfileEditingIdentityDTO.self, forKey: .user)
        metadata = try values.decodeIfPresent(ProfileEditingMetadataDTO.self, forKey: .metadata)
        serverIdentity = try values.decodeIfPresent(ProfileEditingIdentityDTO.self, forKey: .serverIdentity)
        serverMetadata = try values.decodeIfPresent(ProfileEditingMetadataDTO.self, forKey: .serverMetadata)
    }
}

/// Editor decoding is strict: silently losing an editable field could clear it on save.
/// The ordinary profile renderer can still tolerate unknown optional cosmetics.
struct ProfileEditingIdentityDTO: Decodable {
    let fields: ProfileIdentityFields
    let serverTag: ProfileStoredValue<ProfileServerTagFields>

    private enum CodingKeys: String, CodingKey {
        case globalName = "global_name"
        case nick, avatar, collectibles
        case decoration = "avatar_decoration_data"
        case style = "display_name_styles"
        case serverTag = "primary_guild"
    }

    private struct SKU: Decodable {
        var skuID: String
        enum CodingKeys: String, CodingKey { case skuID = "sku_id" }
    }

    private struct Collectibles: Decodable {
        var nameplate: ProfileStoredValue<String>
        enum CodingKeys: String, CodingKey { case nameplate }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            nameplate = try values.profileField(SKU.self, forKey: .nameplate) { $0.skuID }
        }
    }

    private struct ServerTag: Decodable {
        var fields: ProfileServerTagFields
        enum CodingKeys: String, CodingKey {
            case guildID = "identity_guild_id"
            case enabled = "identity_enabled"
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            fields = try ProfileServerTagFields(
                guildID: values.profileField(String.self, forKey: .guildID) { value in
                    guard let id = GuildID(value) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .guildID, in: values, debugDescription: "Invalid profile server tag ID"
                        )
                    }
                    return id
                },
                isEnabled: values.profileField(Bool.self, forKey: .enabled) { $0 }
            )
        }
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let nameKey: CodingKeys = values.contains(.nick) ? .nick : .globalName
        let nameplate: ProfileStoredValue<String>
        if !values.contains(.collectibles) {
            nameplate = .missing
        } else if try values.decodeNil(forKey: .collectibles) {
            nameplate = .null
        } else {
            nameplate = try values.decode(Collectibles.self, forKey: .collectibles).nameplate
        }
        fields = try ProfileIdentityFields(
            name: values.profileField(String.self, forKey: nameKey) { $0 },
            avatarHash: values.profileField(String.self, forKey: .avatar) { $0 },
            decorationSKUID: values.profileField(SKU.self, forKey: .decoration) { $0.skuID },
            nameplateSKUID: nameplate,
            displayNameStyle: values.profileField(UserDTO.DisplayNameStyleDTO.self, forKey: .style) {
                DisplayNameStyle(fontID: $0.fontID ?? 11, effectID: $0.effectID ?? 1, colors: $0.colors ?? [])
            }
        )
        serverTag = try values.profileField(ServerTag.self, forKey: .serverTag) { $0.fields }
    }
}

struct ProfileEditingMetadataDTO: Decodable {
    let fields: ProfileMetadataFields

    private enum CodingKeys: String, CodingKey {
        case bio, pronouns, banner, collectibles
        case accent = "accent_color"
        case theme = "theme_colors"
    }

    private struct Collectible: Decodable {
        var skuID: String
        var type: Int
        var expiresAt: String?
        enum CodingKeys: String, CodingKey {
            case skuID = "sku_id"
            case type
            case expiresAt = "expires_at"
        }
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fields = try ProfileMetadataFields(
            bio: values.profileField(String.self, forKey: .bio) { $0 },
            pronouns: values.profileField(String.self, forKey: .pronouns) { $0 },
            bannerHash: values.profileField(String.self, forKey: .banner) { $0 },
            accentColor: values.profileField(UInt32.self, forKey: .accent) { $0 },
            themeColors: values.profileField([UInt32?].self, forKey: .theme) { colors in
                guard colors.count == 2 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .theme, in: values, debugDescription: "A profile theme requires two ordered colors"
                    )
                }
                return ProfileThemeColors(primary: colors[0], accent: colors[1])
            },
            collectibles: values.profileField([Collectible].self, forKey: .collectibles) { entries in
                entries.map {
                    ProfileCollectibleReference(
                        skuID: $0.skuID, type: $0.type,
                        expiresAt: $0.expiresAt.flatMap(DiscordDate.parse)
                    )
                }
            }
        )
    }
}

private extension KeyedDecodingContainer {
    func profileField<Wire: Decodable, Value: Hashable & Sendable>(
        _ type: Wire.Type,
        forKey key: Key,
        transform: (Wire) throws -> Value
    ) throws -> ProfileStoredValue<Value> {
        guard contains(key) else { return .missing }
        if try decodeNil(forKey: key) { return .null }
        return try .value(transform(decode(type, forKey: key)))
    }
}
