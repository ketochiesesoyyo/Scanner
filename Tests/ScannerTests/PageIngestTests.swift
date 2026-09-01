import Testing
import Foundation
import ScannerCore
import ImagePipeline
import Export

/// M1.4 thumbnails and M1.5 export formats.
struct PageIngestTests {
    @Test func bitmapIngestKeepsSizeAndMakesSmallThumbnail() throws {
        let assets = try PageIngest.prepare(image: Fixtures.page(lines: ["hola"]))
        #expect(assets.originalExtension == "jpg")
        #expect(assets.pixelSize == CGSize(width: 1240, height: 1754))
        let thumbnail = try ImageDecoder.image(from: assets.thumbnailData)
        #expect(max(thumbnail.width, thumbnail.height) <= PageIngest.thumbnailLongSide)
        #expect(assets.thumbnailData.count < assets.originalData.count)
    }

    @Test func fileIngestKeepsBytesVerbatim() throws {
        let jpeg = try ImageEncoder.jpeg(Fixtures.page(lines: ["factura"]), maxLongSide: 800, quality: 0.6).data
        let assets = try PageIngest.prepare(imageData: jpeg)
        #expect(assets.originalData == jpeg)
        #expect(assets.originalExtension == "jpg" || assets.originalExtension == "jpeg")
        #expect(assets.pixelSize.height == 800)
        #expect(max(try ImageDecoder.image(from: assets.thumbnailData).height, 0) <= PageIngest.thumbnailLongSide)
    }

    @Test func jpegExporterWritesOnePerPage() throws {
        let document = Fixtures.document(pages: [
            ScanPage(original: Fixtures.page(lines: ["uno"])),
            ScanPage(original: Fixtures.page(lines: ["dos"])),
        ])
        let jpegs = try JPEGExporter(preset: .email).export(document)
        #expect(jpegs.count == 2)
        for data in jpegs {
            let image = try ImageDecoder.image(from: data)
            #expect(max(image.width, image.height) <= 1500)
        }
    }

    @Test func textExporterJoinsPages() {
        let recognition = PageRecognition(lines: [RecognizedLine(text: "Total 100", box: .zero, confidence: 1, words: [])], duration: .zero)
        let document = Fixtures.document(pages: [
            ScanPage(original: Fixtures.page(lines: []), recognition: recognition),
            ScanPage(original: Fixtures.page(lines: []), recognition: recognition),
        ])
        let text = TextExporter.text(document)
        #expect(text.contains("— Page 1 —"))
        #expect(text.contains("— Page 2 —"))
        #expect(text.components(separatedBy: "Total 100").count == 3)
    }

    @Test func exportFileNamesAreFilesystemSafe() {
        #expect(ExportFileName.base(from: "Scan 31 Aug 2026, 22:41") == "Scan-31-Aug-2026-22-41")
        #expect(ExportFileName.base(from: "   ") == "Scan")
        #expect(ExportFileName.base(from: "Recibo/nómina: Agosto") == "Recibo-nómina-Agosto")
    }
}
