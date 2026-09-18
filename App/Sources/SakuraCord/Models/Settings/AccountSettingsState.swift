import Foundation
import Observation
import SakuraCordModels

@Observable
@MainActor
final class AccountSettingsState {
    private(set) var details: AccountDetails?
    private(set) var devices: [AccountDevice]?
    private(set) var isLoadingDetails = false
    private(set) var isLoadingDevices = false
    private(set) var detailsError: String?
    private(set) var devicesError: String?
    @ObservationIgnored private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load() async {
        async let details: Void = loadDetails()
        async let devices: Void = loadDevices()
        _ = await (details, devices)
    }

    func loadDetails() async {
        guard !isLoadingDetails else { return }
        let session = model.accountSession()
        isLoadingDetails = true
        detailsError = nil
        defer { isLoadingDetails = false }
        do {
            let value = try await session.provider.accountDetails()
            guard !Task.isCancelled, model.isCurrentAccountSession(session) else { return }
            details = value
        } catch {
            guard !Task.isCancelled, model.isCurrentAccountSession(session) else { return }
            detailsError = "Account information couldn’t be loaded."
        }
    }

    func loadDevices() async {
        guard !isLoadingDevices else { return }
        let session = model.accountSession()
        isLoadingDevices = true
        devicesError = nil
        defer { isLoadingDevices = false }
        do {
            let value = try await session.provider.accountDevices()
            guard !Task.isCancelled, model.isCurrentAccountSession(session) else { return }
            devices = value
        } catch {
            guard !Task.isCancelled, model.isCurrentAccountSession(session) else { return }
            devicesError = "Logged-in devices couldn’t be loaded."
        }
    }
}
