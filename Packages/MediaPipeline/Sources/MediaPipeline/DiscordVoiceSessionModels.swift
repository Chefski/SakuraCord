import CoreAudio
import Foundation
import OSLog
import SakuraCordModels

private let voiceMediaLogger = Logger(
    subsystem: "dev.sakuracord.SakuraCord",
    category: "VoiceMedia"
)

public struct VoiceSessionConfiguration: Equatable, Sendable {
    public var inputDeviceID: AudioDeviceID?
    public var outputDeviceID: AudioDeviceID?
    public var inputVolume: Float
    public var outputVolume: Float
    public var isMuted: Bool
    public var isDeafened: Bool
    public var cameraUniqueID: String?

    public init(
        inputDeviceID: AudioDeviceID? = nil,
        outputDeviceID: AudioDeviceID? = nil,
        inputVolume: Float = 1,
        outputVolume: Float = 1,
        isMuted: Bool = false,
        isDeafened: Bool = false,
        cameraUniqueID: String? = nil
    ) {
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.inputVolume = inputVolume
        self.outputVolume = outputVolume
        self.isMuted = isMuted
        self.isDeafened = isDeafened
        self.cameraUniqueID = cameraUniqueID
    }
}

public enum VoiceSessionState: String, Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case disconnected
    case failed
}

public enum VoiceSessionKind: Equatable, Sendable {
    case voice
    case applicationStream(isBroadcaster: Bool)

    var identifyVideoStreamType: String {
        switch self {
        case .voice: "video"
        case .applicationStream: "screen"
        }
    }

    var carriesVoiceAudio: Bool {
        switch self {
        case .voice: true
        case .applicationStream: false
        }
    }
}

public struct VoiceRemoteParticipant: Equatable, Sendable {
    public var userID: String
    public var audioSSRC: UInt32?
    public var videoSSRC: UInt32?
    public var isSpeaking: Bool
    public var isCameraEnabled: Bool
    public var volume: Float

    public init(
        userID: String,
        audioSSRC: UInt32? = nil,
        videoSSRC: UInt32? = nil,
        isSpeaking: Bool = false,
        isCameraEnabled: Bool = false,
        volume: Float = 1
    ) {
        self.userID = userID
        self.audioSSRC = audioSSRC
        self.videoSSRC = videoSSRC
        self.isSpeaking = isSpeaking
        self.isCameraEnabled = isCameraEnabled
        self.volume = volume
    }
}

public enum VoiceSessionEvent: Equatable, Sendable {
    case stateChanged(VoiceSessionState)
    case latencyUpdated(milliseconds: Int)
    case participantChanged(VoiceRemoteParticipant)
    case participantLeft(userID: String)
    case localSpeakingChanged(Bool)
    case encryptionReady(protocolVersion: UInt16)
    case videoFrame(userID: String, frame: VoiceVideoFrame)
    case videoStopped(userID: String)
    case error(String)
}

struct VideoTransportMetrics {
    var sentFrames = 0
    var sentDatagrams = 0
    var maximumFrameSendDuration: Duration = .zero
    var receivedNACKs = 0
    var receivedPLIs = 0
    var requestedRetransmissions = 0
    var sentRetransmissions = 0
    var sentNACKs = 0
    var reportedMissingPackets = 0
    var sentPLIs = 0

    func log() {
        let components = maximumFrameSendDuration.components
        let maximumMilliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1e15
        voiceMediaLogger.info(
            "Video sender stopped; frames=\(sentFrames), datagrams=\(sentDatagrams), maxFrameSendMs=\(maximumMilliseconds, format: .fixed(precision: 3))"
        )
        voiceMediaLogger.info(
            "Video sender feedback stopped; receivedNACKs=\(receivedNACKs), receivedPLIs=\(receivedPLIs), requestedRTX=\(requestedRetransmissions), sentRTX=\(sentRetransmissions)"
        )
        voiceMediaLogger.info(
            "Video receiver feedback stopped; sentNACKs=\(sentNACKs), missingPackets=\(reportedMissingPackets), sentPLIs=\(sentPLIs)"
        )
    }
}
