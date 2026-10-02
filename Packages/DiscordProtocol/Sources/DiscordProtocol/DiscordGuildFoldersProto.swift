import Foundation
import SakuraCordModels

extension DiscordSettingsProto {
    /// settings-proto/1 replaces the complete GuildFolders message. Like the
    /// first-party client, write one entry per rail item, a standalone server
    /// being an entry without a folder ID, and retain `guild_positions` and
    /// unknown fields. Unlike it, keep stored server IDs the rail is not
    /// showing, so an incomplete guild catalogue cannot erase folder contents.
    static func updatingGuildFolders(_ items: [GuildRailItem], in current: Data) -> Data {
        struct StoredFolder {
            var decoded: DiscordGuildLayout.Folder
            var metadata: [RawProtoField]
        }

        var stored: [StoredFolder] = []
        var retainedFields = Data()
        var reader = ProtoReader(data: current)
        while let field = reader.readRawField() {
            guard field.field == 1, field.wireType == 2, let payload = field.payload else {
                retainedFields.append(field.raw)
                continue
            }
            var metadata: [RawProtoField] = []
            var folderReader = ProtoReader(data: payload)
            while let folderField = folderReader.readRawField() {
                if folderField.field != 1 { metadata.append(folderField) }
            }
            stored.append(StoredFolder(decoded: folder(from: payload), metadata: metadata))
        }

        var written = Set(items.flattenedGuildIDs)
        func unshownGuildIDs(in folder: StoredFolder) -> [GuildID] {
            folder.decoded.guildIDs.filter { written.insert($0).inserted }
        }
        var storedByID: [Int64: StoredFolder] = [:]
        for folder in stored {
            if let id = folder.decoded.id, storedByID[id] == nil { storedByID[id] = folder }
        }

        var result = Data()
        var writtenFolderIDs: Set<Int64> = []
        for item in items {
            switch item {
            case .guild(let id):
                result.append(guildFolderField(guildIDs: [id], metadata: Data()))
            case .folder(let folder):
                writtenFolderIDs.insert(folder.id)
                let existing = storedByID[folder.id]
                result.append(guildFolderField(
                    guildIDs: folder.guildIDs + (existing.map { unshownGuildIDs(in: $0) } ?? []),
                    metadata: existing.map { guildFolderMetadata(folder, replacing: $0.metadata, of: $0.decoded) }
                        ?? guildFolderMetadata(folder)
                ))
            }
        }
        for folder in stored where folder.decoded.id.map({ !writtenFolderIDs.contains($0) }) ?? true {
            let guildIDs = unshownGuildIDs(in: folder)
            guard !guildIDs.isEmpty else { continue }
            result.append(guildFolderField(
                guildIDs: guildIDs,
                metadata: folder.metadata.reduce(into: Data()) { $0.append($1.raw) }
            ))
        }
        result.append(retainedFields)
        return result
    }

    /// Keeps a stored folder's bytes, including unknown fields, and rewrites
    /// only a name or color that the rail has changed.
    private static func guildFolderMetadata(
        _ folder: GuildFolder,
        replacing stored: [RawProtoField],
        of decoded: DiscordGuildLayout.Folder
    ) -> Data {
        var replacements: [Int: Data] = [:]
        if folder.name != decoded.name { replacements[3] = guildFolderNameField(folder.name) }
        if folder.colorHex != decoded.colorHex { replacements[4] = guildFolderColorField(folder.colorHex) }
        var metadata = Data()
        for field in stored {
            if let replacement = replacements[field.field] {
                metadata.append(replacement)
                replacements[field.field] = Data()
            } else {
                metadata.append(field.raw)
            }
        }
        for number in replacements.keys.sorted() {
            metadata.append(replacements[number] ?? Data())
        }
        return metadata
    }

    private static func guildFolderField(guildIDs: [GuildID], metadata: Data) -> Data {
        var packed = Data()
        for id in guildIDs {
            for offset in 0 ..< 8 { packed.append(UInt8(truncatingIfNeeded: id.rawValue >> UInt64(offset * 8))) }
        }
        return protoLengthDelimitedField(1, protoLengthDelimitedField(1, packed) + metadata)
    }

    private static func guildFolderMetadata(_ folder: GuildFolder) -> Data {
        protoLengthDelimitedField(2, protoVarintField(1, UInt64(bitPattern: folder.id)))
            + guildFolderNameField(folder.name) + guildFolderColorField(folder.colorHex)
    }

    private static func guildFolderNameField(_ name: String?) -> Data {
        guard let name, !name.isEmpty else { return Data() }
        return protoLengthDelimitedField(3, protoStringField(1, name))
    }

    private static func guildFolderColorField(_ color: UInt32?) -> Data {
        guard let color else { return Data() }
        return protoLengthDelimitedField(4, protoVarintField(1, UInt64(color)))
    }
}
