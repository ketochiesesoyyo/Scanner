import Foundation
import CoreGraphics

/// One recognized token. `box` is normalized to the page (0…1) with a lower-left origin —
/// Vision's convention, which is also PDF's, so no flipping happens between OCR and export.
public struct RecognizedWord: Sendable, Hashable {
    public let text: String
    public let box: CGRect
    public let confidence: Float

    public init(text: String, box: CGRect, confidence: Float) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

public struct RecognizedLine: Sendable, Hashable {
    public let text: String
    public let box: CGRect
    public let confidence: Float
    public let words: [RecognizedWord]

    public init(text: String, box: CGRect, confidence: Float, words: [RecognizedWord]) {
        self.text = text
        self.box = box
        self.confidence = confidence
        self.words = words
    }
}

/// Coarse confidence used in the UI and in telemetry (PRD §12 only permits bands, never raw text).
public enum ConfidenceBand: String, Sendable, Codable {
    case high, medium, low

    public init(meanConfidence: Float) {
        switch meanConfidence {
        case 0.8...: self = .high
        case 0.5..<0.8: self = .medium
        default: self = .low
        }
    }
}

public struct PageRecognition: Sendable {
    public let lines: [RecognizedLine]
    public let duration: Duration

    public init(lines: [RecognizedLine], duration: Duration) {
        self.lines = lines
        self.duration = duration
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }
    public var words: [RecognizedWord] { lines.flatMap(\.words) }
    public var isEmpty: Bool { lines.isEmpty }

    public var meanConfidence: Float {
        guard !lines.isEmpty else { return 0 }
        return lines.reduce(0) { $0 + $1.confidence } / Float(lines.count)
    }

    public var confidenceBand: ConfidenceBand { ConfidenceBand(meanConfidence: meanConfidence) }
}
