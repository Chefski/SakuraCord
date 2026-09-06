import Foundation
import SakuraCordModels

public extension DiscordRESTProvider {
    internal func cachedProfileWidgetResources(for userID: UserID) -> ProfileWidgetResources {
        var resources = ProfileWidgetResources(
            applications: profileWidgetConfigurations.keys.sorted().flatMap { profileWidgetConfigurations[$0] ?? [] },
            identities: profileWidgetIdentities[userID] ?? [], games: profileWidgetGameDetails.values.sorted { $0.id < $1.id }
        )
        if userID == currentUser?.id { resources.connections = profileWidgetConnectionStates }
        return resources
    }

    internal func resolveProfileWidgetResources(for userID: UserID, widgets: [ProfileWidget]) async throws -> ProfileWidgetResources {
        var resources = ProfileWidgetResources()
        var applicationIDs: [String] = []
        var gameIDs: [String] = []
        for widget in widgets {
            switch widget.content {
            case let .application(id): if !applicationIDs.contains(id) { applicationIDs.append(id) }
            case let .games(_, games):
                for game in games where !gameIDs.contains(game.id) { gameIDs.append(game.id) }
            case .personal, .unrecognized: break
            }
        }
        // Keep a profile usable if optional widget content fails to load. Session
        // invalidation and cancellation still terminate the whole presentation.
        do {
            if !applicationIDs.isEmpty {
                resources.identities = try await profileWidgetApplicationIdentities(for: userID)
                for id in applicationIDs { resources.applications += try await profileWidgetApplication(id: id) }
                if userID == currentUser?.id {
                    resources.connections = try await profileWidgetConnections(applicationIDs: resources.applications.map { $0.connectionApplicationID ?? $0.applicationID })
                }
            }
            if !gameIDs.isEmpty { resources.games = try await profileWidgetGames(ids: gameIDs) }
        } catch {
            if error is CancellationError || Task.isCancelled || currentUser == nil || requestSafetyCircuitIsOpen { throw error }
            resources.errorMessage = error.localizedDescription
        }
        return resources
    }

    func profileWidgetCatalogue(developer: Bool) async throws -> [ProfileApplicationWidget] {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        if let cached = profileWidgetCatalogues[developer] { return cached }
        let generation = profileEditingGeneration
        let response: ProfileWidgetCatalogueDTO = try await request(developer ? "/widget-configs/developer" : "/widget-configs/featured")
        try validateProfileWidgetSession(userID: userID, generation: generation)
        let catalogue = response.domain()
        profileWidgetCatalogues[developer] = catalogue
        for (id, configs) in Dictionary(grouping: catalogue, by: \.applicationID) { profileWidgetConfigurations[id] = configs }
        return catalogue
    }

    func profileWidgetApplication(id: String) async throws -> [ProfileApplicationWidget] {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        guard UInt64(id) != nil else { throw ChatProviderError.invalidRequest("Invalid widget application identifier.") }
        if let cached = profileWidgetConfigurations[id] { return cached }
        let generation = profileEditingGeneration
        let response: [ProfileApplicationWidgetDTO] = try await request("/applications/\(id)/widget-configs")
        try validateProfileWidgetSession(userID: userID, generation: generation)
        guard response.allSatisfy({ $0.applicationID == id }) else {
            throw ChatProviderError.invalidRequest("Discord returned a different application's widgets.")
        }
        let configs = response.map { $0.domain() }
        profileWidgetConfigurations[id] = configs
        return configs
    }

    func profileWidgetApplicationIdentities(for userID: UserID) async throws -> [ProfileWidgetApplicationIdentity] {
        guard let accountID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        let generation = profileEditingGeneration
        let response: ProfileWidgetIdentitiesDTO = try await request(
            "/users/\(userID)/application-identities", query: [URLQueryItem(name: "with_profiles", value: "true")]
        )
        try validateProfileWidgetSession(userID: accountID, generation: generation)
        let identities = response.identities.map(\.domain)
        profileWidgetIdentities[userID] = identities
        return identities
    }
}
