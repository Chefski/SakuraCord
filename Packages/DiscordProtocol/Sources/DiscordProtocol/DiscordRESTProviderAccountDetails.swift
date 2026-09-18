import Foundation
import SakuraCordModels

public extension DiscordRESTProvider {
    func accountDetails() async throws -> AccountDetails {
        guard let user = currentUser, !requestSafetyCircuitIsOpen else { throw ChatProviderError.unauthenticated }
        if let currentAccountDetails, currentAccountDetails.userID == user.id {
            return currentAccountDetails
        }
        let revision = accountInformationRevision
        let response: DiscordAccountDetailsDTO = try await request("/users/@me")
        try Task.checkCancellation()
        guard currentUser?.id == user.id, revision == accountInformationRevision, !requestSafetyCircuitIsOpen else { throw CancellationError() }
        // A Gateway update received during the read remains authoritative.
        if let currentAccountDetails, currentAccountDetails.userID == user.id { return currentAccountDetails }
        guard let details = response.domain(), details.userID == user.id else {
            throw ChatProviderError.invalidRequest("Discord did not return this account's details.")
        }
        currentAccountDetails = details
        return details
    }

    func accountDevices() async throws -> [AccountDevice] {
        guard let user = currentUser, !requestSafetyCircuitIsOpen else { throw ChatProviderError.unauthenticated }
        let revision = accountInformationRevision
        let response: DiscordAccountSessionsDTO = try await request("/auth/sessions")
        try Task.checkCancellation()
        guard currentUser?.id == user.id, revision == accountInformationRevision, !requestSafetyCircuitIsOpen else { throw CancellationError() }
        return response.userSessions.map { $0.domain(currentSessionIDHash: currentAuthSessionIDHash) }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }
}
