import CoreAudio
import Foundation
import MediaPipeline
import Observation
import OSLog

private let voiceSettingsLogger = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "VoiceSettings")

@MainActor
protocol VoiceMicrophoneTesting: AnyObject, Sendable {
    var inputVolume: Float { get set }
    var outputVolume: Float { get set }
    var inputLevelHandler: (@Sendable (Float) -> Void)? { get set }

    func startMicrophoneTest(
        inputDeviceID: AudioDeviceID?,
        outputDeviceID: AudioDeviceID?,
        onCapturedFrame: @escaping @Sendable (CapturedOpusFrame) -> Void
    ) throws
    func selectInputDevice(_ deviceID: AudioDeviceID?) async throws
    func selectOutputDevice(_ deviceID: AudioDeviceID?) async throws
    func play(opusPacket: Data, from userID: String) throws
    func stop()
}

extension VoiceAudioEngine: VoiceMicrophoneTesting {}

@MainActor
@Observable
final class VoiceVideoTestController {
    private(set) var microphoneLevel: Float = 0
    private(set) var isMicrophoneTestRunning = false
    private(set) var isMicrophoneTestStarting = false
    private(set) var isMicrophoneRouteChanging = false
    private(set) var isCameraPreviewRunning = false
    private(set) var isCameraPreviewStarting = false
    private(set) var cameraFrame: VoiceVideoFrame?
    private(set) var permissions = VoiceMediaPermissionSnapshot.current()
    var errorMessage: String?

    @ObservationIgnored private let microphoneFactory:
        @MainActor () throws -> any VoiceMicrophoneTesting
    @ObservationIgnored private let microphonePermissionRequester:
        @MainActor () async -> Bool
    @ObservationIgnored private let microphonePlaybackWait:
        @Sendable (ContinuousClock.Instant) async throws -> Bool
    @ObservationIgnored private var preparedMicrophoneEngine: (any VoiceMicrophoneTesting)?
    @ObservationIgnored private var microphoneEngine: (any VoiceMicrophoneTesting)?
    @ObservationIgnored private var microphoneGeneration = UUID()
    @ObservationIgnored private var microphoneInputDeviceID: AudioDeviceID?
    @ObservationIgnored private var microphoneOutputDeviceID: AudioDeviceID?
    @ObservationIgnored private var microphoneLevelTask: Task<Void, Never>?
    @ObservationIgnored private var microphonePlaybackTask: Task<Void, Never>?
    @ObservationIgnored private var microphoneLevelContinuation: AsyncStream<Float>.Continuation?
    @ObservationIgnored private var microphoneFrameContinuation: AsyncStream<MicrophoneTestFrame>.Continuation?

    private struct MicrophoneTestFrame: Sendable {
        let packet: Data
        let capturedAt: ContinuousClock.Instant
    }
    @ObservationIgnored private var cameraGeneration = UUID()
    @ObservationIgnored private var cameraEngine: CameraPreviewEngine?
    @ObservationIgnored private var cameraFrameTask: Task<Void, Never>?

    init(
        microphoneFactory: @escaping @MainActor () throws -> any VoiceMicrophoneTesting = {
            try VoiceAudioEngine()
        },
        microphonePermissionRequester: @escaping @MainActor () async -> Bool = {
            await VoiceAudioEngine.requestMicrophonePermission()
        },
        microphonePlaybackWait: @escaping @Sendable (ContinuousClock.Instant) async throws -> Bool = { capturedAt in
            try await ContinuousClock().sleep(until: capturedAt.advanced(by: .milliseconds(200)))
            // Drop stale audio after a UI stall instead of building up an audible backlog.
            return capturedAt.duration(to: .now) < .milliseconds(500)
        }
    ) {
        self.microphoneFactory = microphoneFactory
        self.microphonePermissionRequester = microphonePermissionRequester
        self.microphonePlaybackWait = microphonePlaybackWait
    }

    func refreshPermissions() {
        permissions = VoiceMediaPermissionSnapshot.current()
    }

    func prepareMicrophoneTest() {
        guard preparedMicrophoneEngine == nil else { return }
        // Allocate codecs and inactive graph objects only. Device capture starts on click.
        preparedMicrophoneEngine = try? microphoneFactory()
    }

    func startMicrophoneTest(
        inputDeviceID: AudioDeviceID?,
        outputDeviceID: AudioDeviceID?,
        inputVolume: Float,
        outputVolume: Float
    ) async {
        let requestedAt = ContinuousClock.now
        stopMicrophoneTest()
        let generation = microphoneGeneration
        microphoneInputDeviceID = inputDeviceID
        microphoneOutputDeviceID = outputDeviceID
        isMicrophoneTestStarting = true
        let allowed = await microphonePermissionRequester()
        guard generation == microphoneGeneration else { return }
        guard !Task.isCancelled else {
            stopMicrophoneTest()
            return
        }
        isMicrophoneTestStarting = false
        guard allowed else {
            refreshPermissions()
            errorMessage = "Microphone access is required to run the microphone test."
            return
        }
        permissions.microphone = .authorized
        do {
            let engine = try preparedMicrophoneEngine ?? microphoneFactory()
            preparedMicrophoneEngine = engine
            microphoneEngine = engine
            engine.inputVolume = inputVolume
            engine.outputVolume = outputVolume
            let levels = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
            // At 20 ms per Opus frame this bounds queued audio to 320 ms.
            let frames = AsyncStream<MicrophoneTestFrame>.makeStream(bufferingPolicy: .bufferingNewest(16))
            microphoneLevelContinuation = levels.continuation
            microphoneFrameContinuation = frames.continuation
            engine.inputLevelHandler = { level in levels.continuation.yield(level) }
            try engine.startMicrophoneTest(
                inputDeviceID: microphoneInputDeviceID,
                outputDeviceID: microphoneOutputDeviceID,
                onCapturedFrame: { frame in
                    frames.continuation.yield(MicrophoneTestFrame(packet: frame.data, capturedAt: .now))
                }
            )
            isMicrophoneTestRunning = true
            errorMessage = nil
            microphoneLevelTask = Task { @MainActor [weak self] in
                var receivedFirstLevel = false
                for await level in levels.stream {
                    guard let self, !Task.isCancelled,
                          self.microphoneGeneration == generation else { return }
                    self.microphoneLevel = level
                    if !receivedFirstLevel {
                        receivedFirstLevel = true
                        voiceSettingsLogger.info(
                            "Microphone test received its first level after \(String(describing: requestedAt.duration(to: .now)), privacy: .public)"
                        )
                    }
                }
            }
            let waitForPlayback = microphonePlaybackWait
            microphonePlaybackTask = Task { @MainActor [weak self] in
                do {
                    for await frame in frames.stream {
                        let isCurrent = try await waitForPlayback(frame.capturedAt)
                        guard let self, !Task.isCancelled,
                              self.microphoneGeneration == generation else { return }
                        guard isCurrent else { continue }
                        try self.microphoneEngine?.play(opusPacket: frame.packet, from: "microphone-test")
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, self.microphoneGeneration == generation else { return }
                    self.stopMicrophoneTest()
                    self.errorMessage = error.localizedDescription
                }
            }
        } catch {
            stopMicrophoneTest()
            preparedMicrophoneEngine = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectMicrophoneTestInput(_ deviceID: AudioDeviceID?) async -> Bool {
        let generation = microphoneGeneration
        let changed = await changeMicrophoneTestRoute { engine in
            try await engine.selectInputDevice(deviceID)
        }
        if changed, generation == microphoneGeneration {
            microphoneInputDeviceID = deviceID
        }
        return changed
    }

    func selectMicrophoneTestOutput(_ deviceID: AudioDeviceID?) async -> Bool {
        let generation = microphoneGeneration
        let changed = await changeMicrophoneTestRoute { engine in
            try await engine.selectOutputDevice(deviceID)
        }
        if changed, generation == microphoneGeneration {
            microphoneOutputDeviceID = deviceID
        }
        return changed
    }

    private func changeMicrophoneTestRoute(
        _ change: (any VoiceMicrophoneTesting) async throws -> Void
    ) async -> Bool {
        guard let engine = microphoneEngine else { return true }
        guard !isMicrophoneRouteChanging else { return false }
        let generation = microphoneGeneration
        isMicrophoneRouteChanging = true
        defer {
            if generation == microphoneGeneration {
                isMicrophoneRouteChanging = false
            }
        }
        do {
            try await change(engine)
            guard generation == microphoneGeneration else { return false }
            errorMessage = nil
            return true
        } catch {
            guard generation == microphoneGeneration else { return false }
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func updateTestVolumes(input: Float, output: Float) {
        microphoneEngine?.inputVolume = input
        microphoneEngine?.outputVolume = output
    }

    func stopMicrophoneTest() {
        microphoneGeneration = UUID()
        isMicrophoneRouteChanging = false
        microphoneLevelTask?.cancel()
        microphonePlaybackTask?.cancel()
        microphoneLevelTask = nil
        microphonePlaybackTask = nil
        microphoneLevelContinuation?.finish()
        microphoneFrameContinuation?.finish()
        microphoneLevelContinuation = nil
        microphoneFrameContinuation = nil
        microphoneEngine?.inputLevelHandler = nil
        microphoneEngine?.stop()
        microphoneEngine = nil
        microphoneLevel = 0
        isMicrophoneTestRunning = false
        isMicrophoneTestStarting = false
    }

    func startCameraPreview(cameraUniqueID: String?) async {
        stopCameraPreview()
        let generation = cameraGeneration
        isCameraPreviewStarting = true
        let allowed = await VoiceVideoEngine.requestCameraPermission()
        guard generation == cameraGeneration else { return }
        guard !Task.isCancelled else {
            stopCameraPreview()
            return
        }
        isCameraPreviewStarting = false
        guard allowed else {
            refreshPermissions()
            errorMessage = "Camera access is required to show a preview."
            return
        }
        refreshPermissions()
        do {
            let engine = CameraPreviewEngine()
            try engine.start(cameraUniqueID: cameraUniqueID)
            cameraEngine = engine
            isCameraPreviewRunning = true
            cameraFrameTask = Task { @MainActor [weak self, engine] in
                for await frame in engine.frames {
                    guard let self,
                          !Task.isCancelled,
                          self.cameraEngine === engine
                    else { return }
                    self.cameraFrame = frame
                }
            }
            errorMessage = nil
        } catch {
            cameraEngine = nil
            isCameraPreviewRunning = false
            errorMessage = error.localizedDescription
        }
    }

    func stopCameraPreview() {
        cameraGeneration = UUID()
        isCameraPreviewStarting = false
        cameraFrameTask?.cancel()
        cameraFrameTask = nil
        cameraEngine?.stop()
        cameraEngine = nil
        cameraFrame = nil
        isCameraPreviewRunning = false
    }

    func stopAll() {
        stopMicrophoneTest()
        preparedMicrophoneEngine = nil
        stopCameraPreview()
    }
}
