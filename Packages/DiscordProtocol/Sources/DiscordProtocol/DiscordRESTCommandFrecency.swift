import Foundation
import SakuraCordModels

public extension DiscordRESTProvider {
    func applicationCommandFrecency() async throws -> DiscordFrecencyHistory {
        let data = try await frecencySettingsProto()
        return DiscordSettingsProto.applicationCommandFrecency(from: data) ?? DiscordFrecencyHistory()
    }

    /// One PATCH carrying field 7 and any other pending usage, matching Discord's flush of
    /// command uses. The Gateway then echoes the stored proto to every session.
    func saveApplicationCommandFrecency(_ history: DiscordFrecencyHistory) async throws
        -> DiscordFrecencyHistory
    {
        let patch = DiscordSettingsProto.applicationCommandFrecencyPatch(history)
        let stored = try await persistFrecencySettingsPatch(patch)
        return DiscordSettingsProto.applicationCommandFrecency(from: stored) ?? history
    }
}
