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
        // Off-white paper (~224 luma): real captures meter below clipping; glare is what clips.
        context.setFillColor(CGColor(red: 0.88, green: 0.88, blue: 0.87, alpha: 1))
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

    /// Softens the page like camera shake: downscale hard, then upscale.
    static func blurred(_ image: CGImage, factor: Int = 8) -> CGImage {
        let smallW = max(1, image.width / factor), smallH = max(1, image.height / factor)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let small = CGContext(data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        let big = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        big.interpolationQuality = .high
        big.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return big.makeImage()!
    }

    /// A clipped specular blob over ~15% of the page.
    static func withGlare(_ image: CGImage) -> CGImage {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let radius = CGFloat(image.width) * 0.22
        let center = CGPoint(x: CGFloat(image.width) * 0.5, y: CGFloat(image.height) * 0.65)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return context.makeImage()!
    }

    /// A hard lighting gradient across the left half of the page.
    static func withShadow(_ image: CGImage) -> CGImage {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let colors = [CGColor(gray: 0, alpha: 0.55), CGColor(gray: 0, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: CGFloat(image.width) * 0.55, y: 0), options: [])
        return context.makeImage()!
    }

    static func document(pages: [ScanPage]) -> ScanDocument {
        ScanDocument(title: "Fixture", pages: pages, source: .files)
    }
}
