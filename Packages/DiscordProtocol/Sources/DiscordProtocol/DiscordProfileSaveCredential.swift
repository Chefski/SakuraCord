import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    func acceptProfileSaveCredential(from data: Data, accountID: UserID, generation: UInt64) async throws {
        struct Response: Decodable { var token: String? }
        guard let token = try JSONDecoder().decode(Response.self, from: data).token,
              token != authorizationValue
        else { return }
        guard token.utf8.count > 20 else { throw PendingDiscordCredentialError.invalidCredential }
        guard currentUser?.id == accountID, profileEditingGeneration == generation, !requestSafetyCircuitIsOpen else {
            throw CancellationError()
        }
        // Discord's account save may replace the credential. Update the existing
        // REST and Gateway owners, then persist through the original credential store.
        try await gatewaySession?.replaceCredential(token)
        guard currentUser?.id == accountID, profileEditingGeneration == generation, !requestSafetyCircuitIsOpen else {
            throw CancellationError()
        }
        authorizationValue = token
        switch credentialSource {
        case let .stored(store, handle):
            _ = try await store.store(Data(token.utf8), accountID: handle.accountID)
        case let .pending(pending):
            let replacement = try PendingDiscordCredential(Data(token.utf8))
            credentialSource = .pending(replacement)
            await pending.discard()
        }
    }
}
