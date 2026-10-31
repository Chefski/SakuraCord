import SwiftUI

struct SoftwareUpdateOverviewSection<Destination: Hashable>: View {
    @ObservedObject var updateController: AppUpdateController
    let state: SettingsViewState
    let checkForUpdatesControlID: SettingsControlID
    let changelogControlID: SettingsControlID
    let changelogDestination: Destination

    private var versionDisplay: String {
        AboutVersionInformation().prefixedDisplay
    }

    var body: some View {
        Section {
            HStack(spacing: InterfaceScale.metric(16)) {
                VStack(alignment: .leading, spacing: InterfaceScale.metric(5)) {
                    Text("SakuraCord Version", bundle: #bundle)
                        .font(.interface(.headline))

                    Text(versionDisplay)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: InterfaceScale.metric(16))

                Button("Check Now…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                .accessibilityHint(updateController.availabilityDescription)
                .help(updateController.availabilityDescription)
                .settingsControlAnchor(checkForUpdatesControlID, state: state)
            }

            NavigationLink(value: changelogDestination) {
                Label("Open Changelog", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityHint("Shows the release notes included with SakuraCord.")
            .settingsControlAnchor(changelogControlID, state: state)
        } header: {
            Text("Updates · \(updateController.activeTrackTitle)")
        }
    }
}
