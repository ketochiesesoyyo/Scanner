import Foundation
import CoreGraphics
import ImageIO
import Vision
import ScannerCore

/// On-device OCR (PRD OCR-01). Wraps Vision's accurate recognizer; nothing leaves the device.
public struct TextRecognizer: Sendable {
    public static let processingLocation: ProcessingLocation = .onDevice

    /// Spanish first, English second — the MVP language set from `docs/mvp-plan.md` §8.
    public static let defaultLanguages: [Locale.Language] = [
        Locale.Language(identifier: "es-MX"),
        Locale.Language(identifier: "en-US"),
    ]

    public var languages: [Locale.Language]
    public var usesLanguageCorrection: Bool

    public init(languages: [Locale.Language] = TextRecognizer.defaultLanguages, usesLanguageCorrection: Bool = true) {
        self.languages = languages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> PageRecognition {
        let clock = ContinuousClock()
        let start = clock.now

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = Self.resolve(preferred: languages, supported: request.supportedRecognitionLanguages)

        let observations = try await request.perform(on: image, orientation: orientation)
        let lines = observations.compactMap(Self.line(from:))
        return PageRecognition(lines: lines, duration: clock.now - start)
    }

    /// Vision only accepts identifiers from its supported list (e.g. "es-ES", not "es-MX"), so match by
    /// language code and keep the caller's preference order. Falls back to Vision's default when nothing matches.
    static func resolve(preferred: [Locale.Language], supported: [Locale.Language]) -> [Locale.Language] {
        var resolved: [Locale.Language] = []
        for language in preferred {
            if supported.contains(language) {
                resolved.append(language)
            } else if let code = language.languageCode,
                      let match = supported.first(where: { $0.languageCode == code }) {
                resolved.append(match)
            }
        }
        return resolved
    }

    private static func line(from observation: RecognizedTextObservation) -> RecognizedLine? {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = candidate.string
        guard !text.isEmpty else { return nil }

        let lineBox = observation.boundingBox.cgRect
        var words: [RecognizedWord] = []
        var cursor = text.startIndex
        for token in text.split(whereSeparator: \.isWhitespace) {
            guard let range = text.range(of: token, range: cursor..<text.endIndex) else { continue }
            cursor = range.upperBound
            let box = candidate.boundingBox(for: range)?.boundingBox.cgRect ?? lineBox
            words.append(RecognizedWord(text: String(token), box: box, confidence: candidate.confidence))
        }
        if words.isEmpty {
            words = [RecognizedWord(text: text, box: lineBox, confidence: candidate.confidence)]
        }
        return RecognizedLine(text: text, box: lineBox, confidence: candidate.confidence, words: words)
    }
}

extension NormalizedRect {
    var cgRect: CGRect { CGRect(x: origin.x, y: origin.y, width: width, height: height) }
}
