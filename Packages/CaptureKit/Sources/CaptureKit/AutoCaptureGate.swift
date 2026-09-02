import CoreGraphics
import Foundation

/// Frame-by-frame decision for CAP-01: what to tell the user, and when the shot is good enough to
/// take itself. Pure logic, fully unit-tested — the camera engine just feeds it frames.
public struct AutoCaptureGate: Sendable {
    public struct Thresholds: Sendable {
        public var minConfidence: Float = 0.8
        /// Page must cover at least this share of the frame.
        public var minArea: CGFloat = 0.15
        /// Corners closer than this to the frame edge read as "part of the page is cut off".
        public var minEdgeMargin: CGFloat = 0.005
        /// Per-frame corner movement above this resets stability ("hold still").
        public var maxCornerDrift: CGFloat = 0.015
        /// Analyzed frames (~10/s) that must be stable before auto-capture — ≈0.6 s.
        public var requiredStableFrames: Int = 6
        public var minMeanLuma: Double = 55
        public init() {}
    }

    public enum Verdict: Sendable, Equatable {
        case guidance(CaptureGuidance)
        /// Take the photo now. The gate has already begun its cooldown.
        case capture
    }

    public var thresholds: Thresholds
    private var previous: DetectedQuad?
    private var stableFrames = 0
    private var coolingDown = false
    private var framesWithoutQuad = 0

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    public var isCoolingDown: Bool { coolingDown }

    /// After a capture the gate stays quiet until the document leaves the frame, so the same page
    /// isn't captured twice.
    public mutating func beginCooldown() {
        coolingDown = true
        stableFrames = 0
    }

    public mutating func reset() {
        previous = nil
        stableFrames = 0
        coolingDown = false
        framesWithoutQuad = 0
    }

    public mutating func evaluate(quad: DetectedQuad?, meanLuma: Double, autoCaptureEnabled: Bool) -> Verdict {
        guard let quad else {
            previous = nil
            stableFrames = 0
            framesWithoutQuad += 1
            if coolingDown && framesWithoutQuad >= 4 { coolingDown = false }
            return .guidance(.searching)
        }
        framesWithoutQuad = 0
        defer { previous = quad }

        if meanLuma < thresholds.minMeanLuma { stableFrames = 0; return .guidance(.moreLight) }
        if quad.confidence < thresholds.minConfidence { stableFrames = 0; return .guidance(.searching) }
        if quad.area < thresholds.minArea { stableFrames = 0; return .guidance(.moveCloser) }
        if quad.edgeMargin < thresholds.minEdgeMargin { stableFrames = 0; return .guidance(.includeEdges) }
        if let previous, quad.maxCornerDistance(to: previous) > thresholds.maxCornerDrift {
            stableFrames = 0
            return .guidance(.holdStill)
        }
        stableFrames += 1
        guard stableFrames >= thresholds.requiredStableFrames else { return .guidance(.holdStill) }
        guard autoCaptureEnabled, !coolingDown else { return .guidance(.ready) }
        beginCooldown()
        return .capture
    }
}
