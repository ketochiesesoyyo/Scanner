import Testing
import CoreGraphics
import Foundation
import ScannerCore
import Recognition

/// M2.1–M2.3: warnings fire on the bad fixtures and stay quiet on the clean ones (QLT-01/02).
struct VerificationTests {
    static let cleanPage = Fixtures.page(lines: ["CONTRATO DE ARRENDAMIENTO", "Cláusula primera: el arrendador…", "Cláusula segunda: el plazo…"])

    @Test func blurIsFlaggedOnBlurredNotSharp() {
        let sharp = QualityAnalyzer.quality(of: Self.cleanPage, recognition: nil, smudgeConfidence: nil)
        let blurred = QualityAnalyzer.quality(of: Fixtures.blurred(Self.cleanPage, factor: 16), recognition: nil, smudgeConfidence: nil)
        print("QVALS blur: sharp=\(sharp.blurVariance) blurred=\(blurred.blurVariance) glareClean=\(sharp.glareRatio) shadowClean=\(sharp.shadowSpread)")
        #expect(sharp.blurVariance > blurred.blurVariance)
        #expect(!DocumentVerifier.pageWarnings(for: sharp, at: 0, thresholds: .standard).contains(.blur(pageIndex: 0)),
                "sharp variance \(sharp.blurVariance)")
        #expect(DocumentVerifier.pageWarnings(for: blurred, at: 0, thresholds: .standard).contains(.blur(pageIndex: 0)),
                "blurred variance \(blurred.blurVariance)")
    }

    @Test func glareIsFlaggedOnGlareBlobNotCleanPaper() {
        let clean = QualityAnalyzer.quality(of: Self.cleanPage, recognition: nil, smudgeConfidence: nil)
        let glared = QualityAnalyzer.quality(of: Fixtures.withGlare(Self.cleanPage), recognition: nil, smudgeConfidence: nil)
        #expect(!DocumentVerifier.pageWarnings(for: clean, at: 0, thresholds: .standard).contains(.glare(pageIndex: 0)),
                "clean glare ratio \(clean.glareRatio)")
        #expect(DocumentVerifier.pageWarnings(for: glared, at: 0, thresholds: .standard).contains(.glare(pageIndex: 0)),
                "glared ratio \(glared.glareRatio)")
    }

    @Test func shadowIsFlaggedOnGradientNotEvenLight() {
        let clean = QualityAnalyzer.quality(of: Self.cleanPage, recognition: nil, smudgeConfidence: nil)
        let shadowed = QualityAnalyzer.quality(of: Fixtures.withShadow(Self.cleanPage), recognition: nil, smudgeConfidence: nil)
        #expect(!DocumentVerifier.pageWarnings(for: clean, at: 0, thresholds: .standard).contains(.shadow(pageIndex: 0)),
                "clean spread \(clean.shadowSpread)")
        #expect(DocumentVerifier.pageWarnings(for: shadowed, at: 0, thresholds: .standard).contains(.shadow(pageIndex: 0)),
                "shadowed spread \(shadowed.shadowSpread)")
    }

    @Test func readabilityUsesLowConfidenceShare() {
        let poor = PageRecognition(
            lines: [RecognizedLine(text: "???", box: .zero, confidence: 0.2,
                                   words: (0..<10).map { RecognizedWord(text: "w\($0)", box: .zero, confidence: 0.2) })],
            duration: .zero
        )
        let quality = QualityAnalyzer.quality(of: Self.cleanPage, recognition: poor, smudgeConfidence: nil)
        #expect(DocumentVerifier.pageWarnings(for: quality, at: 3, thresholds: .standard).contains(.readability(pageIndex: 3)))
    }

    @Test func duplicatePagesAreFlaggedDistinctOnesAreNot() async throws {
        let pageA = Fixtures.page(lines: ["FACTURA A-1234", "Subtotal $100.00", "IVA $16.00"])
        let pageB = Fixtures.page(lines: ["Términos y condiciones del servicio", "El presente contrato obliga a las partes", "a cumplir las cláusulas siguientes"])
        let document = Fixtures.document(pages: [ScanPage(original: pageA), ScanPage(original: pageB), ScanPage(original: pageA)])
        let result = try await DocumentVerifier().verify(document, contentRevision: 1)
        let duplicates = result.warnings.filter { if case .possibleDuplicate = $0 { true } else { false } }
        let hashA = DocumentVerifier.differenceHash(pageA)!
        let hashB = DocumentVerifier.differenceHash(pageB)!
        print("QVALS duplicate hamming distinct=\(DocumentVerifier.hammingDistance(hashA, hashB))")
        #expect(duplicates == [.possibleDuplicate(pageIndex: 2, duplicateOf: 0)], "warnings: \(result.warnings)")
        #expect(DocumentVerifier.hammingDistance(hashA, hashB) > QualityThresholds.standard.maxDuplicateHamming)
    }

    @Test func sequenceGapAndOrderAreDetected() {
        let gap = DocumentVerifier.sequenceWarnings(forPageTexts: ["Página 1 de 3\nCFE", "Página 3 de 3\nRFC"])
        #expect(gap.contains(.missingPages(numbers: [2])), "\(gap)")

        let order = DocumentVerifier.sequenceWarnings(forPageTexts: ["Page 2 of 2\nbody", "Page 1 of 2\nbody"])
        #expect(order.contains(.outOfOrder(pageIndex: 1)), "\(order)")

        // An unnumbered page means we can't claim anything is missing.
        let mixed = DocumentVerifier.sequenceWarnings(forPageTexts: ["Página 1 de 3", nil])
        #expect(mixed.isEmpty)

        // "3/7"-style bare fractions parse; dates must not.
        #expect(DocumentVerifier.pageNumbers(in: "2/3") != nil)
        #expect(DocumentVerifier.pageNumbers(in: "Fecha: 31/12/2025") == nil)
    }

    @Test func ignoredWarningKeysAreStable() {
        #expect(ScanWarning.possibleDuplicate(pageIndex: 2, duplicateOf: 0).key == "duplicate:0-2")
        #expect(ScanWarning.missingPages(numbers: [2, 4]).key == "missing:2,4")
    }
}
