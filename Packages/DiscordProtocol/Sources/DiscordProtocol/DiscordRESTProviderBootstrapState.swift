import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func currentActiveJoinedThreads() -> [MessageThreadSummary] {
        var seen = Set<ChannelID>()
        return cachedJoinedThreadOrder.compactMap { threadID in
            guard seen.insert(threadID).inserted,
                  let thread = cachedJoinedThreads[threadID], !thread.isArchived
            else { return nil }
            return thread
        } + cachedJoinedThreads.values
            .filter { !seen.contains($0.id) && !$0.isArchived }
            .sorted { $0.id < $1.id }
    }

    func waitForInitialGatewaySnapshot() async throws -> InitialGatewaySnapshot {
        if let initialGatewaySnapshotResult {
            return try initialGatewaySnapshotResult.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            initialGatewaySnapshotContinuation = continuation
        }
    }

    func finishInitialGatewaySnapshot(_ snapshot: InitialGatewaySnapshot) {
        guard initialGatewaySnapshotResult == nil else { return }
        // GatewaySession emits READY dispatch before its `.ready` state event.
        // Bootstrap resumes here, so immediate channel loads must already be
        // allowed to resolve missing message authors through the Gateway.
        gatewayReady = true
        initialGatewaySnapshotResult = .success(snapshot)
        initialGatewaySnapshotContinuation?.resume(returning: snapshot)
        initialGatewaySnapshotContinuation = nil
    }

    func failInitialGatewaySnapshot(_ error: any Error) {
        guard initialGatewaySnapshotResult == nil else { return }
        initialGatewaySnapshotResult = .failure(error)
        initialGatewaySnapshotContinuation?.resume(throwing: error)
        initialGatewaySnapshotContinuation = nil
    }

    func failInitialGatewaySnapshotOnTerminalDisconnect(_ state: ConnectionState) {
        guard state == .disconnected else { return }
        failInitialGatewaySnapshot(
            ChatProviderError.invalidRequest(
                "Discord's Gateway disconnected before initial state was ready."
            )
        )
    }

    static func applyingGuildLayout(
        _ layout: DiscordGuildLayout,
        to guilds: [Guild]
    ) -> (guilds: [Guild], railItems: [GuildRailItem]) {
        let byID = Dictionary(uniqueKeysWithValues: guilds.map { ($0.id, $0) })
        let folderGuildIDs = layout.folders.flatMap(\.guildIDs)
        let orderedIDs = folderGuildIDs.isEmpty ? layout.guildPositions : folderGuildIDs
        guard !orderedIDs.isEmpty else {
            return (guilds, guilds.map { .guild($0.id) })
        }

        let referenced = Set(orderedIDs)
        let omitted =
            guilds
                .filter { !referenced.contains($0.id) }
                .sorted { $0.id.rawValue > $1.id.rawValue }
        var railItems = omitted.map { GuildRailItem.guild($0.id) }
        var emittedGuildIDs = Set(omitted.map(\.id))
        var emittedFolderIDs: Set<Int64> = []

        if layout.folders.isEmpty {
            for id in layout.guildPositions
                where byID[id] != nil && emittedGuildIDs.insert(id).inserted {
                railItems.append(.guild(id))
            }
        } else {
            for decodedFolder in layout.folders {
                let validIDs = decodedFolder.guildIDs.filter {
                    byID[$0] != nil && !emittedGuildIDs.contains($0)
                }
                emittedGuildIDs.formUnion(validIDs)
                guard !validIDs.isEmpty else { continue }
                if let id = decodedFolder.id, emittedFolderIDs.insert(id).inserted {
                    railItems.append(
                        .folder(
                            GuildFolder(
                                id: id,
                                name: decodedFolder.name,
                                colorHex: decodedFolder.colorHex,
                                guildIDs: validIDs
                            )))
                } else {
                    railItems.append(contentsOf: validIDs.map(GuildRailItem.guild))
                }
            }
        }

        let flattenedIDs = railItems.flatMap { item -> [GuildID] in
            switch item {
            case .guild(let id): [id]
            case .folder(let folder): folder.guildIDs
            }
        }
        let orderedGuilds = flattenedIDs.compactMap { byID[$0] }
        gatewayLogger.info(
            "Applied guild folder settings; folders=\(emittedFolderIDs.count), guilds=\(orderedGuilds.count), omitted=\(omitted.count)"
        )
        return (orderedGuilds, railItems)
    }

    static func applyingGuildOrder(_ orderedIDs: [GuildID], to guilds: [Guild]) -> [Guild] {
        let byID = Dictionary(uniqueKeysWithValues: guilds.map { ($0.id, $0) })
        let ordered = orderedIDs.compactMap { byID[$0] }
        let orderedSet = Set(orderedIDs)
        let omitted =
            guilds
                .filter { !orderedSet.contains($0.id) }
                .sorted { $0.id.rawValue > $1.id.rawValue }
        gatewayLogger.info(
            "Applied guild settings order; ordered=\(ordered.count), omitted=\(omitted.count)"
        )
        // Match Discord/Paicord's unlisted-guild fallback: guilds absent from the
        // folder payload appear first, newest joined/created first. Guild IDs are
        // time-sortable snowflakes and are the bootstrap-safe proxy for join date.
        return omitted + ordered
    }
}

nonisolated struct DiscordInstallationExperimentsDTO: Decodable {
    let installation: String?
}
