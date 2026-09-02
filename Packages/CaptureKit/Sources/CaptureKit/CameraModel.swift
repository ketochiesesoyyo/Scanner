@preconcurrency import AVFoundation
import Foundation
import Observation

/// Main-actor bridge between the engine and SwiftUI.
@MainActor @Observable
public final class CameraModel {
    public struct CapturedPage: Sendable, Identifiable {
        public let id = UUID()
        /// The photo's bytes exactly as the sensor pipeline produced them — stored verbatim (CAP-04).
        public let data: Data
        public let auto: Bool
    }

    public private(set) var guidance: CaptureGuidance = .searching
    public private(set) var quad: DetectedQuad?
    public private(set) var pages: [CapturedPage] = []
    public private(set) var permissionDenied = false
    /// Toggles on every captured page — drives the shutter blink.
    public private(set) var shutterTick = false
    public var errorMessage: String?

    public var torchOn = false {
        didSet { engine.setTorch(torchOn) }
    }
    public var autoCapture = true {
        didSet { engine.setAutoCapture(autoCapture) }
    }

    public let engine = CameraEngine()

    public init() {
        engine.configure(
            onUpdate: { [weak self] update in
                Task { @MainActor in self?.apply(update) }
            },
            onPhoto: { [weak self] result, auto in
                Task { @MainActor in self?.finishPhoto(result, auto: auto) }
            }
        )
    }

    public func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                permissionDenied = true
                return
            }
        default:
            permissionDenied = true
            return
        }
        #if DEBUG
        print("PHASE camera start")
        #endif
        engine.start()
    }

    public func stop() {
        #if DEBUG
        print("PHASE camera stop")
        #endif
        engine.stop()
    }

    public func shutterTapped() { engine.captureStill(auto: false) }

    private func apply(_ update: CameraEngine.Update) {
        quad = update.quad
        guidance = update.guidance
    }

    private func finishPhoto(_ result: Result<Data, Error>, auto: Bool) {
        switch result {
        case .success(let data):
            pages.append(CapturedPage(data: data, auto: auto))
            shutterTick.toggle()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
