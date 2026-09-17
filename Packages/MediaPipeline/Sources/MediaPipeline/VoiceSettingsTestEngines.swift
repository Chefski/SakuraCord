@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

public enum VoiceMediaAuthorization: String, Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .restricted
        }
    }
}

public struct VoiceMediaPermissionSnapshot: Equatable, Sendable {
    public var microphone: VoiceMediaAuthorization
    public var camera: VoiceMediaAuthorization
    public var screenRecordingAllowed: Bool

    public init(
        microphone: VoiceMediaAuthorization,
        camera: VoiceMediaAuthorization,
        screenRecordingAllowed: Bool
    ) {
        self.microphone = microphone
        self.camera = camera
        self.screenRecordingAllowed = screenRecordingAllowed
    }

    public static func current() -> Self {
        Self(
            microphone: VoiceMediaAuthorization(
                AVCaptureDevice.authorizationStatus(for: .audio)
            ),
            camera: VoiceMediaAuthorization(
                AVCaptureDevice.authorizationStatus(for: .video)
            ),
            screenRecordingAllowed: CGPreflightScreenCaptureAccess()
        )
    }
}

public final class CameraPreviewEngine: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    public let frames: AsyncStream<VoiceVideoFrame>

    private let frameContinuation: AsyncStream<VoiceVideoFrame>.Continuation
    private let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(
        label: "app.sakuracord.settings.camera-preview",
        qos: .userInteractive
    )
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var lastPreviewTime = CFAbsoluteTimeGetCurrent()

    override public init() {
        let stream = AsyncStream<VoiceVideoFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        frames = stream.stream
        frameContinuation = stream.continuation
        super.init()
    }

    deinit {
        frameContinuation.finish()
    }

    public func start(cameraUniqueID: String?) throws {
        guard let camera = MediaDeviceCatalog.camera(uniqueID: cameraUniqueID) else {
            throw VoiceVideoError.cameraUnavailable
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            throw VoiceVideoError.cameraInputUnavailable
        }
        try captureQueue.sync { [captureSession] in
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }
            for existing in captureSession.inputs {
                captureSession.removeInput(existing)
            }
            for existing in captureSession.outputs {
                captureSession.removeOutput(existing)
            }
            guard captureSession.canAddInput(input) else {
                throw VoiceVideoError.cameraInputUnavailable
            }
            captureSession.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            ]
            output.setSampleBufferDelegate(self, queue: captureQueue)
            guard captureSession.canAddOutput(output) else {
                throw VoiceVideoError.cameraUnavailable
            }
            captureSession.addOutput(output)
        }
        captureQueue.async { [captureSession] in
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
    }

    public func stop() {
        captureQueue.sync { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            captureSession.beginConfiguration()
            for input in captureSession.inputs {
                captureSession.removeInput(input)
            }
            for output in captureSession.outputs {
                if let videoOutput = output as? AVCaptureVideoDataOutput {
                    videoOutput.setSampleBufferDelegate(nil, queue: nil)
                }
                captureSession.removeOutput(output)
            }
            captureSession.commitConfiguration()
        }
    }

    public func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPreviewTime >= 1.0 / 15.0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        lastPreviewTime = now
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            return
        }
        frameContinuation.yield(VoiceVideoFrame(image: cgImage))
    }
}
