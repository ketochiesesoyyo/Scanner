import Foundation
import CoreGraphics
import Vision
import ScannerCore

/// The quality gate (PRD QLT-01/QLT-02): scores every page, finds likely duplicates and page-number
/// gaps, and returns warnings. It never deletes, reorders, or blocks — the user decides.
public struct DocumentVerifier: Sendable {
    public var thresholds: QualityThresholds

    public init(thresholds: QualityThresholds = .standard) {
        self.thresholds = thresholds
    }

    public func verify(_ document: ScanDocument, contentRevision: Int) async throws -> VerificationResult {
        var qualities: [PageQuality] = []
        var warnings: [ScanWarning] = []
        var signatures: [PageSignature] = []

        for (index, page) in document.pages.enumerated() {
            // One decoded page at a time; released before the next iteration.
            let image = try page.loadOriginal()
            var smudge: Double?
            if #available(iOS 26.0, macOS 26.0, *) {
                smudge = (try? await DetectLensSmudgeRequest().perform(on: image)).map { Double($0.confidence) }
            }
            let luma = QualityAnalyzer.luma(of: image)
            let quality = QualityAnalyzer.quality(luma: luma, recognition: page.recognition, smudgeConfidence: smudge)
            qualities.append(quality)
            warnings.append(contentsOf: Self.pageWarnings(for: quality, at: index, thresholds: thresholds))
            // Feature print needs the neural runtime (absent on the Simulator, can fail elsewhere);
            // the dHash from the luma we already have is the always-available fallback.
            signatures.append(PageSignature(
                featurePrint: try? await GenerateImageFeaturePrintRequest().perform(on: image),
                hash: luma.map(Self.differenceHash)
            ))
        }

        warnings.append(contentsOf: Self.duplicateWarnings(signatures: signatures, thresholds: thresholds))
        warnings.append(contentsOf: Self.sequenceWarnings(forPageTexts: document.pages.map { $0.recognition?.text }))

        return VerificationResult(contentRevision: contentRevision, pageQualities: qualities, warnings: warnings)
    }

    /// Thresholds → warnings for one page. Public so tests and previews can exercise it directly.
    public static func pageWarnings(for quality: PageQuality, at index: Int, thresholds: QualityThresholds) -> [ScanWarning] {
        var warnings: [ScanWarning] = []
        if quality.blurVariance < thresholds.minBlurVariance { warnings.append(.blur(pageIndex: index)) }
        if quality.glareRatio > thresholds.maxGlareRatio { warnings.append(.glare(pageIndex: index)) }
        if quality.shadowSpread > thresholds.maxShadowSpread { warnings.append(.shadow(pageIndex: index)) }
        if let share = quality.lowConfidenceShare, share > thresholds.maxLowConfidenceShare {
            warnings.append(.readability(pageIndex: index))
        }
        if let smudge = quality.smudgeConfidence, smudge > thresholds.maxSmudgeConfidence {
            warnings.append(.smudge(pageIndex: index))
        }
        return warnings
    }

    struct PageSignature {
        let featurePrint: FeaturePrintObservation?
        let hash: UInt64?
    }

    static func duplicateWarnings(signatures: [PageSignature], thresholds: QualityThresholds) -> [ScanWarning] {
        var warnings: [ScanWarning] = []
        for i in 0..<signatures.count {
            for j in (i + 1)..<signatures.count {
                let isDuplicate: Bool
                if let a = signatures[i].featurePrint, let b = signatures[j].featurePrint,
                   let distance = try? a.distance(to: b) {
                    isDuplicate = distance <= thresholds.maxDuplicateDistance
                } else if let a = signatures[i].hash, let b = signatures[j].hash {
                    isDuplicate = hammingDistance(a, b) <= thresholds.maxDuplicateHamming
                } else {
                    isDuplicate = false
                }
                if isDuplicate { warnings.append(.possibleDuplicate(pageIndex: j, duplicateOf: i)) }
            }
        }
        return warnings
    }

    /// 9×8 gradient hash (dHash): resilient to re-encoding, catches identical/near-identical pages.
    /// Public for tests.
    public static func differenceHash(_ image: CGImage) -> UInt64? {
        QualityAnalyzer.luma(of: image).map(differenceHash)
    }

    static func differenceHash(_ luma: QualityAnalyzer.LumaBuffer) -> UInt64 {
        let columns = 9, rows = 8
        var samples = [Double](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                // Box-average the source region for stability.
                let x0 = column * luma.width / columns, x1 = max(x0 + 1, (column + 1) * luma.width / columns)
                let y0 = row * luma.height / rows, y1 = max(y0 + 1, (row + 1) * luma.height / rows)
                var sum = 0
                for y in y0..<y1 {
                    let base = y * luma.width
                    for x in x0..<x1 { sum += Int(luma.pixels[base + x]) }
                }
                samples[row * columns + column] = Double(sum) / Double((x1 - x0) * (y1 - y0))
            }
        }
        var hash: UInt64 = 0
        for row in 0..<rows {
            for column in 0..<(columns - 1) {
                hash <<= 1
                if samples[row * columns + column] > samples[row * columns + column + 1] { hash |= 1 }
            }
        }
        return hash
    }

    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: Page-number sequence ("Página 3 de 7", "Page 3 of 7", "3/7")

    static let labeledPattern = try! NSRegularExpression(
        pattern: #"(?:p[áa]gina|page|p[áa]g\.?|p\.)\s*(\d{1,3})\s*(?:de|of|/)\s*(\d{1,3})"#,
        options: [.caseInsensitive]
    )
    static let barePattern = try! NSRegularExpression(pattern: #"^\s*(\d{1,3})\s*/\s*(\d{1,3})\s*$"#)

    /// Public for tests: extracts "Página 3 de 7" / "Page 3 of 7" / "3/7" from a page's text.
    public static func pageNumbers(in text: String) -> (number: Int, total: Int)? {
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            for pattern in [labeledPattern, barePattern] {
                guard let match = pattern.firstMatch(in: line, range: range),
                      let numberRange = Range(match.range(at: 1), in: line),
                      let totalRange = Range(match.range(at: 2), in: line),
                      let number = Int(line[numberRange]), let total = Int(line[totalRange]),
                      number >= 1, number <= total, total <= 200 else { continue }
                return (number, total)
            }
        }
        return nil
    }

    /// Warns about missing page numbers and out-of-capture-order pages. Public for tests.
    public static func sequenceWarnings(forPageTexts texts: [String?]) -> [ScanWarning] {
        let found: [(pageIndex: Int, number: Int, total: Int)] = texts.enumerated().compactMap { index, text in
            guard let text, let numbers = pageNumbers(in: text) else { return nil }
            return (index, numbers.number, numbers.total)
        }
        guard found.count >= 2, Set(found.map(\.total)).count == 1, let total = found.first?.total else { return [] }

        var warnings: [ScanWarning] = []
        // Only claim pages are missing when every captured page carries a number — otherwise the
        // unnumbered pages might be exactly the ones we'd call missing.
        if found.count == texts.count {
            let missing = Set(1...total).subtracting(found.map(\.number)).sorted()
            if !missing.isEmpty { warnings.append(.missingPages(numbers: missing)) }
        }
        for k in 1..<found.count where found[k].number < found[k - 1].number {
            warnings.append(.outOfOrder(pageIndex: found[k].pageIndex))
        }
        return warnings
    }
}
