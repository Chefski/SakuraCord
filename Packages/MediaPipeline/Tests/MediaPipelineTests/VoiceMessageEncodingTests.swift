import AVFAudio
import Foundation
import Testing
@testable import MediaPipeline

struct VoiceMessageEncodingTests {
    /// Discord accepts Ogg Opus only; Apple's frameworks write Opus solely in
    /// CAF, so the muxer must produce a stream AVAudioFile reads back exactly.
    @Test(arguments: [0.4, 2.0, 30.0])
    func recordingRoundTripsThroughOggWithDiscordWaveform(duration: Double) throws {
        let processor = try VoiceMessageCaptureProcessor()
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
                    // Silence, then a tone, so the waveform has shape.
                    buffer.floatChannelData![channel][index] = time < Float(duration) / 2 ? 0 : 0.4 * sin(time * 2 * .pi * 330)
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
        #expect(result.waveform.max() ?? 0 >= 254)

        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.data.write(to: url)
        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(abs(Int(file.length) - sampleCount) <= Int(OpusCodec.sampleRate * 0.005))
        #expect(OggPageWalker.checksumsAreValid(result.data))
    }
}

private enum OggPageWalker {
    static func checksumsAreValid(_ data: Data) -> Bool {
        var bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            guard offset + 27 <= bytes.count, bytes[offset ..< offset + 4].elementsEqual("OggS".utf8) else { return false }
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
