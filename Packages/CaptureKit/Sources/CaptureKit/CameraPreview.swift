@preconcurrency import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// The live viewfinder: preview layer, detected-quad overlay, and the volume-button shutter
/// (§9 Accessibility: an alternative capture control).
public struct CameraPreview: UIViewRepresentable {
    let engine: CameraEngine
    let quad: DetectedQuad?
    let onHardwareShutter: () -> Void

    public init(engine: CameraEngine, quad: DetectedQuad?, onHardwareShutter: @escaping () -> Void) {
        self.engine = engine
        self.quad = quad
        self.onHardwareShutter = onHardwareShutter
    }

    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        engine.attach(to: view.previewLayer)
        view.onHardwareShutter = onHardwareShutter
        return view
    }

    public func updateUIView(_ view: PreviewUIView, context: Context) {
        view.onHardwareShutter = onHardwareShutter
        view.updateQuad(quad)
    }
}

public final class PreviewUIView: UIView {
    public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onHardwareShutter: (() -> Void)?

    private let quadLayer = CAShapeLayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
        quadLayer.lineWidth = 3
        quadLayer.lineJoin = .round
        quadLayer.strokeColor = tintColor.cgColor
        quadLayer.fillColor = tintColor.withAlphaComponent(0.12).cgColor
        layer.addSublayer(quadLayer)
        let interaction = AVCaptureEventInteraction { [weak self] event in
            if event.phase == .began { self?.onHardwareShutter?() }
        }
        addInteraction(interaction)
        isAccessibilityElement = true
        accessibilityLabel = "Camera viewfinder"
        accessibilityHint = "Point at a document. It captures automatically, or press a volume button."
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        quadLayer.frame = bounds
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        quadLayer.strokeColor = tintColor.cgColor
        quadLayer.fillColor = tintColor.withAlphaComponent(0.12).cgColor
    }

    func updateQuad(_ quad: DetectedQuad?) {
        guard let quad, previewLayer.connection != nil else {
            quadLayer.path = nil
            return
        }
        // Vision's buffer-normalized (origin lower-left) → capture-device (origin top-left) →
        // layer coordinates. layerPointConverted handles rotation, gravity crop and mirroring.
        let points = quad.corners.map { corner in
            previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: corner.x, y: 1 - corner.y))
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.close()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        quadLayer.path = path.cgPath
        CATransaction.commit()
    }
}
