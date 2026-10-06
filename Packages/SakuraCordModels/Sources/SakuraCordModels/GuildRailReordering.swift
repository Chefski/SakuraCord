import Foundation

/// Where a dragged server-rail item is dropped: a container and the sibling it
/// lands in front of. A nil sibling means the end of that container.
public struct GuildRailDestination: Equatable, Hashable, Sendable {
    public enum Container: Equatable, Hashable, Sendable {
        case root
        case folder(Int64)
    }

    public var container: Container
    public var before: GuildRailItem.RailIdentifier?

    public init(container: Container, before: GuildRailItem.RailIdentifier? = nil) {
        self.container = container
        self.before = before
    }
}

public extension [GuildRailItem] {
    var flattenedGuildIDs: [GuildID] {
        flatMap { item -> [GuildID] in
            switch item {
            case .guild(let id): [id]
            case .folder(let folder): folder.guildIDs
            }
        }
    }

    /// Returns the rail after moving `sources` to `destination`, or the
    /// unchanged rail when the move is invalid. Folders only move within the
    /// root, and a folder left without servers is removed.
    func moving(
        _ sources: [GuildRailItem.RailIdentifier],
        to destination: GuildRailDestination
    ) -> [GuildRailItem] {
        var seen = Set<GuildRailItem.RailIdentifier>()
        let sources = sources.filter { seen.insert($0).inserted }
        let known = Set(map(\.id)).union(flattenedGuildIDs.map(GuildRailItem.RailIdentifier.guild))
        guard !sources.isEmpty, sources.allSatisfy(known.contains) else { return self }

        guard let siblings = siblings(in: destination.container, accepting: sources) else { return self }

        // Dropping in front of a dragged item means in front of the next
        // sibling that stays behind.
        var anchor = destination.before
        if let before = anchor {
            guard let index = siblings.firstIndex(of: before) else { return self }
            anchor = siblings[index...].first { !seen.contains($0) }
        }

        let folders = Dictionary(
            compactMap { item -> (GuildRailItem.RailIdentifier, GuildRailItem)? in
                if case .folder = item { (item.id, item) } else { nil }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var result: [GuildRailItem] = compactMap { item in
            guard !seen.contains(item.id) else { return nil }
            guard case .folder(var folder) = item else { return item }
            folder.guildIDs.removeAll { seen.contains(.guild($0)) }
            return .folder(folder)
        }

        switch destination.container {
        case .root:
            let moved = sources.compactMap { source -> GuildRailItem? in
                if case .guild(let id) = source { .guild(id) } else { folders[source] }
            }
            let index = anchor.flatMap { anchor in result.firstIndex { $0.id == anchor } } ?? result.endIndex
            result.insert(contentsOf: moved, at: index)
        case .folder(let folderID):
            guard let folderIndex = result.firstIndex(where: { $0.id == .folder(folderID) }),
                  case .folder(var folder) = result[folderIndex]
            else { return self }
            let moved = sources.compactMap { source -> GuildID? in
                if case .guild(let id) = source { id } else { nil }
            }
            let index = folder.guildIDs.firstIndex { anchor == .guild($0) } ?? folder.guildIDs.endIndex
            folder.guildIDs.insert(contentsOf: moved, at: index)
            result[folderIndex] = .folder(folder)
        }

        return result.filter { item in
            if case .folder(let folder) = item { !folder.guildIDs.isEmpty } else { true }
        }
    }

    /// Returns the rail after dropping `source` onto the standalone server
    /// `target`: a new folder takes the target's place and holds the target
    /// followed by the source. Returns the unchanged rail when that is invalid.
    func combining(_ source: GuildID, onto target: GuildID, folderID: Int64) -> [GuildRailItem] {
        guard source != target, contains(.guild(target)), flattenedGuildIDs.contains(source),
              folder(folderID) == nil
        else { return self }
        return compactMap { item -> GuildRailItem? in
            switch item {
            case .guild(source):
                return nil
            case .guild(target):
                return .folder(GuildFolder(id: folderID, guildIDs: [target, source]))
            case .guild:
                return item
            case .folder(var folder):
                folder.guildIDs.removeAll { $0 == source }
                return folder.guildIDs.isEmpty ? nil : .folder(folder)
            }
        }
    }

    /// Returns the rail with a folder's name and color replaced. A blank name
    /// and a nil color both mean the default.
    func updatingFolder(_ id: Int64, name: String?, colorHex: UInt32?) -> [GuildRailItem] {
        map { item in
            guard case .folder(var folder) = item, folder.id == id else { return item }
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            folder.name = trimmed?.isEmpty == false ? trimmed : nil
            folder.colorHex = colorHex
            return .folder(folder)
        }
    }

    /// The items already in a container, or nil when it cannot take `sources`.
    private func siblings(
        in container: GuildRailDestination.Container,
        accepting sources: [GuildRailItem.RailIdentifier]
    ) -> [GuildRailItem.RailIdentifier]? {
        switch container {
        case .root:
            return map(\.id)
        case .folder(let folderID):
            guard let folder = folder(folderID),
                  sources.allSatisfy({ if case .guild = $0 { true } else { false } })
            else { return nil }
            return folder.guildIDs.map(GuildRailItem.RailIdentifier.guild)
        }
    }

    private func folder(_ id: Int64) -> GuildFolder? {
        for case .folder(let folder) in self where folder.id == id { return folder }
        return nil
    }
}
