import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    public func updateProfileCustomStatus(_ requested: ProfileCustomStatus?) async throws -> ProfileCustomStatus? {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        guard let current = profileStatusSettings else {
            throw ChatProviderError.invalidRequest("Wait for your account settings to finish loading before editing your status.")
        }
        guard profileStatusSaveID == nil else {
            throw ChatProviderError.invalidRequest("A status update is already in progress.")
        }
        var status = requested
        if var value = status {
            value.text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.text.utf16.count <= 128,
                  value.emojiID.map({ UInt64($0).map { $0 > 0 } ?? false }) ?? true,
                  [value.expiresAt, value.createdAt].compactMap({ $0 }).allSatisfy({
                      $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 >= 0
                          && $0.timeIntervalSince1970 < Double(UInt64.max) / 1000
                  }) else { throw ChatProviderError.invalidRequest("Choose a valid status of 128 characters or fewer.") }
            value.createdAt = .now
            status = value.text.isEmpty && value.emojiID == nil && (value.emojiName?.isEmpty ?? true) ? nil : value
        }
        let patch = DiscordSettingsProto.updatingCustomStatus(status, in: current)
        let saveID = UUID()
        let generation = profileEditingGeneration
        profileStatusSaveID = saveID
        defer { if profileStatusSaveID == saveID { profileStatusSaveID = nil } }
        let response: UserSettingsProtoDTO = try await request(
            "/users/@me/settings-proto/1", method: "PATCH",
            body: ["settings": .string(patch.base64EncodedString())]
        )
        guard currentUser?.id == userID, generation == profileEditingGeneration, profileStatusSaveID == saveID else { throw CancellationError() }
        guard let responseData = Data(base64Encoded: response.settings),
              let saved = DiscordSettingsProto.statusSettings(in: responseData) else {
            profileStatusSettings = nil
            throw ChatProviderError.invalidRequest("Discord saved your settings but returned an unreadable status. Reconnect before editing it again.")
        }
        profileStatusSettings = saved
        publishProfileCustomStatus()
        return DiscordSettingsProto.customStatus(in: saved)
    }

    func publishProfileCustomStatus() {
        guard let userID = currentUser?.id, let profileStatusSettings else { return }
        let status = DiscordSettingsProto.customStatus(in: profileStatusSettings)
        let text = status?.displayText
        for key in cachedProfiles.keys where key.userID == userID { cachedProfiles[key]?.customStatus = text }
        for guildID in cachedMembers.keys {
            guard let index = cachedMembers[guildID]?.firstIndex(where: { $0.id == userID }) else { continue }
            cachedMembers[guildID]?[index].customStatus = text
        }
        continuation?.yield(.profileCustomStatusChanged(userID: userID, status: status))
        scheduleCustomStatusExpiration(status)
    }

    private func scheduleCustomStatusExpiration(_ status: ProfileCustomStatus?) {
        profileCustomStatusExpiryTask?.cancel()
        profileCustomStatusExpiryTask = nil
        guard let status, let expiry = status.expiresAt else { return }
        let generation = profileEditingGeneration
        profileCustomStatusExpiryTask = Task { [weak self] in
            do {
                while expiry.timeIntervalSinceNow > 0 {
                    try await Task.sleep(for: .seconds(min(86400, expiry.timeIntervalSinceNow)))
                }
                await self?.expireCustomStatus(status, generation: generation)
            } catch {}
        }
    }

    private func expireCustomStatus(_ expected: ProfileCustomStatus, generation: UInt64) async {
        do {
            while profileStatusSaveID != nil {
                try await Task.sleep(for: .milliseconds(200))
            }
            try Task.checkCancellation()
            guard generation == profileEditingGeneration,
                  profileStatusSettings.flatMap(DiscordSettingsProto.customStatus(in:)) == expected else { return }
            _ = try await updateProfileCustomStatus(nil)
        } catch {
            if !Task.isCancelled { gatewayLogger.error("Custom status expiration could not be saved.") }
        }
    }
}
