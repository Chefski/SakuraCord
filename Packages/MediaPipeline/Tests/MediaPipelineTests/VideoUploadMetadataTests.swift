import AVFoundation
import Foundation
import Testing
@testable import MediaPipeline

struct VideoUploadMetadataTests {
    @Test func removesQuickTimeLocationAndPreservesVideoTransform() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("movie.mov")
        try await makeVideo(at: source)
        let original = try Data(contentsOf: source)
        #expect(original.range(of: Data("+50.1234+030.4567/".utf8)) != nil)
        let prepared = try await UploadMetadataRemover.prepare(source)
        defer { prepared.discard() }
        let cleaned = try Data(contentsOf: prepared.url)
        #expect(cleaned.range(of: Data("+50.1234+030.4567/".utf8)) == nil)
        #expect(cleaned.range(of: Data("Secret Camera Owner".utf8)) == nil)
        let before = AVURLAsset(url: source)
        let after = AVURLAsset(url: prepared.url)
        let inputTrack = try #require(await before.loadTracks(withMediaType: .video).first)
        let outputTrack = try #require(await after.loadTracks(withMediaType: .video).first)
        #expect(try await inputTrack.load(.preferredTransform) == outputTrack.load(.preferredTransform))
        #expect(try await before.load(.duration) == after.load(.duration))
        #expect(try Data(contentsOf: source) == original)
    }

    @Test(arguments: [AVFileType.mov, .mp4])
    func preservesAlternateAudioSelection(type: AVFileType) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = directory.appendingPathComponent("video.mov")
        try await makeVideo(at: video)
        let audio = directory.appendingPathComponent("audio.m4a")
        try makeAudio(at: audio)
        let audioAsset = AVURLAsset(url: audio, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let audioTrack = try #require(await audioAsset.loadTracks(withMediaType: .audio).first)
        let movie = AVMutableMovie(url: video, options: nil)
        for index in 0 ..< 2 {
            let track = try #require(movie.addMutableTrack(withMediaType: .audio, copySettingsFrom: audioTrack, options: nil))
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), of: audioTrack, at: .zero, copySampleData: false)
            track.alternateGroupID = 1
            track.languageCode = index == 0 ? "eng" : "fra"
            track.extendedLanguageTag = index == 0 ? "en" : "fr"
            track.isEnabled = index == 0
            track.metadata = movie.metadata
        }
        let source = directory.appendingPathComponent(type == .mov ? "selected.mov" : "selected.mp4")
        let exporter = try #require(AVAssetExportSession(asset: movie, presetName: AVAssetExportPresetPassthrough))
        try await exporter.export(to: source, as: type)
        let original = try Data(contentsOf: source)
        let prepared = try await UploadMetadataRemover.prepare(source)
        defer { prepared.discard() }
        for url in [source, prepared.url] {
            let asset = AVURLAsset(url: url)
            let group = try #require(await asset.loadMediaSelectionGroup(for: .audible))
            #expect(group.options.map(\.extendedLanguageTag) == ["en", "fr"])
            #expect(group.defaultOption?.extendedLanguageTag == "en")
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            #expect(audioTracks.count == 2)
            for (index, track) in audioTracks.enumerated() {
                #expect(try await track.load(.isEnabled) == (index == 0))
                #expect(try await track.load(.languageCode) == (index == 0 ? "eng" : "fra"))
                if url == prepared.url { #expect(try await track.load(.metadata).isEmpty) }
            }
        }
        let cleaned = try Data(contentsOf: prepared.url)
        #expect(cleaned.range(of: Data("Secret Camera Owner".utf8)) == nil)
        #expect(cleaned.range(of: Data("+50.1234+030.4567/".utf8)) == nil)
        #expect(try Data(contentsOf: source) == original)
    }

    private func makeAudio(at url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = buffer.frameCapacity
        let samples = try #require(buffer.floatChannelData?[0])
        samples.update(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1
        ])
        try file.write(from: buffer)
    }

    private func makeVideo(at source: URL) async throws {
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let location = AVMutableMetadataItem()
        location.identifier = .quickTimeMetadataLocationISO6709
        location.value = "+50.1234+030.4567/" as NSString
        let author = AVMutableMetadataItem()
        author.identifier = .quickTimeMetadataAuthor
        author.value = "Secret Camera Owner" as NSString
        writer.metadata = [location, author]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 32])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 128, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        try await receiver.append(CVReadOnlyPixelBuffer(unsafeBuffer: pixels), with: .zero)
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        receiver.finish()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

}
