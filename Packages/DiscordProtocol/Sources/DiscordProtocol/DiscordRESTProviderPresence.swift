import Foundation
import SakuraCordModels

extension DiscordRESTProvider {
    public func currentStatus() async -> PresenceStatus {
        presenceStatus
    }

    /// The account's StatusSettings own the status. Publish the change to the
    /// Gateway at once, then save the complete status subtree. Whatever the
    /// outcome, the status then follows the settings held after the save, so
    /// a failed save rolls back unless the Gateway already confirmed it.
    public func updateStatus(_ status: PresenceStatus) async throws {
        guard status != .offline else {
            throw ChatProviderError.invalidRequest("Choose Online, Idle, Do Not Disturb or Invisible.")
        }
        do {
            _ = try await saveStatusSettings(beforeRequest: {
                if setPresenceStatus(status) { await publishPresenceStatus() }
            }, { DiscordSettingsProto.updatingPresenceStatus(status, in: $0) })
        } catch {
            await syncAccountPresenceStatus()
            throw error
        }
        await syncAccountPresenceStatus()
    }

    /// Returns whether the status changed.
    func setPresenceStatus(_ status: PresenceStatus) -> Bool {
        guard status != presenceStatus else { return false }
        presenceStatus = status
        continuation?.yield(.currentStatusChanged(status))
        return true
    }

    /// Adopts the status in the account settings and republishes a change,
    /// including one made on another device.
    func syncAccountPresenceStatus() async {
        guard let profileStatusSettings else { return }
        if setPresenceStatus(DiscordSettingsProto.presenceStatus(in: profileStatusSettings)) {
            await publishPresenceStatus()
        }
    }

    /// Ready adopts the account status before projecting members, so the first
    /// presence update repeats it instead of replacing it.
    func applyReadyPresenceStatus(_ encoded: String?) {
        guard let encoded, let data = Data(base64Encoded: encoded) else { return }
        _ = setPresenceStatus(DiscordSettingsProto.presenceStatus(
            in: DiscordSettingsProto.statusSettings(in: data) ?? Data()
        ))
    }

    /// Before a session is ready the lifecycle synchronization sends the
    /// current status, so an unavailable Gateway is not an error here.
    func publishPresenceStatus() async {
        guard gatewayReady else { return }
        do {
            try await sendGateway(DiscordGatewayPayloadFactory.presenceUpdate(status: presenceStatus))
        } catch {
            gatewayLogger.error("Presence update could not be sent: \(error.localizedDescription, privacy: .public)")
        }
    }
}
