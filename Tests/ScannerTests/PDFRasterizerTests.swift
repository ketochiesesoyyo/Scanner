import Testing
import CoreGraphics
import Foundation
import ScannerCore
import ImagePipeline
import Export

/// Files import: PDFs picked in Files are rasterized page by page into the normal pipeline.
struct PDFRasterizerTests {
    private static func makePDF(pages: Int) throws -> Data {
        let scanPages = (0..<pages).map { ScanPage(original: Fixtures.page(lines: ["Página \($0 + 1)"])) }
        return try SearchablePDFBuilder(preset: .email).build(Fixtures.document(pages: scanPages)).data
    }

    @Test func countsAndRendersPages() throws {
        let pdf = try Self.makePDF(pages: 2)
        #expect(PDFRasterizer.pageCount(of: pdf) == 2)
        let image = try PDFRasterizer.image(from: pdf, pageIndex: 0)
        #expect(max(image.width, image.height) == 2480)
        // Letter-ish aspect from the fixture (1240×1754).
        let aspect = Double(image.width) / Double(image.height)
        #expect(abs(aspect - 1240.0 / 1754.0) < 0.02, "aspect \(aspect)")
        #expect(throws: PDFRasterizer.Failure.self) { try PDFRasterizer.image(from: pdf, pageIndex: 5) }
    }

    @Test func rejectsNonPDFData() {
        #expect(PDFRasterizer.pageCount(of: Data("not a pdf".utf8)) == nil)
    }

    @Test func rasterizedPageIngestsLikeAnyBitmap() throws {
        let pdf = try Self.makePDF(pages: 1)
        let assets = try PageIngest.prepare(image: PDFRasterizer.image(from: pdf, pageIndex: 0))
        #expect(assets.pixelSize.height == 2480)
        #expect(!assets.thumbnailData.isEmpty)
    }
}
