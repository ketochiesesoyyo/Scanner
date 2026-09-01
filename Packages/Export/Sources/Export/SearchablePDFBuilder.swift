import Foundation
import CoreGraphics
import CoreText
import ScannerCore
import ImagePipeline

public struct PDFExport: Sendable {
    public let data: Data
    public let pageCount: Int
    public var byteCount: Int { data.count }
}

public enum PDFExportError: Error {
    case noPages, contextUnavailable
}

/// Builds a PDF from a `ScanDocument`: each page is the (preset-compressed) capture with the recognized
/// words drawn invisibly on top of where they were seen, so Files, Preview and Spotlight can search and
/// select the text (PRD OCR-01 / EXP-01). No watermark, nothing proprietary.
public struct SearchablePDFBuilder: Sendable {
    public var preset: ExportPreset
    public var includesTextLayer: Bool

    public init(preset: ExportPreset = .standard, includesTextLayer: Bool = true) {
        self.preset = preset
        self.includesTextLayer = includesTextLayer
    }

    /// US Letter in points. Every page is scaled to fit inside it, keeping the capture's aspect ratio.
    public static let letter = CGSize(width: 612, height: 792)

    public func build(_ document: ScanDocument) throws -> PDFExport {
        guard !document.pages.isEmpty else { throw PDFExportError.noPages }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw PDFExportError.contextUnavailable }
        var mediaBox = CGRect(origin: .zero, size: Self.letter)
        let info = [kCGPDFContextTitle: document.title, kCGPDFContextCreator: "Scanner"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else {
            throw PDFExportError.contextUnavailable
        }

        for page in document.pages {
            // Decode → encode → draw one page at a time; the decoded original is released before the next page.
            let encoded = try ImageEncoder.jpeg(try page.loadOriginal(), preset: preset)
            let size = Self.pageSize(fitting: encoded.pixelSize)
            var box = CGRect(origin: .zero, size: size)
            let boxData = withUnsafeBytes(of: &box) { Data($0) }
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.draw(encoded.image, in: box)
            if includesTextLayer, let recognition = page.recognition {
                Self.drawInvisibleText(recognition.words, pageSize: size, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return PDFExport(data: data as Data, pageCount: document.pages.count)
    }

    /// Points for a page whose capture has the given pixel size.
    public static func pageSize(fitting pixels: CGSize) -> CGSize {
        let landscape = pixels.width > pixels.height
        let bounds = landscape ? CGSize(width: letter.height, height: letter.width) : letter
        let scale = min(bounds.width / pixels.width, bounds.height / pixels.height)
        return CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
    }

    /// Each word is set at a font size whose ascent+descent equals the box height, then stretched
    /// horizontally to the box width, so selection highlights line up with the printed word.
    static func drawInvisibleText(_ words: [RecognizedWord], pageSize: CGSize, in context: CGContext) {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let probeSize: CGFloat = 10
        let probeFont = CTFontCreateWithName("Helvetica" as CFString, probeSize, nil)

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for word in words where !word.text.isEmpty {
            let rect = CGRect(
                x: word.box.minX * pageSize.width,
                y: word.box.minY * pageSize.height,
                width: word.box.width * pageSize.width,
                height: word.box.height * pageSize.height
            )
            guard rect.width > 0, rect.height > 0 else { continue }

            var ascent: CGFloat = 0, descent: CGFloat = 0
            let probe = CTLineCreateWithAttributedString(NSAttributedString(string: word.text, attributes: [fontKey: probeFont]))
            _ = CTLineGetTypographicBounds(probe, &ascent, &descent, nil)
            let probeHeight = ascent + descent
            guard probeHeight > 0 else { continue }

            let font = CTFontCreateWithName("Helvetica" as CFString, probeSize * rect.height / probeHeight, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: word.text, attributes: [fontKey: font]))
            var lineDescent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, &lineDescent, nil))
            let horizontalScale = width > 0 ? rect.width / width : 1

            context.textMatrix = CGAffineTransform(scaleX: horizontalScale, y: 1)
            context.textPosition = CGPoint(x: rect.minX, y: rect.minY + lineDescent)
            CTLineDraw(line, context)
        }
        context.textMatrix = .identity
        context.restoreGState()
    }
}
