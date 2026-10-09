@preconcurrency import AVFoundation
import Foundation

/// Plays one Ogg Opus voice message with seeking and pitch-preserving speed.
///
/// AVAudioPlayer cannot prepare Ogg Opus, while AVAudioFile decodes it
/// natively, so playback schedules file segments on an engine instead.
@MainActor
public final class VoiceMessagePlayer {
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying = false
    /// Called once playback reaches the end of the file.
    public var onFinish: (@MainActor () -> Void)?

    public var rate: Float = 1 {
        didSet { timePitch.rate = rate }
    }

    /// Recent output loudness, 0–1, for presentation.
    public var outputLevel: Float { meter.level }

    private let meter = VoiceMessageOutputMeter()
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var file: AVAudioFile?
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var pausedTime: TimeInterval = 0
    /// Distinguishes the current segment's completion from one stopped by a seek.
    private var scheduleGeneration = 0

    public init(fileURL: URL) throws {
        // Time-pitch units reject AVAudioFile's default interleaved mono layout.
        let file = try AVAudioFile(forReading: fileURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
        self.file = file
        duration = Double(file.length) / file.processingFormat.sampleRate
        engine.attach(playerNode)
        engine.attach(timePitch)
        try engine.connectNode(playerNode, to: timePitch, format: file.processingFormat)
        try engine.connectNode(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
        timePitch.installTap(onBus: 0, bufferSize: 1_024, format: nil, block: Self.meteringTap(meter))
        engine.prepare()
    }

    isolated deinit {
        timePitch.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
    }

    public var currentTime: TimeInterval {
        guard isPlaying,
              let file,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return pausedTime }
        let frame = segmentStartFrame + max(0, playerTime.sampleTime)
        return min(duration, Double(frame) / file.processingFormat.sampleRate)
    }

    public func play() throws {
        guard !isPlaying else { return }
        if pausedTime >= duration { pausedTime = 0 }
        if !engine.isRunning { try engine.start() }
        schedule(from: pausedTime)
        try playerNode.playAudio(at: nil)
        isPlaying = true
    }

    public func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        isPlaying = false
        meter.reset()
        scheduleGeneration += 1
        playerNode.stop()
        engine.pause()
    }

    public func seek(to time: TimeInterval) {
        let target = min(max(0, time), duration)
        guard isPlaying else {
            pausedTime = target
            return
        }
        scheduleGeneration += 1
        playerNode.stop()
        schedule(from: target)
        do {
            try playerNode.playAudio(at: nil)
        } catch {
            isPlaying = false
            engine.pause()
        }
    }

    public func stop() {
        pause()
        pausedTime = 0
        engine.stop()
    }

    private func schedule(from time: TimeInterval) {
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let start = min(AVAudioFramePosition(time * sampleRate), max(0, file.length - 1))
        segmentStartFrame = start
        pausedTime = Double(start) / sampleRate
        scheduleGeneration += 1
        let generation = scheduleGeneration
        playerNode.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: AVAudioFrameCount(file.length - start),
            at: nil,
            completionCallbackType: .dataPlayedBack,
            completionHandler: Self.segmentCompletion { [weak self] in
                self?.segmentFinished(generation: generation)
            }
        )
    }

    private func segmentFinished(generation: Int) {
        guard scheduleGeneration == generation, isPlaying else { return }
        isPlaying = false
        pausedTime = duration
        playerNode.stop()
        engine.pause()
        onFinish?()
    }

    // AVFAudio calls these on its own queues. Closures formed inside this
    // main-actor type would inherit its isolation and trap there.
    private nonisolated static func meteringTap(_ meter: VoiceMessageOutputMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in meter.measure(buffer) }
    }

    private nonisolated static func segmentCompletion(
        _ finished: @escaping @MainActor @Sendable () -> Void
    ) -> AVAudioPlayerNodeCompletionHandler {
        { _ in Task { @MainActor in finished() } }
    }
}

private final class VoiceMessageOutputMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    var level: Float { lock.withLock { value } }

    func reset() { lock.withLock { value = 0 } }

    func measure(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var energy: Float = 0
        for index in 0 ..< Int(buffer.frameLength) { energy += samples[index] * samples[index] }
        let rms = (energy / Float(buffer.frameLength)).squareRoot()
        let level = rms > 0 ? min(max((20 * log10(rms) + 50) / 50, 0), 1) : 0
        // Rise quickly and fall gently, like a VU meter.
        lock.withLock { value = level > value ? level : value * 0.6 + level * 0.4 }
    }
}
