import Testing
import CoreGraphics
import PDFKit
import ScannerCore
import Recognition
import Export

/// Spike 1+2 wiring: OCR runs on-device (here, in the simulator) and its boxes drive a searchable PDF.
struct TextRecognizerTests {
    @Test func recognizesPrintedSpanish() async throws {
        let image = Fixtures.page(lines: ["COMPROBANTE DE DOMICILIO", "Total: $1,234.56 MXN", "Fecha: 31 de agosto de 2026"])
        let result = try await TextRecognizer().recognize(image)

        #expect(result.text.localizedCaseInsensitiveContains("COMPROBANTE"))
        #expect(result.text.localizedCaseInsensitiveContains("DOMICILIO"))
        #expect(result.text.contains("1,234.56"))
        #expect(result.confidenceBand != .low)
        #expect(!result.words.isEmpty)
        for word in result.words {
            #expect(word.box.minX >= 0 && word.box.maxX <= 1.0001)
            #expect(word.box.minY >= 0 && word.box.maxY <= 1.0001)
            #expect(word.box.width > 0 && word.box.height > 0)
        }
    }

    @Test func recognizedTextSurvivesTheRoundTripIntoPDF() async throws {
        let image = Fixtures.page(lines: ["CONTRATO DE ARRENDAMIENTO", "Cláusula primera"])
        let recognition = try await TextRecognizer().recognize(image)
        let document = Fixtures.document(pages: [ScanPage(original: image, recognition: recognition)])

        let export = try SearchablePDFBuilder(preset: .standard).build(document)
        let pdf = try #require(PDFDocument(data: export.data))
        let matches = pdf.findString("ARRENDAMIENTO", withOptions: .caseInsensitive)
        #expect(matches.count == 1)

        // The fixture draws the first line near the top of the page, so the hit must be in the top third.
        let page = try #require(pdf.page(at: 0))
        let hit = try #require(matches.first).bounds(for: page)
        #expect(hit.minY > page.bounds(for: .mediaBox).height * 2 / 3)
    }
}
