import Testing
import CoreGraphics
import PDFKit
import ScannerCore
import Export

/// Spike 1 from docs/mvp-plan.md §7: the invisible text layer must be findable and land where the word is.
struct SearchablePDFTests {
    @Test func textLayerIsSearchableAndAligned() throws {
        let image = Fixtures.page(lines: [])
        let words = [
            RecognizedWord(text: "FACTURA", box: CGRect(x: 0.10, y: 0.80, width: 0.30, height: 0.05), confidence: 1),
            RecognizedWord(text: "1234", box: CGRect(x: 0.45, y: 0.80, width: 0.15, height: 0.05), confidence: 1),
        ]
        let recognition = PageRecognition(lines: [RecognizedLine(text: "FACTURA 1234", box: .zero, confidence: 1, words: words)], duration: .zero)
        let document = Fixtures.document(pages: [ScanPage(original: image, recognition: recognition)])

        let export = try SearchablePDFBuilder(preset: .standard).build(document)
        let pdf = try #require(PDFDocument(data: export.data))
        #expect(pdf.pageCount == 1)
        #expect(pdf.string?.contains("FACTURA") == true)

        let matches = pdf.findString("1234", withOptions: [])
        #expect(matches.count == 1)
        let page = try #require(pdf.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)
        let hit = try #require(matches.first).bounds(for: page)
        // Selection should sit on the word's box: x at 45% of the width, y at 80% of the height (±3%).
        #expect(abs(hit.minX / pageBounds.width - 0.45) < 0.03)
        #expect(abs(hit.minY / pageBounds.height - 0.80) < 0.03)
        #expect(abs(hit.width / pageBounds.width - 0.15) < 0.03)
    }

    @Test func pagesWithoutRecognitionHaveNoTextLayer() throws {
        let document = Fixtures.document(pages: [ScanPage(original: Fixtures.page(lines: ["hola"]))])
        let export = try SearchablePDFBuilder().build(document)
        let pdf = try #require(PDFDocument(data: export.data))
        #expect(pdf.pageCount == 1)
        #expect((pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func pagesFitInsideLetter() {
        #expect(SearchablePDFBuilder.pageSize(fitting: CGSize(width: 3000, height: 4000)) == CGSize(width: 594, height: 792))
        #expect(SearchablePDFBuilder.pageSize(fitting: CGSize(width: 4000, height: 3000)) == CGSize(width: 792, height: 594))
        #expect(SearchablePDFBuilder.pageSize(fitting: CGSize(width: 1240, height: 1754)) == CGSize(width: 560, height: 792))
    }

    @Test func emailPresetIsSmallerThanArchive() throws {
        let document = Fixtures.document(pages: [ScanPage(original: Fixtures.page(lines: ["Recibo de nómina", "Total $12,345.00"]))])
        let email = try SearchablePDFBuilder(preset: .email).build(document)
        let archive = try SearchablePDFBuilder(preset: .archive).build(document)
        #expect(email.byteCount < archive.byteCount)
    }
}
