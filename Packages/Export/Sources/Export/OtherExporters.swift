import Foundation
import ScannerCore
import ImagePipeline

/// One JPEG per page at the preset's size/quality (PRD EXP-01).
public struct JPEGExporter: Sendable {
    public var preset: ExportPreset
    public init(preset: ExportPreset = .standard) { self.preset = preset }

    public func export(_ document: ScanDocument) throws -> [Data] {
        try document.pages.map { try ImageEncoder.jpeg(try $0.loadOriginal(), preset: preset).data }
    }
}

/// Plain text of everything that was recognized, pages separated by a blank line (PRD EXP-01).
public enum TextExporter {
    public static func text(_ document: ScanDocument) -> String {
        document.pages.enumerated().map { index, page in
            let body = page.recognition?.text ?? ""
            return document.pages.count > 1 ? "— Page \(index + 1) —\n\(body)" : body
        }
        .joined(separator: "\n\n")
    }
}

public enum ExportFileName {
    /// A filesystem-safe base name from a user-facing title ("Scan 31 Aug 2026, 22:41" → "Scan-31-Aug-2026-22-41").
    public static func base(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = ""
        var lastDash = false
        for scalar in title.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "Scan" : trimmed
    }
}
