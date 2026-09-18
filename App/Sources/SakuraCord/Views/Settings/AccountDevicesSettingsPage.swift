import SakuraCordModels
import SwiftUI

struct AccountDevicesSettingsPage: View {
    let accountState: AccountSettingsState
    @State private var revealedLocations: [String: String] = [:]

    private func locationVisibility(for device: AccountDevice) -> Binding<Bool> {
        Binding(
            get: { device.location != nil && revealedLocations[device.id] == device.location },
            set: { revealedLocations[device.id] = $0 ? device.location : nil }
        )
    }

    private var allLocationsVisibility: Binding<Bool> {
        Binding(
            get: { (accountState.devices ?? []).contains { locationVisibility(for: $0).wrappedValue } },
            set: { reveal in
                revealedLocations.removeAll()
                if reveal {
                    for device in accountState.devices ?? [] {
                        revealedLocations[device.id] = device.location
                    }
                }
            }
        )
    }

    var body: some View {
        SettingsForm {
            if let error = accountState.devicesError {
                Section {
                    AccountSettingsRetryRow(message: error) {
                        await accountState.loadDevices()
                    }
                }
            }
            if let devices = accountState.devices {
                if devices.isEmpty {
                    ContentUnavailableView(
                        "No Logged-in Devices", systemImage: "desktopcomputer",
                        description: Text("Discord didn’t return any devices for this account.", bundle: #bundle)
                    )
                } else {
                    let current = devices.filter(\.isCurrentSession)
                    let others = devices.filter { !$0.isCurrentSession }
                    if !current.isEmpty {
                        Section {
                            ForEach(current) {
                                AccountDeviceRow(device: $0, isLocationRevealed: locationVisibility(for: $0))
                            }
                        } header: {
                            HStack {
                                Text("Current Device", bundle: #bundle)
                                if others.isEmpty {
                                    Spacer()
                                    AccountDeviceLocationsToggle(isRevealed: allLocationsVisibility)
                                }
                            }
                        }
                    }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) {
                                AccountDeviceRow(device: $0, isLocationRevealed: locationVisibility(for: $0))
                            }
                        } header: {
                            HStack {
                                Text(current.isEmpty ? "Devices" : "Other Devices", bundle: #bundle)
                                Spacer()
                                AccountDeviceLocationsToggle(isRevealed: allLocationsVisibility)
                            }
                        }
                    }
                }
            } else if accountState.isLoadingDevices {
                ProgressView("Loading devices…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(Text("Logged-in Devices", bundle: #bundle))
        .toolbar {
            Button {
                Task { await accountState.loadDevices() }
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
            .disabled(accountState.isLoadingDevices)
        }
        .onDisappear { revealedLocations.removeAll() }
    }
}

private struct AccountDeviceLocationsToggle: View {
    @Binding var isRevealed: Bool

    var body: some View {
        Button {
            isRevealed.toggle()
        } label: {
            Text(isRevealed ? "Hide All Locations" : "Show All Locations", bundle: #bundle)
                .font(.caption)
                .fontWeight(.regular)
                .foregroundStyle(.tint)
        }
        .buttonStyle(.borderless)
    }
}

private struct AccountDeviceRow: View {
    let device: AccountDevice
    @Binding var isLocationRevealed: Bool

    private var systemImage: String {
        switch device.operatingSystem?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "ios": "iphone"
        case "android": "smartphone"
        case "horizon os": "vision.pro"
        default: "desktopcomputer"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if device.isCurrentSession, let icon = CurrentMacHardware.icon {
                Image(nsImage: icon)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let os = device.operatingSystem, !os.isEmpty {
                        Text(os == "Mac OS X" ? "macOS" : os).fontWeight(.semibold)
                    } else {
                        Text("Unknown Device", bundle: #bundle).fontWeight(.semibold)
                    }
                    if let platform = device.platform, !platform.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(platform).foregroundStyle(.primary)
                    }
                }
                if let location = device.location, !location.isEmpty {
                    AccountDeviceLocation(location: location, isRevealed: $isLocationRevealed)
                        .id(location)
                }
                if !device.isCurrentSession {
                    if let lastUsedAt = device.lastUsedAt {
                        AccountDeviceLastUsed(date: lastUsedAt)
                    } else {
                        Text("Last used time unavailable", bundle: #bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct AccountDeviceLocation: View {
    let location: String
    @Binding var isRevealed: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isRevealed.toggle()
        } label: {
            Text(location)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .blur(radius: isRevealed ? 0 : 5)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.primary.opacity(isHovered ? 0.06 : 0), in: .rect(cornerRadius: 5))
                .contentShape(.rect)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .padding(.leading, -6)
        .onModalHover { isHovered = $0 }
        .help(Text(isRevealed ? "Click to conceal" : "Click to reveal", bundle: #bundle))
        .accessibilityLabel(Text("Location", bundle: #bundle))
        .accessibilityValue(isRevealed ? Text(location) : Text("Hidden", bundle: #bundle))
        .accessibilityHint(Text(isRevealed ? "Click to conceal" : "Click to reveal", bundle: #bundle))
        .privacySensitive()
        .transition(.identity)
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
        .onDisappear { isHovered = false }
    }
}

private struct AccountDeviceLastUsed: View {
    let date: Date
    @State private var isHovered = false

    var body: some View {
        Text("Last used \(date, format: .relative(presentation: .numeric, unitsStyle: .wide))", bundle: #bundle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .onModalHover { isHovered = $0 }
            .nativeHoverPopover(isPresented: $isHovered) {
                Text(date, format: .dateTime.month(.abbreviated).day().year().hour().minute().second())
                    .font(.subheadline.weight(.medium))
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
    }
}
