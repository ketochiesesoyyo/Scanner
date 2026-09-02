import SwiftUI
import VisionKit
import ScannerCore

/// M0 stand-in: Apple's stock document camera. It returns already-cropped, already-filtered pages and
/// exposes no per-frame signals, so it cannot satisfy CAP-01 (live guidance/auto-capture) or CAP-04
/// (untouched originals). CaptureKit's own camera replaces it in M3; the rest of the pipeline is unchanged.
public struct DocumentCameraView: UIViewControllerRepresentable {
    /// The finished scan, safe to carry across threads: VNDocumentCameraScan is an immutable result
    /// container (plain NSObject, not main-actor-bound). `image(at:)` renders the full-resolution
    /// page — call it OFF the main thread: rendering on main during the cover's dismissal is exactly
    /// what wedged the transition and froze the app on device.
    public struct CameraScan: @unchecked Sendable {
        private let scan: VNDocumentCameraScan
        public let pageCount: Int

        init(_ scan: VNDocumentCameraScan) {
            self.scan = scan
            self.pageCount = scan.pageCount
        }

        public func image(at index: Int) -> UIImage {
            scan.imageOfPage(at: index)
        }
    }

    public enum Outcome: Sendable {
        case scanned(CameraScan)
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
            // Do NOTHING heavy here: this runs on the main thread right as the dismissal animation
            // starts. Page images are rendered later, off-main, one at a time.
            onFinish(.scanned(CameraScan(scan)))
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(.cancelled)
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onFinish(.failed(error.localizedDescription))
        }
    }
}
