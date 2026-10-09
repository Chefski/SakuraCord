@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import OSLog
import SakuraCordModels

private let voiceMessageLogger = Logger(subsystem: "dev.sakuracord.SakuraCord", category: "VoiceMessage")

/// A finished voice message ready to upload as Discord's `voice-message.ogg`.
public struct VoiceMessageRecording: Equatable, Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    /// Discord's 0–255 waveform bins.
    public let waveform: [UInt8]

    public init(fileURL: URL, duration: TimeInterval, waveform: [UInt8]) {
        self.fileURL = fileURL
        self.duration = duration
        self.waveform = waveform
    }

    public var metadata: VoiceMessageMetadata {
        VoiceMessageMetadata(durationSeconds: duration, waveform: VoiceMessageWaveform.encode(waveform))
    }

    /// Removes the recording's private directory.
    public func discard() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
}

public enum VoiceMessageRecorderError: Error, Equatable {
    case microphonePermissionDenied
    case inputUnavailable
    case encoderUnavailable
    case notRecording
}

extension VoiceMessageRecorderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "SakuraCord needs microphone access to record voice messages. You can allow it in System Settings → Privacy & Security → Microphone."
        case .inputUnavailable:
            "The selected microphone is not available."
        case .encoderUnavailable:
            "Voice messages can't be encoded on this Mac."
        case .notRecording:
            "No voice message is being recorded."
        }
    }
}

/// Records the microphone into an Ogg Opus voice message.
///
/// Capture uses AVCaptureSession for the same reason as calls: opening a
/// Bluetooth headset through AVAudioEngine's input node can switch the
/// headset's transport for the entire Mac.
@MainActor
public final class VoiceMessageRecorder {
    /// Discord's documented voice-message limit.
    public nonisolated static let maximumDuration: TimeInterval = 20 * 60
    /// Seconds of audio represented by one bar of the live waveform.
    public nonisolated static let liveBarInterval: TimeInterval = 0.1

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.sakuracord.voice-message.capture", qos: .userInitiated)
    private var processor: VoiceMessageCaptureProcessor?

    public init() {}

    public var isRecording: Bool { processor != nil }

    public static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    public func start(inputDeviceID: AudioDeviceID? = nil) throws {
        cancel()
        let device = MediaDeviceCatalog.audioCaptureDevice(deviceID: inputDeviceID)
            ?? MediaDeviceCatalog.audioCaptureDevice(deviceID: nil)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            throw VoiceMessageRecorderError.inputUnavailable
        }
        let processor = try VoiceMessageCaptureProcessor()
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(processor, queue: queue)
        try queue.sync { [session] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                throw VoiceMessageRecorderError.inputUnavailable
            }
            session.addInput(input)
            session.addOutput(output)
        }
        self.processor = processor
        queue.async { [session] in session.startRunning() }
        voiceMessageLogger.info("Voice message recording started")
    }

    /// Captured duration so far.
    public var elapsed: TimeInterval { processor?.elapsed ?? 0 }

    public var hasReachedMaximumDuration: Bool { elapsed >= Self.maximumDuration }

    /// Live waveform bars completed since the previous call, each the peak
    /// level over `liveBarInterval`, plus the level of the bar in progress.
    public func drainLevels() -> (completed: [Float], current: Float) {
        processor?.drainLevels() ?? ([], 0)
    }

    public func stop() async throws -> VoiceMessageRecording {
        guard let processor else { throw VoiceMessageRecorderError.notRecording }
        self.processor = nil
        await stopSession()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SakuraCordVoiceMessages", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: VoiceMessageMetadata.filename)
        let recording = try await Task.detached(priority: .userInitiated) {
            let result = processor.finish()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try result.data.write(to: fileURL, options: .atomic)
            return VoiceMessageRecording(fileURL: fileURL, duration: result.duration, waveform: result.waveform)
        }.value
        voiceMessageLogger.info("Voice message recording finished duration=\(recording.duration, format: .fixed(precision: 2))")
        return recording
    }

    public func cancel() {
        guard processor != nil else { return }
        processor = nil
        Task { await stopSession() }
    }

    private func stopSession() async {
        await withCheckedContinuation { continuation in
            queue.async { [session] in
                session.stopRunning()
                session.outputs.forEach { ($0 as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil) }
                continuation.resume()
            }
        }
    }
}

final class VoiceMessageCaptureProcessor: NSObject,
    AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    static let preSkip: UInt16 = 312
    static let samplesPerBar = Int(VoiceMessageRecorder.liveBarInterval * OpusCodec.sampleRate)

    private let lock = NSLock()
    private let codec: OpusCodec
    private var converter: AVAudioConverter?
    private var writer = OggOpusWriter(channelCount: 1, preSkip: preSkip)
    private var accumulator = VoiceMessageWaveform.Accumulator()
    private var pending: [Float] = []
    private var capturedSamples = 0
    private var completedBars: [Float] = []
    private var barPeak: Float = 0
    private var barSamples = 0
    private var isFinished = false

    init(bitRate: Int = 32_000) throws {
        do {
            codec = try OpusCodec(bitRate: bitRate, channels: 1)
        } catch {
            throw VoiceMessageRecorderError.encoderUnavailable
        }
        super.init()
    }

    var elapsed: TimeInterval {
        lock.withLock { Double(capturedSamples) / OpusCodec.sampleRate }
    }

    func drainLevels() -> (completed: [Float], current: Float) {
        lock.withLock {
            defer { completedBars.removeAll(keepingCapacity: true) }
            return (completedBars, barPeak)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = AVAudioFormat(formatDescription: description)
        else { return }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }
        buffer.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList
        ) == noErr else { return }
        process(buffer)
    }

    func process(_ input: AVAudioPCMBuffer) {
        lock.withLock {
            guard !isFinished,
                  Double(capturedSamples) / OpusCodec.sampleRate < VoiceMessageRecorder.maximumDuration,
                  let converted = convert(input),
                  let samples = converted.floatChannelData?[0]
            else { return }
            let count = Int(converted.frameLength)
            let buffer = UnsafeBufferPointer(start: samples, count: count)
            accumulator.append(buffer)
            pending.append(contentsOf: buffer)
            capturedSamples += count
            updateLevels(buffer)
            encodePendingFrames()
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: codec.pcmFormat)
            converter?.downmix = true
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * OpusCodec.sampleRate / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: codec.pcmFormat, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            guard !supplied else {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private func updateLevels(_ samples: UnsafeBufferPointer<Float>) {
        var offset = 0
        while offset < samples.count {
            let take = min(samples.count - offset, Self.samplesPerBar - barSamples)
            var energy: Float = 0
            for sample in samples[offset ..< offset + take] { energy += sample * sample }
            let level = Self.normalizedLevel(rms: (energy / Float(max(take, 1))).squareRoot())
            barPeak = max(barPeak, level)
            barSamples += take
            offset += take
            if barSamples == Self.samplesPerBar {
                completedBars.append(barPeak)
                barPeak = 0
                barSamples = 0
            }
        }
    }

    /// A perceptual 0–1 level over a 60 dB range, so a quiet room still moves.
    static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(max((20 * log10(rms) + 60) / 60, 0), 1)
    }

    private func encodePendingFrames() {
        let frame = Int(OpusCodec.frameSamples)
        var offset = 0
        while pending.count - offset >= frame {
            encode(pending[offset ..< offset + frame])
            offset += frame
        }
        pending.removeFirst(offset)
    }

    private func encode(_ samples: ArraySlice<Float>) {
        guard let pcm = AVAudioPCMBuffer(pcmFormat: codec.pcmFormat, frameCapacity: OpusCodec.frameSamples),
              let channel = pcm.floatChannelData?[0]
        else { return }
        pcm.frameLength = OpusCodec.frameSamples
        for (index, sample) in samples.enumerated() { channel[index] = sample }
        for index in samples.count ..< Int(OpusCodec.frameSamples) { channel[index] = 0 }
        do {
            writer.append(packet: try codec.encode(pcm), samples: Int(OpusCodec.frameSamples))
        } catch {
            voiceMessageLogger.error("Voice message frame encoding failed")
        }
    }

    struct Result {
        let data: Data
        let duration: TimeInterval
        let waveform: [UInt8]
    }

    func finish() -> Result {
        lock.withLock {
            isFinished = true
            // Pad the final partial frame, then push the encoder's delay out.
            if !pending.isEmpty { encode(pending[...]) }
            pending.removeAll()
            encode([])
            let data = writer.finish(sampleCount: capturedSamples)
            return Result(
                data: data,
                duration: Double(capturedSamples) / OpusCodec.sampleRate,
                waveform: VoiceMessageWaveform.bins(from: accumulator)
            )
        }
    }
}
