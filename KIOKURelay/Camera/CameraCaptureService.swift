@preconcurrency import AVFoundation
import CoreImage
import Foundation

final class CameraFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var latestImage: CGImage?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        lock.lock()
        latestImage = cgImage
        lock.unlock()
    }

    func snapshot() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return latestImage
    }
}

final class CameraSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ai.kiokurelay.camera.session")
    private let outputQueue = DispatchQueue(label: "ai.kiokurelay.camera.frames", qos: .userInitiated)
    private let receiver = CameraFrameReceiver()
    private var configured = false

    func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.cameraUnavailable
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.configurationFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(receiver, queue: outputQueue)
        guard session.canAddOutput(output) else { throw CameraError.configurationFailed }
        session.addOutput(output)

        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        configured = true
    }

    func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func snapshot() -> CGImage? { receiver.snapshot() }
}

@MainActor
final class CameraCaptureService: ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown
        case authorized
        case denied
        case unavailable
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var isRunning = false

    private let box = CameraSessionBox()
    var session: AVCaptureSession { box.session }

    func requestAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }

        guard granted else {
            authorizationState = .denied
            return
        }

        do {
            try box.configure()
            box.start()
            authorizationState = .authorized
            isRunning = true
        } catch {
            authorizationState = .unavailable
            isRunning = false
        }
    }

    func stop() {
        box.stop()
        isRunning = false
    }

    func snapshot() -> CGImage? { box.snapshot() }
}

enum CameraError: LocalizedError {
    case cameraUnavailable
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "利用できるカメラがありません"
        case .configurationFailed: "カメラを構成できませんでした"
        }
    }
}
