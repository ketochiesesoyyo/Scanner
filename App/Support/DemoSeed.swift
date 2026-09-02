#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ScannerCore
import ImagePipeline

/// Launch with `-seedDemoScan` (Xcode scheme argument or `simctl launch ... -seedDemoScan`) to get a
/// two-page rendered scan in the library — for screenshots and manual testing on the Simulator, which
/// has no camera. Never compiled into release builds.
@MainActor
enum DemoSeed {
    static let argument = "-seedDemoScan"

    static func runIfRequested(library: Library, queue: RecognitionQueue) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        Task { await seed(library: library, queue: queue) }
    }

    private static func seed(library: Library, queue: RecognitionQueue) async {
        guard ((try? library.allRecords()) ?? []).isEmpty else { return }
        do {
            // No title: lets the classifier's suggestion chip show. Pages are crafted so the
            // verification summary has something to say: page 2 of 3 missing, page 3 a duplicate.
            let record = try library.createDraft(source: .files)
            let pageOne = ["COMPROBANTE DE DOMICILIO", "CFE Suministrador de Servicios Básicos", "Página 1 de 3", "Fecha: 15 de julio de 2026", "Total a pagar: $1,234.56"]
            let pages = [
                pageOne,
                ["Página 3 de 3", "Dirección: Av. Insurgentes Sur 1602", "Ciudad de México, 03940", "RFC: XAXX010101000"],
                pageOne,
            ]
            for lines in pages {
                try await library.addPage(try PageIngest.prepare(image: render(lines)), to: record)
            }
            try library.finishCapture(record)
            queue.process(record.id)
        } catch {
            assertionFailure("Demo seed failed: \(error)")
        }
    }

    private static func render(_ lines: [String], size: CGSize = CGSize(width: 1240, height: 1754)) -> CGImage {
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.88, green: 0.88, blue: 0.87, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
        ]
        var baseline = size.height - 220
        for line in lines {
            context.textPosition = CGPoint(x: 120, y: baseline)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes)), context)
            baseline -= 96
        }
        return context.makeImage()!
    }
}
#endif
