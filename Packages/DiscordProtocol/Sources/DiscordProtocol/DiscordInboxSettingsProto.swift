import Foundation
import SakuraCordModels

/// Settings-proto/1 replaces each supplied top-level message. Preserve all
/// unknown fields and sibling guild/channel settings when changing Inbox state.
enum DiscordInboxSettingsProto {
    static func settings(in data: Data) -> InboxSettings {
        let root = fields(data)
        let inbox = fields(root.first { $0.field == 2 }?.payload ?? Data())
        let tab = inbox.first { $0.field == 1 }?.varint.flatMap { Int(exactly: $0).flatMap(InboxTab.init(rawValue:)) } ?? .unread
        var collapsed = Set<ChannelID>()
        var collapsedEvents = Set<GuildID>()
        for guild in fields(root.first { $0.field == 3 }?.payload ?? Data()) where guild.field == 1 {
            let guildID = fields(guild.payload ?? Data()).first(where: { $0.field == 1 }).flatMap(fixed64)
            let value = fields(guild.payload ?? Data()).first { $0.field == 2 }?.payload ?? Data()
            for channel in fields(value) where channel.field == 1 {
                let entry = fields(channel.payload ?? Data())
                guard let key = entry.first(where: { $0.field == 1 }),
                      let id = fixed64(key),
                      let settings = entry.first(where: { $0.field == 2 })?.payload,
                      fields(settings).contains(where: { $0.field == 1 && $0.varint == 1 })
                else { continue }
                if id == 1_539_033_557_786_173_450, let guildID {
                    collapsedEvents.insert(GuildID(rawValue: guildID))
                } else { collapsed.insert(ChannelID(rawValue: id)) }
            }
        }
        let favorites = Set(fields(root.first { $0.field == 15 }?.payload ?? Data()).compactMap { entry -> ChannelID? in
            guard entry.field == 1,
                  let key = fields(entry.payload ?? Data()).first(where: { $0.field == 1 }),
                  let id = fixed64(key) else { return nil }
            return ChannelID(rawValue: id)
        })
        return InboxSettings(tab: tab, collapsedChannelIDs: collapsed, favoriteChannelIDs: favorites, collapsedEventGuildIDs: collapsedEvents)
    }

    static func updatingTab(_ tab: InboxTab, in data: Data) -> Data {
        let current = fields(data).first { $0.field == 2 }?.payload ?? Data()
        return wrapped(2, replacing(1, with: Data([8, UInt8(tab.rawValue)]), in: current))
    }

    static func updatingCollapsed(_ collapsed: Bool, channelID: ChannelID, guildID: GuildID?, in data: Data) -> Data {
        let guilds = fields(data).first { $0.field == 3 }?.payload ?? Data()
        let updated = updatingMap(guilds, key: guildID?.rawValue ?? 0) { guild in
            updatingMap(guild, key: channelID.rawValue) { channel in
                replacing(1, with: collapsed ? Data([8, 1]) : Data(), in: channel)
            }
        }
        return wrapped(3, updated)
    }

    private static func updatingMap(_ data: Data, key: UInt64, update: (Data) -> Data) -> Data {
        var found = false
        var result = Data()
        for field in fields(data) {
            let entry = fields(field.payload ?? Data())
            if field.field == 1, entry.first(where: { $0.field == 1 }).flatMap(fixed64) == key {
                let value = entry.first { $0.field == 2 }?.payload ?? Data()
                result.append(wrapped(1, replacing(2, with: wrapped(2, update(value)), in: field.payload ?? Data())))
                found = true
            } else {
                result.append(field.raw)
            }
        }
        if !found {
            var entry = Data([9])
            for offset in 0 ..< 8 { entry.append(UInt8(truncatingIfNeeded: key >> UInt64(offset * 8))) }
            entry.append(wrapped(2, update(Data())))
            result.append(wrapped(1, entry))
        }
        return result
    }

    private static func fixed64(_ field: RawProtoField) -> UInt64? {
        guard field.wireType == 1 else { return nil }
        var reader = ProtoReader(data: field.raw)
        _ = reader.readTag()
        return reader.readFixed64()
    }

    private static func replacing(_ number: Int, with replacement: Data, in data: Data) -> Data {
        var result = fields(data).filter { $0.field != number }.reduce(into: Data()) { $0.append($1.raw) }
        result.append(replacement)
        return result
    }

    private static func fields(_ data: Data) -> [RawProtoField] {
        var reader = ProtoReader(data: data)
        var result: [RawProtoField] = []
        while let field = reader.readRawField() { result.append(field) }
        return result
    }

    private static func wrapped(_ number: Int, _ data: Data) -> Data {
        DiscordSettingsProto.protoLengthDelimitedField(number, data)
    }
}
