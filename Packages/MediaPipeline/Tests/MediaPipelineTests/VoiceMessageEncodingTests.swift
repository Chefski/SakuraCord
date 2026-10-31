import AVFAudio
import Foundation
import Testing
@testable import MediaPipeline

struct VoiceMessageEncodingTests {
    /// Discord accepts Ogg Opus only; Apple's frameworks write Opus solely in
    /// CAF, so the muxer must produce a stream AVAudioFile reads back exactly.
    @Test(arguments: [0.4, 0.99, 2.0, 30.0])
    func recordingRoundTripsThroughOggWithDiscordWaveform(duration: Double) throws {
        let processor = try VoiceMessageCaptureProcessor(spoolURL: Self.spoolURL())
        let sampleCount = Int(duration * OpusCodec.sampleRate)
        // Capture devices deliver 44.1 kHz stereo; the recorder must downmix and resample.
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let inputFrames = Int(duration * 44_100)
        var offset = 0
        while offset < inputFrames {
            let count = min(1_024, inputFrames - offset)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            for channel in 0 ..< 2 {
                for index in 0 ..< count {
                    let time = Float(offset + index) / 44_100
                    // A quiet room, then a tone, so the waveform has shape.
                    let amplitude: Float = time < Float(duration) / 2 ? 0.001 : 0.4
                    buffer.floatChannelData![channel][index] = amplitude * sin(time * 2 * .pi * 330)
                }
            }
            processor.process(buffer)
            offset += count
        }
        let result = try processor.finish()

        #expect(abs(result.duration - duration) < 0.01)
        let expectedBins = min(max(Int(duration * 10), 32), 256)
        #expect(result.waveform.count == min(expectedBins, Int((Double(sampleCount) / 480).rounded(.up))))
        #expect(result.waveform.first == 0)
        // The tone is levelled, so its bins sit at the eased normalization of the target.
        let target = (VoiceMessageLoudness.targetRMS * 255).rounded(.down)
        #expect(Double(result.waveform.max() ?? 0) >= Double(target) * VoiceMessageWaveform.normalizationRatio(maximum: Double(target)) - 2)

        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.data.write(to: url)
        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(abs(Int(file.length) - sampleCount) <= Int(OpusCodec.sampleRate * 0.005))
        #expect(OggPageWalker.pagesAreValid(result.data))
    }

    /// Microphones capture speech far below a comfortable playback level;
    /// the recording is levelled to the target and its peaks never clip.
    @Test(arguments: [Float(0.02), 0.2, 0.9])
    func recordingIsLevelledToSpeechTarget(amplitude: Float) throws {
        let processor = try VoiceMessageCaptureProcessor(spoolURL: Self.spoolURL())
        let format = OpusCodec.pcmFormat(channels: 1)
        let duration = 3.0
        let frames = Int(duration * OpusCodec.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0 ..< frames {
            let time = Float(index) / Float(OpusCodec.sampleRate)
            // Half a second of pause between two phrases.
            let envelope: Float = time > 1.25 && time < 1.75 ? 0 : 1
            buffer.floatChannelData![0][index] = envelope * amplitude * sin(time * 2 * .pi * 220)
        }
        processor.process(buffer)
        let result = try processor.finish()

        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.data.write(to: url)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let decoded = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: decoded)
        let samples = UnsafeBufferPointer(start: decoded.floatChannelData![0], count: Int(decoded.frameLength))
        // The first phrase, clear of the encoder's start-up.
        let phrase = samples[4_800 ..< 57_600]
        let rms = (phrase.reduce(0) { $0 + $1 * $1 } / Float(phrase.count)).squareRoot()
        let input = amplitude / Float(2).squareRoot()
        let gain = min(max(VoiceMessageLoudness.targetRMS / input, VoiceMessageLoudness.minimumGain), VoiceMessageLoudness.maximumGain)
        let expected = input * gain
        #expect(abs(20 * log10(rms / expected)) < 1)
        #expect(samples.allSatisfy { abs($0) <= 1 })
    }

    /// A microphone that is still starting delivers digital silence; the
    /// recording begins with its first sound.
    @Test func recordingSkipsMicrophoneWarmUp() throws {
        let processor = try VoiceMessageCaptureProcessor(spoolURL: Self.spoolURL())
        let format = OpusCodec.pcmFormat(channels: 1)
        let frames = Int(2 * OpusCodec.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0 ..< frames {
            let time = Float(index) / Float(OpusCodec.sampleRate)
            buffer.floatChannelData![0][index] = time < 1.5 ? 0 : 0.2 * sin(time * 2 * .pi * 220)
        }
        processor.process(buffer)
        #expect(abs(processor.elapsed - 0.5) < 0.01)
        let result = try processor.finish()
        #expect(abs(result.duration - 0.5) < 0.01)
    }

    private static func spoolURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pcm")
    }
}

private enum OggPageWalker {
    static func pagesAreValid(_ data: Data) -> Bool {
        var bytes = [UInt8](data)
        var offset = 0
        var previousGranule: UInt64 = 0
        while offset < bytes.count {
            guard offset + 27 <= bytes.count, bytes[offset ..< offset + 4].elementsEqual("OggS".utf8) else { return false }
            let granule = bytes[offset + 6 ..< offset + 14].enumerated().reduce(UInt64(0)) {
                $0 | UInt64($1.element) << (8 * $1.offset)
            }
            guard granule >= previousGranule else { return false }
            previousGranule = granule
            let segments = Int(bytes[offset + 26])
            let bodyLength = bytes[offset + 27 ..< offset + 27 + segments].reduce(0) { $0 + Int($1) }
            let pageLength = 27 + segments + bodyLength
            let stored = bytes[offset + 22 ..< offset + 26].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            for index in offset + 22 ..< offset + 26 { bytes[index] = 0 }
            var crc: UInt32 = 0
            for byte in bytes[offset ..< offset + pageLength] {
                crc ^= UInt32(byte) << 24
                for _ in 0 ..< 8 { crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1 }
            }
            guard crc == stored else { return false }
            offset += pageLength
        }
        return true
    }
}
