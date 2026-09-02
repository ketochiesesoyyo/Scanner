import Foundation
import CoreGraphics

/// Renders PDF pages to bitmaps so a PDF from Files can enter the same pipeline as a scan.
/// CoreGraphics only (thread-safe, no UIKit) — safe inside detached ingest tasks.
public enum PDFRasterizer {
    public enum Failure: Error {
        case unreadable, pageOutOfRange
    }

    public static func pageCount(of data: Data) -> Int? {
        guard let document = document(from: data) else { return nil }
        return document.numberOfPages
    }

    /// One page as an opaque sRGB bitmap; `longSide` 2480 ≈ 300 dpi for a letter page.
    /// Note: born-digital PDFs are rasterized and re-OCR'd — their embedded text layer is not reused (yet).
    public static func image(from data: Data, pageIndex: Int, longSide: Int = 2480) throws -> CGImage {
        guard let document = document(from: data) else { throw Failure.unreadable }
        guard pageIndex >= 0, pageIndex < document.numberOfPages, let page = document.page(at: pageIndex + 1) else {
            throw Failure.pageOutOfRange
        }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { throw Failure.unreadable }
        let rotated = abs(page.rotationAngle) % 180 == 90
        let pageSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = CGFloat(longSide) / max(pageSize.width, pageSize.height)
        let width = max(1, Int((pageSize.width * scale).rounded()))
        let height = max(1, Int((pageSize.height * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { throw Failure.unreadable }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        // Handles rotation, scaling and origin in one go.
        let transform = page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw Failure.unreadable }
        return image
    }

    private static func document(from data: Data) -> CGPDFDocument? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGPDFDocument(provider)
    }
}
