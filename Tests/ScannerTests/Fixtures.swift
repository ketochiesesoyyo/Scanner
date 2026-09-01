import CoreGraphics
import CoreText
import Foundation
import ScannerCore

/// Rendered test pages. Real user documents never enter the test suite (PRD §14: consented corpus only).
enum Fixtures {
    /// A white "page" with left-aligned black Helvetica lines, top to bottom.
    static func page(lines: [String], size: CGSize = CGSize(width: 1240, height: 1754), fontSize: CGFloat = 56) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        var baseline = size.height - 200
        for line in lines {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            context.textPosition = CGPoint(x: 120, y: baseline)
            CTLineDraw(ctLine, context)
            baseline -= fontSize * 1.8
        }
        return context.makeImage()!
    }

    static func document(pages: [ScanPage]) -> ScanDocument {
        ScanDocument(title: "Fixture", pages: pages, source: .files)
    }
}
