import Testing
import CoreGraphics
import CaptureKit

/// M3.2: the auto-capture decision logic, exercised as pure functions (the Simulator has no camera).
struct AutoCaptureGateTests {
    private static func quad(inset: CGFloat = 0.15, jitter: CGFloat = 0, confidence: Float = 0.95) -> DetectedQuad {
        DetectedQuad(
            topLeft: CGPoint(x: inset + jitter, y: 1 - inset),
            topRight: CGPoint(x: 1 - inset + jitter, y: 1 - inset),
            bottomRight: CGPoint(x: 1 - inset + jitter, y: inset),
            bottomLeft: CGPoint(x: inset + jitter, y: inset),
            confidence: confidence
        )
    }

    @Test func capturesOnceAfterStableFramesThenCoolsDown() {
        var gate = AutoCaptureGate()
        var captures = 0
        for _ in 0..<20 {
            if gate.evaluate(quad: Self.quad(), meanLuma: 120, autoCaptureEnabled: true) == .capture { captures += 1 }
        }
        #expect(captures == 1)
        #expect(gate.isCoolingDown)

        // Page leaves the frame → gate re-arms → next stable page captures again.
        for _ in 0..<5 {
            #expect(gate.evaluate(quad: nil, meanLuma: 120, autoCaptureEnabled: true) == .guidance(.searching))
        }
        #expect(!gate.isCoolingDown)
        captures = 0
        for _ in 0..<20 {
            if gate.evaluate(quad: Self.quad(), meanLuma: 120, autoCaptureEnabled: true) == .capture { captures += 1 }
        }
        #expect(captures == 1)
    }

    @Test func driftingQuadNeverCaptures() {
        var gate = AutoCaptureGate()
        var offset: CGFloat = 0
        for _ in 0..<30 {
            offset += 0.02
            let verdict = gate.evaluate(quad: Self.quad(jitter: offset.truncatingRemainder(dividingBy: 0.08)), meanLuma: 120, autoCaptureEnabled: true)
            #expect(verdict != .capture)
        }
    }

    @Test func guidanceMatchesTheProblem() {
        var gate = AutoCaptureGate()
        #expect(gate.evaluate(quad: nil, meanLuma: 120, autoCaptureEnabled: true) == .guidance(.searching))
        #expect(gate.evaluate(quad: Self.quad(), meanLuma: 20, autoCaptureEnabled: true) == .guidance(.moreLight))
        #expect(gate.evaluate(quad: Self.quad(inset: 0.42), meanLuma: 120, autoCaptureEnabled: true) == .guidance(.moveCloser))
        #expect(gate.evaluate(quad: Self.quad(inset: 0.0), meanLuma: 120, autoCaptureEnabled: true) == .guidance(.includeEdges))
        #expect(gate.evaluate(quad: Self.quad(confidence: 0.3), meanLuma: 120, autoCaptureEnabled: true) == .guidance(.searching))
    }

    @Test func manualModeReportsReadyButNeverFires() {
        var gate = AutoCaptureGate()
        var sawReady = false
        for _ in 0..<20 {
            let verdict = gate.evaluate(quad: Self.quad(), meanLuma: 120, autoCaptureEnabled: false)
            #expect(verdict != .capture)
            if verdict == .guidance(.ready) { sawReady = true }
        }
        #expect(sawReady)
    }

    @Test func quadGeometry() {
        let full = DetectedQuad(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1), bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0), confidence: 1)
        #expect(abs(full.area - 1) < 0.0001)
        #expect(full.edgeMargin == 0)
        let half = Self.quad(inset: 0.25)
        #expect(abs(half.area - 0.25) < 0.0001)
        #expect(half.maxCornerDistance(to: Self.quad(inset: 0.25, jitter: 0.03)) > 0.02)
    }
}
