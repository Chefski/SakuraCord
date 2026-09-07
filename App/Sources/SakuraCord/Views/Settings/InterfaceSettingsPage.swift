import SwiftUI

struct InterfaceSettingsPage: View {
    let model: AppModel
    let state: SettingsViewState

    @State private var value = InterfaceSettingsSnapshot.defaults
    @State private var appearanceValue = AppearanceSettingsSnapshot.defaults
    var body: some View {
        SettingsPageForm(page: .interface, state: state) {
            InterfaceMessagesSection(
                value: $appearanceValue,
                reset: resetMessageAppearance,
                state: state
            )
            InputBarSettingsSection(value: $appearanceValue, state: state)
            InterfaceTimeSection(value: $value, state: state)
        }
        .task {
            value = model.interfaceSettings
            appearanceValue = model.appearanceSettings
        }
        .onChange(of: value) { _, newValue in
            model.applyInterfaceSettings(newValue)
        }
        .onChange(of: appearanceValue) { _, newValue in
            model.applyAppearanceSettings(newValue)
        }
    }

    private func resetMessageAppearance() {
        appearanceValue.messageAppearance = .defaultStyle
        appearanceValue.messageSpacing =
            AppearanceSettingsSnapshot.defaultMessageSpacing
    }
}

private struct InterfaceMessagesSection: View {
    @Binding var value: AppearanceSettingsSnapshot
    let reset: () -> Void
    let state: SettingsViewState

    private var isUsingDefaults: Bool {
        value.messageAppearance
            == AppearanceSettingsSnapshot.defaults.messageAppearance
            && value.messageSpacing
                == AppearanceSettingsSnapshot.defaults.messageSpacing
    }

    var body: some View {
        Section {
            LabeledContent("Messages") {
                Picker("Messages", selection: $value.messageAppearance) {
                    ForEach(MessageAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .tint(SakuraCordAccentColor.color)
            }
            .settingsControlAnchor(.messageAppearance, state: state)

            LabeledContent("Density") {
                HStack {
                    Slider(
                        value: $value.messageSpacing,
                        in: AppearanceSettingsSnapshot.messageSpacingRange,
                        step: 1
                    )
                    .tint(SakuraCordAccentColor.color)
                    .frame(minWidth: 220)
                    Text("\(Int(value.messageSpacing)) pt")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .accessibilityValue(
                "\(Int(value.messageSpacing)) points between messages"
            )
            .settingsControlAnchor(.messageDensity, state: state)

            Button("Reset to Defaults", action: reset)
                .disabled(isUsingDefaults)
                .settingsControlAnchor(.resetMessageAppearance, state: state)
        } header: {
            Text("Messages", bundle: #bundle)
        }
    }
}

private struct InterfaceTimeSection: View {
    @Binding var value: InterfaceSettingsSnapshot
    let state: SettingsViewState

    var body: some View {
        Section {
            Picker("Timestamp format", selection: $value.timestampFormat) {
                ForEach(InterfaceTimestampFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .settingsControlAnchor(.timestampFormat, state: state)

            Toggle(
                "Show seconds",
                isOn: $value.includesTimestampSeconds
            )
            .tint(SakuraCordAccentColor.color)
            .settingsControlAnchor(.timestampSeconds, state: state)

            Toggle("Always show timestamps", isOn: $value.alwaysShowsTimestamps)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.alwaysShowTimestamps, state: state)
        } header: {
            Text("Timestamps", bundle: #bundle)
        }
    }
}
