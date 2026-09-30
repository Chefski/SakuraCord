import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    public func updateProfileCustomStatus(_ requested: ProfileCustomStatus?) async throws -> ProfileCustomStatus? {
        guard currentUser != nil else { throw ChatProviderError.unauthenticated }
        guard profileStatusSettings != nil else {
            throw ChatProviderError.invalidRequest("Wait for your account settings to finish loading before editing your status.")
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
        let saved = try await saveStatusSettings(userInitiated: true) { DiscordSettingsProto.updatingCustomStatus(status, in: $0) }
        return saved.flatMap(DiscordSettingsProto.customStatus(in:))
    }

    // Official stable622805 module594061 `persistChanges`.
    /// The single settings-proto/1 writer for StatusSettings, one save at a
    /// time, carrying any pending status edit. With `pendingEdit` it writes
    /// only while that edit is pending and returns nil otherwise.
    func saveStatusSettings(
        pendingEdit editID: UInt64? = nil,
        userInitiated: Bool,
        updating change: (Data) -> Data = { DiscordSettingsProto.protoLengthDelimitedField(11, $0) }
    ) async throws -> Data? {
        guard let userID = currentUser?.id else { throw ChatProviderError.unauthenticated }
        let generation = profileEditingGeneration
        await waitForStatusSettingsSave()
        guard currentUser?.id == userID, generation == profileEditingGeneration, var current = profileStatusSettings else {
            throw CancellationError()
        }
        let edit = pendingStatusEdit
        if let editID, edit?.id != editID { return nil }
        if let edit {
            let merged = DiscordSettingsProto.updatingPresenceStatus(edit.status, in: current, now: .now)
            current = DiscordSettingsProto.statusSettings(in: merged) ?? current
        }
        var body: [String: JSONValue] = ["settings": .string(change(current).base64EncodedString())]
        if let version = edit?.requiredDataVersion { body["required_data_version"] = .number(Double(version)) }
        let saveID = UUID()
        profileStatusSaveID = saveID
        defer { if profileStatusSaveID == saveID { finishStatusSettingsSave() } }
        let response: UserSettingsProtoDTO
        do {
            response = try await patchUserSettings(body, retriesRateLimit: userInitiated)
        } catch {
            guard currentUser?.id == userID, generation == profileEditingGeneration, profileStatusSaveID == saveID else {
                throw CancellationError()
            }
            guard error is UserSettingsRejection else { throw error }
            endPendingStatusEdit(edit?.id)
            await reloadUserSettings()
            throw ChatProviderError.invalidRequest("Discord rejected this status change. Your saved status is shown again.")
        }
        guard currentUser?.id == userID, generation == profileEditingGeneration, profileStatusSaveID == saveID else { throw CancellationError() }
        let outOfDate = response.outOfDate == true
        guard let responseData = Data(base64Encoded: response.settings),
              let saved = DiscordSettingsProto.statusSettings(in: responseData) ?? (outOfDate ? Data() : nil) else {
            profileStatusSettings = nil
            throw ChatProviderError.invalidRequest("Discord saved your settings but returned an unreadable status. Reconnect before editing it again.")
        }
        let accepted = acceptSavedStatusSettings(saved, root: responseData, editID: edit?.id)
        publishProfileCustomStatus()
        await sendPresenceIfChanged()
        if outOfDate {
            gatewayLogger.info("Status settings were out of date; the server's settings were kept.")
            if userInitiated {
                throw ChatProviderError.invalidRequest("Your status changed on another device, so this change was not saved.")
            }
        }
        return accepted
    }

    /// A Gateway update can overtake an in-flight REST response. Complete only
    /// the acknowledged edit, then expose the newest authoritative settings.
    func acceptSavedStatusSettings(_ saved: Data, root: Data, editID: UInt64?) -> Data {
        let version = DiscordSettingsProto.dataVersion(in: root)
        let isStale = version.flatMap { incoming in profileStatusSettingsDataVersion.map { incoming < $0 } } ?? false
        let accepted = isStale ? profileStatusSettings ?? saved : saved
        endPendingStatusEdit(editID)
        if !isStale, let version {
            profileStatusSettingsDataVersion = version
            settingsDataVersion = max(settingsDataVersion ?? version, version)
        }
        adoptStatusSettings(accepted)
        return accepted
    }

    /// One StatusSettings save is in flight at a time; later writers wait here.
    func waitForStatusSettingsSave() async {
        while profileStatusSaveID != nil {
            await withCheckedContinuation { statusSettingsSaveWaiters.append($0) }
        }
    }

    func finishStatusSettingsSave() {
        profileStatusSaveID = nil
        let waiters = statusSettingsSaveWaiters
        statusSettingsSaveWaiters = []
        for waiter in waiters { waiter.resume() }
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
            await waitForStatusSettingsSave()
            try Task.checkCancellation()
            guard generation == profileEditingGeneration,
                  profileStatusSettings.flatMap(DiscordSettingsProto.customStatus(in:)) == expected else { return }
            _ = try await saveStatusSettings(userInitiated: false) { DiscordSettingsProto.updatingCustomStatus(nil, in: $0) }
        } catch {
            if !Task.isCancelled { gatewayLogger.error("Custom status expiration could not be saved.") }
        }
    }
}
