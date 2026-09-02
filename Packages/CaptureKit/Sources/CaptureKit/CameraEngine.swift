@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import Vision

/// The AVFoundation side of CAP-01. Owns the session on its own queues (never the main thread),
/// analyzes ~10 frames/s with document segmentation, drives the AutoCaptureGate, and takes full-res
/// stills whose bytes are stored verbatim (CAP-04 — the sensor's file is the original).
public final class CameraEngine: NSObject, @unchecked Sendable {
    public struct Update: Sendable {
        public let quad: DetectedQuad?
        public let guidance: CaptureGuidance
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "mx.scanner.camera.session")
    private let analysisQueue = DispatchQueue(label: "mx.scanner.camera.analysis")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var gate = AutoCaptureGate()
    private var autoCaptureEnabled = true
    private var analyzing = false
    private var frameCounter = 0
    private var handlers: [PhotoHandler] = []
    private var onUpdate: (@Sendable (Update) -> Void)?
    private var onPhoto: (@Sendable (Result<Data, Error>, _ auto: Bool) -> Void)?

    public static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    public func configure(
        onUpdate: @escaping @Sendable (Update) -> Void,
        onPhoto: @escaping @Sendable (Result<Data, Error>, _ auto: Bool) -> Void
    ) {
        self.onUpdate = onUpdate
        self.onPhoto = onPhoto
    }

    /// Attach before `start()`; safe on the main thread (only wires the layer to the session).
    public func attach(to layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
    }

    public func start() {
        sessionQueue.async { [self] in
            configureSessionIfNeeded()
            if !session.isRunning { session.startRunning() }
        }
    }

    public func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    public func setTorch(_ on: Bool) {
        sessionQueue.async { [self] in
            guard let device, device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    public func setAutoCapture(_ enabled: Bool) {
        analysisQueue.async { [self] in
            autoCaptureEnabled = enabled
            if !enabled { gate.reset() }
        }
    }

    public func captureStill(auto: Bool = false) {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait EXIF; ingest bakes orientation at decode
            }
            let handler = PhotoHandler { [weak self] result in
                guard let self else { return }
                self.sessionQueue.async { self.handlers.removeAll { $0.finished } }
                self.onPhoto?(result, auto)
            }
            handlers.append(handler)
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: handler)
        }
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        device = camera
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
    }

    /// Mean of the Y plane, sampled sparsely — the "more light" signal.
    static func meanLuma(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        var sum = 0, count = 0
        var y = 0
        while y < height {
            let row = base + y * bytesPerRow
            var x = 0
            while x < width {
                sum += Int(row.load(fromByteOffset: x, as: UInt8.self))
                count += 1
                x += 32
            }
            y += 32
        }
        return count > 0 ? Double(sum) / Double(count) : 0
    }

    private struct BufferBox: @unchecked Sendable { let buffer: CVPixelBuffer }

    private final class PhotoHandler: NSObject, AVCapturePhotoCaptureDelegate {
        private let completion: @Sendable (Result<Data, Error>) -> Void
        private(set) var finished = false

        init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
            self.completion = completion
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
            finished = true
            if let error {
                completion(.failure(error))
            } else if let data = photo.fileDataRepresentation() {
                completion(.success(data))
            } else {
                completion(.failure(CocoaError(.fileReadUnknown)))
            }
        }
    }
}

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Runs on analysisQueue. Analyze every 3rd frame, one at a time.
        frameCounter += 1
        guard frameCounter % 3 == 0, !analyzing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analyzing = true
        let luma = Self.meanLuma(of: pixelBuffer)
        let box = BufferBox(buffer: pixelBuffer)
        Task { [weak self] in
            let observation = try? await DetectDocumentSegmentationRequest().perform(on: box.buffer)
            guard let self else { return }
            self.analysisQueue.async {
                self.analyzing = false
                let quad = (observation ?? nil).map(DetectedQuad.init)
                let verdict = self.gate.evaluate(quad: quad, meanLuma: luma, autoCaptureEnabled: self.autoCaptureEnabled)
                switch verdict {
                case .capture:
                    self.captureStill(auto: true)
                    self.onUpdate?(Update(quad: quad, guidance: .ready))
                case .guidance(let guidance):
                    self.onUpdate?(Update(quad: quad, guidance: guidance))
                }
            }
        }
    }
}
