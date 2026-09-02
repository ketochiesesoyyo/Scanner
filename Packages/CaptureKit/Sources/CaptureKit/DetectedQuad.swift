import CoreGraphics
import Vision

/// A detected page in normalized image coordinates (origin lower-left — Vision's convention).
public struct DetectedQuad: Sendable, Hashable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint
    public var confidence: Float

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint, confidence: Float) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
    }

    init(_ observation: DetectedDocumentObservation) {
        self.init(
            topLeft: CGPoint(x: observation.topLeft.x, y: observation.topLeft.y),
            topRight: CGPoint(x: observation.topRight.x, y: observation.topRight.y),
            bottomRight: CGPoint(x: observation.bottomRight.x, y: observation.bottomRight.y),
            bottomLeft: CGPoint(x: observation.bottomLeft.x, y: observation.bottomLeft.y),
            confidence: observation.confidence
        )
    }

    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Shoelace area in normalized units — 1.0 means the page fills the frame.
    public var area: CGFloat {
        let points = corners
        var sum: CGFloat = 0
        for index in 0..<4 {
            let a = points[index]
            let b = points[(index + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Largest displacement between matching corners — the stability signal.
    public func maxCornerDistance(to other: DetectedQuad) -> CGFloat {
        zip(corners, other.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Smallest distance from any corner to the frame edge; ~0 means a corner is probably cut off.
    public var edgeMargin: CGFloat {
        corners.map { min($0.x, 1 - $0.x, $0.y, 1 - $0.y) }.min() ?? 0
    }
}

public enum CaptureGuidance: String, Sendable {
    case searching, moveCloser, includeEdges, moreLight, holdStill, ready
}
