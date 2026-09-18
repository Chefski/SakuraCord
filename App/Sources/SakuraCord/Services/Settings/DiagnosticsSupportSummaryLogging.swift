import DiscordProtocol
import Foundation
import MediaPipeline

extension DiagnosticsSupportSummary {
    /// Only the fixed support-summary DTO crosses this boundary. Free-form
    /// status details, account identities, and device names are never encoded.
    nonisolated func installLogSnapshot(in store: DiscordAPIDiagnosticStore = .shared) {
        guard let data = try? encodedData(),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return }
        store.setSupportSummary(value)
    }

    nonisolated static func startup(releaseTrack: AppUpdateReleaseTrack) -> Self {
        Self(
            application: currentApplication(releaseTrack: releaseTrack),
            system: currentSystemSnapshot,
            statusItems: DiagnosticsSubsystem.allCases.map {
                DiagnosticsStatusItem(subsystem: $0, health: .checking, detail: "Not checked")
            },
            diagnosticModes: .init(
                capturesDetailedSanitizedPayloads: false,
                savesSanitizedDiagnosticsToDisk: false,
                retainedEntryCount: 0
            )
        )
    }

    @MainActor
    static func refreshLogSnapshot(model: AppModel, updateController: AppUpdateController) async {
        async let notifications = model.notificationAuthorizationStatus()
        let cache: DiagnosticsMediaCacheCheck
        do {
            if let status = try await SharedMediaDataLoader.shared.diskCacheStatus() {
                cache = .available(status)
            } else {
                cache = .unavailable
            }
        } catch {
            cache = .failed
        }
        let store = DiscordAPIDiagnosticStore.shared
        let summary = Self(
            application: currentApplication(releaseTrack: updateController.releaseTrack),
            system: currentSystemSnapshot,
            statusItems: await DiagnosticsStatusBuilder.make(
                model: model,
                updateController: updateController,
                notificationPermissionStatus: notifications,
                mediaPermissions: VoiceMediaPermissionSnapshot.current(),
                mediaCacheCheck: cache
            ),
            diagnosticModes: .init(
                capturesDetailedSanitizedPayloads: store.retainsPayloadDetails,
                savesSanitizedDiagnosticsToDisk: store.savesDiagnosticsToDisk,
                retainedEntryCount: store.retainedEntryCount,
                capturesConnectionMetrics: store.capturesConnectionMetrics
            )
        )
        summary.installLogSnapshot(in: store)
    }
}
