import SwiftUI

struct InterfaceSettingsPage: View {
    let model: AppModel
    let state: SettingsViewState

    @State private var value = InterfaceSettingsSnapshot.defaults
    @State private var appearanceValue = AppearanceSettingsSnapshot.defaults
    var body: some View {
        SettingsPageForm(page: .interface, state: state) {
            InterfaceSizeSection(value: $appearanceValue.interfaceSize, state: state)
            InterfaceMessagesSection(
                value: $appearanceValue,
                interface: value,
                accessibility: model.accessibilitySettings,
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
        // Keyboard shortcuts can change the size while this page is open.
        .onChange(of: model.appearanceSettings.interfaceSize) { _, newValue in
            appearanceValue.interfaceSize = newValue
        }
    }

    private func resetMessageAppearance() {
        appearanceValue.messageAppearance = .defaultStyle
        appearanceValue.messageSpacing =
            AppearanceSettingsSnapshot.defaultMessageSpacing
    }
}

private struct InterfaceSizeSection: View {
    @Binding var value: Double
    let state: SettingsViewState

    // The settings window follows the interface size too, so dragging
    // previews the value and applies it on release; keyboard and
    // accessibility adjustments apply immediately.
    @State private var draft = InterfaceScale.defaultFactor
    @State private var isEditing = false

    // Whole percentages keep the native slider's step count exact; the
    // fractional range 0.8...1.4 can otherwise lose its final 0.1 step.
    private var percentage: Binding<Double> {
        Binding(
            get: { (draft * 100).rounded() },
            set: { draft = $0 / 100 }
        )
    }

    private var percentageRange: ClosedRange<Double> {
        (InterfaceScale.range.lowerBound * 100).rounded()
            ... (InterfaceScale.range.upperBound * 100).rounded()
    }

    var body: some View {
        Section {
            LabeledContent("Interface size") {
                HStack(spacing: InterfaceScale.metric(10)) {
                    Slider(
                        value: percentage,
                        in: percentageRange,
                        step: (InterfaceScale.step * 100).rounded(),
                        neutralValue: InterfaceScale.defaultFactor * 100
                    ) {
                        Text("Interface size", bundle: #bundle)
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.interface(.caption))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Smaller", bundle: #bundle))
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                            .font(.interface(.title3))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Larger", bundle: #bundle))
                    } tick: { stop in
                        stop == InterfaceScale.defaultFactor * 100
                            ? SliderTick(stop) { Text("Default", bundle: #bundle) }
                            : SliderTick(stop)
                    } onEditingChanged: { editing in
                        isEditing = editing
                        if !editing { value = draft }
                    }
                    .labelsHidden()
                    .tint(SakuraCordAccentColor.color)
                    .frame(minWidth: InterfaceScale.metric(220))
                    Text(draft, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: InterfaceScale.metric(42), alignment: .trailing)
                }
            }
            .accessibilityValue(
                Text(draft, format: .percent.precision(.fractionLength(0)))
            )
            .settingsControlAnchor(.interfaceSize, state: state)
        } header: {
            Text("Interface", bundle: #bundle)
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !isEditing { draft = newValue }
        }
        .onChange(of: draft) { _, newValue in
            if !isEditing { value = newValue }
        }
    }
}

private struct InterfaceMessagesSection: View {
    @Binding var value: AppearanceSettingsSnapshot
    let interface: InterfaceSettingsSnapshot
    let accessibility: AccessibilitySettingsSnapshot
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
                    .frame(minWidth: InterfaceScale.metric(220))
                    Text("\(Int(value.messageSpacing)) pt")
                        .monospacedDigit()
                        .frame(width: InterfaceScale.metric(42), alignment: .trailing)
                }
            }
            .accessibilityValue(
                "\(Int(value.messageSpacing)) points between messages"
            )
            .settingsControlAnchor(.messageDensity, state: state)

            MessageAppearancePreview(
                appearance: value, interface: interface,
                accessibility: accessibility
            )

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
