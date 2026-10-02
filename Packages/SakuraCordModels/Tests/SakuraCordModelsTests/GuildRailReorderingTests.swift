import Foundation
@testable import SakuraCordModels
import Testing

@Test func `server rail moves reorder servers and carry them into and out of folders`() {
    func guild(_ id: UInt64) -> GuildRailItem { .guild(GuildID(rawValue: id)) }
    func folder(_ id: Int64, _ guildIDs: [UInt64]) -> GuildRailItem {
        .folder(GuildFolder(id: id, name: "Folder \(id)", guildIDs: guildIDs.map(GuildID.init(rawValue:))))
    }
    func id(_ guild: UInt64) -> GuildRailItem.RailIdentifier { .guild(GuildID(rawValue: guild)) }
    let rail = [guild(1), folder(7, [2, 3]), guild(4), folder(8, [5])]

    // Reordering within the root, including a folder and the end position.
    #expect(rail.moving([id(4)], to: .init(container: .root, before: id(1)))
        == [guild(4), guild(1), folder(7, [2, 3]), folder(8, [5])])
    #expect(rail.moving([.folder(7)], to: .init(container: .root))
        == [guild(1), guild(4), folder(8, [5]), folder(7, [2, 3])])

    // Into a folder, within a folder, and between folders.
    #expect(rail.moving([id(1)], to: .init(container: .folder(7), before: id(3)))
        == [folder(7, [2, 1, 3]), guild(4), folder(8, [5])])
    #expect(rail.moving([id(2)], to: .init(container: .folder(7)))
        == [guild(1), folder(7, [3, 2]), guild(4), folder(8, [5])])
    #expect(rail.moving([id(3)], to: .init(container: .folder(8), before: id(5)))
        == [guild(1), folder(7, [2]), guild(4), folder(8, [3, 5])])

    // Out of a folder; taking the last server removes the folder, even when
    // that folder is the drop anchor.
    #expect(rail.moving([id(3)], to: .init(container: .root, before: id(4)))
        == [guild(1), folder(7, [2]), guild(3), guild(4), folder(8, [5])])
    #expect(rail.moving([id(5)], to: .init(container: .root, before: .folder(8)))
        == [guild(1), folder(7, [2, 3]), guild(4), guild(5)])

    // Dropping in place, nesting a folder, and unknown items change nothing.
    #expect(rail.moving([id(4)], to: .init(container: .root, before: id(4))) == rail)
    #expect(rail.moving([.folder(8)], to: .init(container: .folder(7))) == rail)
    #expect(rail.moving([id(9)], to: .init(container: .root)) == rail)
    #expect(rail.moving([id(1)], to: .init(container: .folder(7), before: id(4))) == rail)

    // Dropping a server onto a standalone server makes a folder in the
    // target's place; an in-use folder ID or a foldered target is rejected.
    #expect(rail.combining(GuildID(rawValue: 4), onto: GuildID(rawValue: 1), folderID: 9)
        == [.folder(GuildFolder(id: 9, guildIDs: [GuildID(rawValue: 1), GuildID(rawValue: 4)])), folder(7, [2, 3]), folder(8, [5])])
    #expect(rail.combining(GuildID(rawValue: 5), onto: GuildID(rawValue: 4), folderID: 9)
        == [guild(1), folder(7, [2, 3]), .folder(GuildFolder(id: 9, guildIDs: [GuildID(rawValue: 4), GuildID(rawValue: 5)]))])
    #expect(rail.combining(GuildID(rawValue: 4), onto: GuildID(rawValue: 1), folderID: 7) == rail)
    #expect(rail.combining(GuildID(rawValue: 4), onto: GuildID(rawValue: 2), folderID: 9) == rail)

    // Folder settings: a blank name and a nil color mean the defaults.
    let renamed = rail.updatingFolder(8, name: "  Art  ", colorHex: 0x1ABC9C)
    #expect(renamed.last == .folder(GuildFolder(id: 8, name: "Art", colorHex: 0x1ABC9C, guildIDs: [GuildID(rawValue: 5)])))
    #expect(renamed.updatingFolder(8, name: " ", colorHex: nil).last
        == .folder(GuildFolder(id: 8, guildIDs: [GuildID(rawValue: 5)])))
}
