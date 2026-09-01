import SwiftUI
import VisionKit
import ScannerCore

/// M0 stand-in: Apple's stock document camera. It returns already-cropped, already-filtered pages and
/// exposes no per-frame signals, so it cannot satisfy CAP-01 (live guidance/auto-capture) or CAP-04
/// (untouched originals). CaptureKit's own camera replaces it in M3; the rest of the pipeline is unchanged.
public struct DocumentCameraView: UIViewControllerRepresentable {
    public enum Outcome: Sendable {
        case scanned([CGImage])
        case cancelled
        case failed(String)
    }

    @MainActor public static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    private let onFinish: @MainActor (Outcome) -> Void

    public init(onFinish: @escaping @MainActor (Outcome) -> Void) {
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        private let onFinish: @MainActor (Outcome) -> Void

        init(onFinish: @escaping @MainActor (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).uprightCGImage() }
            onFinish(.scanned(images))
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.cancelled)
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onFinish(.failed(error.localizedDescription))
        }
    }
}
