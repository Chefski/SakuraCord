import Foundation
import GRDB
import SakuraCordModels

public struct DraftStorageSummary: Equatable, Sendable {
    public let draftCount: Int
    public let approximateByteCount: Int64

    public init(draftCount: Int, approximateByteCount: Int64) {
        self.draftCount = draftCount
        self.approximateByteCount = approximateByteCount
    }
}

/// Per-account storage is intentionally limited to user-authored state, such as
/// drafts and invite links the account created. Discord workspace, message,
/// read, and Gateway state belongs to the running session and is never written here.
public actor SakuraCordDatabase {
    private let queue: DatabaseQueue

    public init(accountID: AccountID, directory: URL? = nil) throws {
        let root = try directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: root.appending(path: "account-\(accountID).sqlite").path)
        try Self.migrator.migrate(queue)
    }

    public init(inMemory: Bool) throws {
        queue = try DatabaseQueue()
        try Self.migrator.migrate(queue)
    }

    public func saveDraft(_ content: String, channelID: ChannelID) throws {
        try queue.write { db in
            if content.isEmpty {
                _ = try DraftRecord.deleteOne(db, key: channelID.description)
            } else {
                try DraftRecord(
                    channelID: channelID.description,
                    content: content,
                    updatedAt: .now
                ).save(db)
            }
        }
    }

    public func draft(channelID: ChannelID) throws -> String {
        try queue.read { db in
            try DraftRecord.fetchOne(db, key: channelID.description)?.content ?? ""
        }
    }

    public func recentDraftChannelIDs() throws -> [ChannelID] {
        try queue.read { db in
            try DraftRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .compactMap { ChannelID($0.channelID) }
        }
    }

    public func draftStorageSummary() throws -> DraftStorageSummary {
        try queue.read { db in
            let records = try DraftRecord.fetchAll(db)
            return DraftStorageSummary(
                draftCount: records.count,
                approximateByteCount: records.reduce(into: 0) { total, record in
                    total += Int64(record.content.utf8.count)
                }
            )
        }
    }

    public func clearAccountData() throws {
        try clearDrafts()
        try clearCreatedInvites()
    }

    public func saveCreatedInvite(_ invite: CreatedServerInvite) throws {
        try queue.write { db in try CreatedInviteRecord(invite).save(db) }
    }

    /// Unexpired invites for one server, newest first. Expired rows are pruned on read.
    public func createdInvites(guildID: GuildID, now: Date = .now) throws -> [CreatedServerInvite] {
        try queue.write { db in
            try CreatedInviteRecord.filter(Column("expiresAt") != nil && Column("expiresAt") <= now).deleteAll(db)
            return try CreatedInviteRecord
                .filter(Column("guildID") == guildID.description)
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .compactMap(\.invite)
        }
    }

    public func deleteCreatedInvite(code: String) throws {
        _ = try queue.write { db in try CreatedInviteRecord.deleteOne(db, key: code) }
    }

    public func clearCreatedInvites() throws {
        _ = try queue.write { db in try CreatedInviteRecord.deleteAll(db) }
    }

    public func clearDrafts() throws {
        _ = try queue.write { db in
            _ = try DraftRecord.deleteAll(db)
        }
    }

    private static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "SakuraCord/Accounts", directoryHint: .isDirectory)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-core") { db in
            try db.create(table: "messages") { table in
                table.primaryKey("id", .text)
                table.column("channelID", .text).notNull().indexed()
                table.column("timestamp", .datetime).notNull().indexed()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "drafts") { table in
                table.primaryKey("channelID", .text)
                table.column("content", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "gatewaySession") { table in
                table.primaryKey("accountID", .text)
                table.column("sessionID", .text)
                table.column("resumeURL", .text)
                table.column("sequence", .integer)
            }
        }
        migrator.registerMigration("v2-message-timeline-index") { db in
            try db.create(
                index: "messages_channel_timestamp",
                on: "messages",
                columns: ["channelID", "timestamp"]
            )
        }
        migrator.registerMigration("v3-conversation-page-boundary") { db in
            try db.create(table: "conversationPages") { table in
                table.primaryKey("channelID", .text)
                table.column("hasMoreBefore", .boolean).notNull()
            }
        }
        migrator.registerMigration("v4-bootstrap-snapshot") { db in
            try db.create(table: "bootstrapSnapshots") { table in
                table.primaryKey("id", .integer)
                table.column("payload", .blob).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v5-account-presentation") { db in
            try db.create(table: "accountPresentation") { table in
                table.primaryKey("id", .integer)
                table.column("selectedChannelID", .text).notNull()
            }
        }
        // These names are retained so databases created by older builds keep a
        // monotonic migration history. Their derived-cache work is obsolete.
        migrator.registerMigration("v6-message-snowflake-order") { _ in }
        migrator.registerMigration("v7-refresh-bootstrap-unread-cache") { _ in }
        migrator.registerMigration("v8-session-only-cache") { db in
            try db.execute(sql: "DELETE FROM accountPresentation")
            try db.execute(sql: "DELETE FROM bootstrapSnapshots")
            try db.execute(sql: "DELETE FROM conversationPages")
            try db.execute(sql: "DELETE FROM gatewaySession")
            try db.execute(sql: "DELETE FROM messages")
        }
        migrator.registerMigration("v9-drop-persistent-discord-cache") { db in
            try db.drop(table: "accountPresentation")
            try db.drop(table: "bootstrapSnapshots")
            try db.drop(table: "conversationPages")
            try db.drop(table: "gatewaySession")
            try db.drop(table: "messages")
        }
        migrator.registerMigration("v10-onboarding-drafts") { db in
            try db.create(table: "onboardingDrafts") { table in
                table.primaryKey("guildID", .text)
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("v11-session-only-onboarding") { db in
            try db.drop(table: "onboardingDrafts")
        }
        migrator.registerMigration("v12-created-invites") { db in
            try db.create(table: "createdInvites") { table in
                table.primaryKey("code", .text)
                table.column("guildID", .text).notNull().indexed()
                table.column("channelID", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("expiresAt", .datetime)
                table.column("maxAge", .integer).notNull()
                table.column("maxUses", .integer).notNull()
            }
        }
        return migrator
    }
}

private struct DraftRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "drafts"
    var channelID: String
    var content: String
    var updatedAt: Date
}

private struct CreatedInviteRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "createdInvites"
    var code: String
    var guildID: String
    var channelID: String
    var createdAt: Date
    var expiresAt: Date?
    var maxAge: Int
    var maxUses: Int

    init(_ invite: CreatedServerInvite) {
        code = invite.reference.code
        guildID = invite.guildID.description
        channelID = invite.channelID.description
        createdAt = invite.createdAt
        expiresAt = invite.expiresAt
        maxAge = invite.maxAge
        maxUses = invite.maxUses
    }

    var invite: CreatedServerInvite? {
        guard let reference = ServerInviteReference(code), let guildID = GuildID(guildID),
              let channelID = ChannelID(channelID) else { return nil }
        return CreatedServerInvite(reference: reference, guildID: guildID, channelID: channelID,
                                   createdAt: createdAt, expiresAt: expiresAt, maxAge: maxAge, maxUses: maxUses)
    }
}
