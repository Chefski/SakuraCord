import AppKit
import CoreAudio
import MediaPipeline
import SwiftUI

struct VoiceVideoSettingsPage: View {
    let model: AppModel
    let state: SettingsViewState

    @State private var tests = VoiceVideoTestController()
    @State private var showsResetConfirmation = false
    @State private var operationMessage: String?

    var body: some View {
        SettingsPageForm(page: .voiceVideo, state: state) {
            VoiceDevicesSettingsSection(
                model: model,
                tests: tests,
                state: state,
                refresh: refreshDevices
            )
            VoiceLevelsSettingsSection(model: model, tests: tests, state: state)
            VoiceCallDefaultsSettingsSection(
                preferences: model.voiceVideoPreferences,
                state: state
            )
            VoiceCameraSettingsSection(model: model, tests: tests, state: state)
            ScreenShareDefaultsSettingsSection(
                preferences: model.voiceVideoPreferences,
                state: state
            )
            VoicePermissionsSettingsSection(
                permissions: tests.permissions,
                state: state,
                openSystemSettings: openPrivacySettings
            )
            Section {
                Button("Reset Voice & Video Settings…", role: .destructive) {
                    showsResetConfirmation = true
                }
                .settingsControlAnchor(.voiceReset, state: state)
            } header: {
                Text("Reset", bundle: #bundle)
            }
        }
        .task {
            await model.refreshMediaDevices()
            tests.refreshPermissions()
        }
        .onDisappear { tests.stopAll() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            tests.refreshPermissions()
        }
        .onChange(of: model.activeVoiceChannel?.id) {
            if model.activeVoiceChannel != nil {
                tests.stopAll()
            }
        }
        .settingsResetConfirmation(
            "Reset Voice & Video Settings?",
            isPresented: $showsResetConfirmation,
            resetTitle: "Reset Voice & Video Settings",
            message: """
            This restores SakuraCord’s app-wide call and screen-share defaults. \
            It does not change macOS permissions, Discord settings, or mute, \
            deafen, camera, and sharing state in the current call.
            """,
            reset: resetPreferences
        )
        .alert(
            "Voice & Video",
            isPresented: Binding(
                get: { operationMessage != nil || tests.errorMessage != nil },
                set: {
                    if !$0 {
                        operationMessage = nil
                        tests.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                operationMessage = nil
                tests.errorMessage = nil
            }
        } message: {
            Text(operationMessage ?? tests.errorMessage ?? "")
        }
    }

    private func refreshDevices() {
        tests.stopAll()
        Task { await model.refreshMediaDevices() }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security"),
              NSWorkspace.shared.open(url)
        else {
            operationMessage = "System Settings could not be opened. Open Privacy & Security in System Settings manually."
            return
        }
    }

    private func resetPreferences() {
        tests.stopAll()
        SettingsPreferenceStore.shared.reset(scope: .appWide, page: .voiceVideo)
        model.voiceVideoPreferences.reload()
        Task {
            _ = await model.selectInputDevice(nil)
            _ = await model.selectOutputDevice(nil)
            _ = await model.selectCamera(nil)
            await model.updateInputVolume(1)
            await model.updateOutputVolume(1)
            operationMessage = "Restored Voice & Video settings to their defaults. Current mute, deafen, camera, and sharing state were left unchanged."
        }
    }
}

private struct VoiceDevicesSettingsSection: View {
    let model: AppModel
    let tests: VoiceVideoTestController
    let state: SettingsViewState
    let refresh: () -> Void

    var body: some View {
        Section {
            Picker("Input device", selection: inputSelection) {
                Text(systemDefaultAudioDeviceLabel(model.mediaDevices.audioInputs)).tag("")
                ForEach(model.mediaDevices.audioInputs) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .settingsControlAnchor(.voiceInputDevice, state: state)

            Picker("Output device", selection: outputSelection) {
                Text(systemDefaultAudioDeviceLabel(model.mediaDevices.audioOutputs)).tag("")
                ForEach(model.mediaDevices.audioOutputs) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .settingsControlAnchor(.voiceOutputDevice, state: state)

            Picker("Camera", selection: cameraSelection) {
                Text(systemDefaultCameraLabel(model.mediaDevices.cameras)).tag("")
                ForEach(model.mediaDevices.cameras) { camera in
                    Text(camera.name).tag(camera.uniqueID)
                }
            }
            .settingsControlAnchor(.voiceCamera, state: state)

            LabeledContent("Devices") {
                Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
            }
            .settingsControlAnchor(.voiceRefreshDevices, state: state)

            if let statusMessage = model.voiceDeviceStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Devices", bundle: #bundle)
        } footer: {
            Text("System Default follows your Mac’s selected device.")
        }
    }

    private var inputSelection: Binding<String> {
        Binding(
            get: { model.voiceVideoPreferences.inputDeviceUID },
            set: { uid in
                tests.stopMicrophoneTest()
                let device = model.mediaDevices.audioInputs.first { $0.uid == uid }
                Task {
                    if !(await model.selectInputDevice(device)) {
                        tests.errorMessage = model.voiceErrorMessage
                    }
                }
            }
        )
    }

    private var outputSelection: Binding<String> {
        Binding(
            get: { model.voiceVideoPreferences.outputDeviceUID },
            set: { uid in
                tests.stopMicrophoneTest()
                tests.stopSpeakerTest()
                let device = model.mediaDevices.audioOutputs.first { $0.uid == uid }
                Task {
                    if !(await model.selectOutputDevice(device)) {
                        tests.errorMessage = model.voiceErrorMessage
                    }
                }
            }
        )
    }

    private var cameraSelection: Binding<String> {
        Binding(
            get: { model.selectedCameraUID ?? "" },
            set: { uid in
                tests.stopCameraPreview()
                let camera = model.mediaDevices.cameras.first { $0.uniqueID == uid }
                Task {
                    if !(await model.selectCamera(camera)) {
                        tests.errorMessage = model.voiceErrorMessage
                    }
                }
            }
        )
    }
}

private struct VoiceLevelsSettingsSection: View {
    let model: AppModel
    let tests: VoiceVideoTestController
    let state: SettingsViewState

    var body: some View {
        Section {
            LabeledContent("Input volume") {
                Slider(value: inputVolume, in: 0 ... 2)
                    .tint(SakuraCordAccentColor.color)
                Text("\(Int(model.voiceVideoPreferences.inputVolume * 100))%")
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            .settingsControlAnchor(.voiceInputVolume, state: state)

            LabeledContent("Microphone level") {
                ProgressView(value: Double(tests.microphoneLevel))
                    .tint(SakuraCordAccentColor.color)
                    .frame(width: 160)
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue("\(Int(tests.microphoneLevel * 100)) percent")
                Button(tests.isMicrophoneTestRunning ? "Stop Test" : "Test Microphone") {
                    toggleMicrophoneTest()
                }
                .disabled(isCallActive)
            }
            .settingsControlAnchor(.voiceMicrophoneTest, state: state)

            LabeledContent("Output volume") {
                Slider(value: outputVolume, in: 0 ... 2)
                    .tint(SakuraCordAccentColor.color)
                Text("\(Int(model.voiceVideoPreferences.outputVolume * 100))%")
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
            .settingsControlAnchor(.voiceOutputVolume, state: state)

            LabeledContent("Speaker") {
                Button(tests.isSpeakerTestRunning ? "Stop Test" : "Test Speaker") {
                    toggleSpeakerTest()
                }
                .disabled(isCallActive)
            }
            .settingsControlAnchor(.voiceSpeakerTest, state: state)
        } header: {
            Text("Audio", bundle: #bundle)
        } footer: {
            if isCallActive {
                Text("Device tests are unavailable during a call so they cannot interfere with live audio.")
            } else {
                Text("Tests stop when you leave this page. Microphone audio is not recorded.")
            }
        }
    }

    private var isCallActive: Bool { model.activeVoiceChannel != nil }

    private var inputVolume: Binding<Double> {
        Binding(
            get: { model.voiceVideoPreferences.inputVolume },
            set: { value in Task { await model.updateInputVolume(Float(value)) } }
        )
    }

    private var outputVolume: Binding<Double> {
        Binding(
            get: { model.voiceVideoPreferences.outputVolume },
            set: { value in Task { await model.updateOutputVolume(Float(value)) } }
        )
    }

    private func toggleMicrophoneTest() {
        if tests.isMicrophoneTestRunning {
            tests.stopMicrophoneTest()
            return
        }
        tests.stopSpeakerTest()
        let inputID = selectedInputDeviceID(model)
        let outputID = selectedOutputDeviceID(model)
        Task {
            await tests.startMicrophoneTest(
                inputDeviceID: inputID,
                outputDeviceID: outputID,
                inputVolume: Float(model.voiceVideoPreferences.inputVolume)
            )
        }
    }

    private func toggleSpeakerTest() {
        if tests.isSpeakerTestRunning {
            tests.stopSpeakerTest()
            return
        }
        tests.stopMicrophoneTest()
        tests.startSpeakerTest(
            outputDeviceID: selectedOutputDeviceID(model),
            outputVolume: Float(model.voiceVideoPreferences.outputVolume)
        )
    }
}

private struct VoiceCallDefaultsSettingsSection: View {
    let preferences: VoiceVideoPreferences
    let state: SettingsViewState

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Group {
                Toggle("Join calls muted", isOn: $preferences.joinsMuted)
                    .settingsControlAnchor(.voiceJoinMuted, state: state)
                Toggle("Join calls deafened", isOn: $preferences.joinsDeafened)
                    .settingsControlAnchor(.voiceJoinDeafened, state: state)
                Toggle("Play call feedback sounds", isOn: $preferences.playsFeedbackSounds)
                    .settingsControlAnchor(.voiceFeedbackSounds, state: state)
            }
            .tint(SakuraCordAccentColor.color)
        } header: {
            Text("Calls", bundle: #bundle)
        } footer: {
            Text("Join settings apply to your next call.")
        }
    }
}

private struct VoiceCameraSettingsSection: View {
    let model: AppModel
    let tests: VoiceVideoTestController
    let state: SettingsViewState

    var body: some View {
        @Bindable var preferences = model.voiceVideoPreferences
        Section {
            if let frame = tests.cameraFrame {
                Image(decorative: frame.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: preferences.mirrorsLocalPreview ? -1 : 1, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityLabel("Live camera preview")
            }

            LabeledContent("Preview") {
                Button(tests.isCameraPreviewRunning ? "Stop Preview" : "Start Preview") {
                    togglePreview()
                }
                .disabled(model.activeVoiceChannel != nil)
            }
            .settingsControlAnchor(.voiceCameraPreview, state: state)

            Group {
                Toggle("Mirror my local preview", isOn: $preferences.mirrorsLocalPreview)
                    .settingsControlAnchor(.voiceMirrorPreview, state: state)
                Toggle("Remember selected camera", isOn: rememberCamera)
                    .settingsControlAnchor(.voiceRememberCamera, state: state)
                Toggle("Join calls with camera off", isOn: $preferences.joinsWithCameraOff)
                    .settingsControlAnchor(.voiceJoinCameraOff, state: state)
            }
            .tint(SakuraCordAccentColor.color)
        } header: {
            Text("Camera", bundle: #bundle)
        } footer: {
            Text("Mirroring changes only your preview. Camera tests are available when you’re not in a call.")
        }
    }

    private var rememberCamera: Binding<Bool> {
        Binding(
            get: { model.voiceVideoPreferences.remembersCamera },
            set: { model.updateCameraPersistence($0) }
        )
    }

    private func togglePreview() {
        if tests.isCameraPreviewRunning {
            tests.stopCameraPreview()
        } else {
            Task { await tests.startCameraPreview(cameraUniqueID: model.selectedCameraUID) }
        }
    }
}

private struct ScreenShareDefaultsSettingsSection: View {
    let preferences: VoiceVideoPreferences
    let state: SettingsViewState

    var body: some View {
        @Bindable var preferences = preferences
        Section {
            Picker("Quality", selection: $preferences.screenShareQuality) {
                ForEach(ScreenShareQuality.allCases, id: \.self) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .settingsControlAnchor(.voiceScreenShareQuality, state: state)

            Picker("Frame rate", selection: $preferences.screenShareFrameRate) {
                ForEach(ScreenShareFrameRate.allCases, id: \.self) { rate in
                    Text(rate.title).tag(rate)
                }
            }
            .settingsControlAnchor(.voiceScreenShareFrameRate, state: state)

            Toggle("Include system audio", isOn: $preferences.screenShareIncludesAudio)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.voiceScreenShareAudio, state: state)
            Toggle("Show pointer", isOn: $preferences.screenShareShowsPointer)
                .tint(SakuraCordAccentColor.color)
                .settingsControlAnchor(.voiceScreenSharePointer, state: state)
        } header: {
            Text("Screen Sharing", bundle: #bundle)
        } footer: {
            Text("Defaults for your next screen share. You can also adjust them in the share preview.")
        }
    }
}

private struct VoicePermissionsSettingsSection: View {
    let permissions: VoiceMediaPermissionSnapshot
    let state: SettingsViewState
    let openSystemSettings: () -> Void

    var body: some View {
        Section {
            LabeledContent("Microphone") {
                Text(permissionTitle(permissions.microphone))
                    .foregroundStyle(.secondary)
            }
            .settingsControlAnchor(.voiceMicrophonePermission, state: state)

            LabeledContent("Camera") {
                Text(permissionTitle(permissions.camera))
                    .foregroundStyle(.secondary)
            }
            .settingsControlAnchor(.voiceCameraPermission, state: state)

            LabeledContent("Privacy & Security") {
                Button("Open System Settings…", action: openSystemSettings)
            }
        } header: {
            Text("Permissions", bundle: #bundle)
        } footer: {
            Text("Screen sharing asks you to choose a window or display using the macOS picker.")
        }
    }
}

private func selectedInputDeviceID(_ model: AppModel) -> AudioDeviceID? {
    let uid = model.voiceVideoPreferences.inputDeviceUID
    return model.mediaDevices.audioInputs.first { $0.uid == uid }?.id
}

private func selectedOutputDeviceID(_ model: AppModel) -> AudioDeviceID? {
    let uid = model.voiceVideoPreferences.outputDeviceUID
    return model.mediaDevices.audioOutputs.first { $0.uid == uid }?.id
}

private func systemDefaultAudioDeviceLabel(_ devices: [AudioDeviceInfo]) -> String {
    guard let device = devices.first(where: \.isDefault) else { return "System Default" }
    return "System Default (\(device.name))"
}

private func systemDefaultCameraLabel(_ cameras: [CameraDeviceInfo]) -> String {
    cameras.first(where: \.isDefault)
        .map { "System Default (\($0.name))" } ?? "System Default"
}

private func permissionTitle(_ authorization: VoiceMediaAuthorization) -> String {
    switch authorization {
    case .authorized: "Allowed"
    case .denied: "Denied"
    case .restricted: "Restricted"
    case .notDetermined: "Not requested"
    }
}
