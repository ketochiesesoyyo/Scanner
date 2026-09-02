import Foundation

/// Per-page quality metrics (PRD QLT-01). Raw measurements are stored; whether each one warrants a
/// warning is decided against `QualityThresholds`, so thresholds can be tuned without re-scanning.
public struct PageQuality: Sendable, Codable, Hashable {
    /// Variance of the Laplacian of luma — higher is sharper.
    public let blurVariance: Double
    /// Fraction of clipped-highlight pixels (luma ≥ 250).
    public let glareRatio: Double
    /// Spread between the brightest and darkest paper regions, 0…1.
    public let shadowSpread: Double
    /// Share of OCR words below the confidence floor; nil when the page has no recognition yet.
    public let lowConfidenceShare: Double?
    /// iOS 26 lens-smudge confidence, when available.
    public let smudgeConfidence: Double?

    public init(blurVariance: Double, glareRatio: Double, shadowSpread: Double, lowConfidenceShare: Double?, smudgeConfidence: Double?) {
        self.blurVariance = blurVariance
        self.glareRatio = glareRatio
        self.shadowSpread = shadowSpread
        self.lowConfidenceShare = lowConfidenceShare
        self.smudgeConfidence = smudgeConfidence
    }
}

/// Defaults tuned on the rendered fixture corpus (M2.2). Per-document-class thresholds come with the
/// real corpus in M3+, once capture supplies quads and real lighting.
public struct QualityThresholds: Sendable, Codable, Hashable {
    public var minBlurVariance: Double = 25
    public var maxGlareRatio: Double = 0.04
    public var maxShadowSpread: Double = 0.22
    public var maxLowConfidenceShare: Double = 0.25
    public var maxSmudgeConfidence: Double = 0.8
    public var maxDuplicateDistance: Double = 0.1
    /// dHash fallback cutoff when the neural feature print is unavailable. Deliberately strict:
    /// exact re-imports hash identically (0), while two different text pages measured as close as 5.
    public var maxDuplicateHamming: Int = 2

    public init() {}
    public static let standard = QualityThresholds()
}

/// A problem worth telling the user about. Warnings warn — they never delete, reorder, or block (QLT-02).
public enum ScanWarning: Sendable, Codable, Hashable {
    case blur(pageIndex: Int)
    case glare(pageIndex: Int)
    case shadow(pageIndex: Int)
    case readability(pageIndex: Int)
    case smudge(pageIndex: Int)
    case possibleDuplicate(pageIndex: Int, duplicateOf: Int)
    case missingPages(numbers: [Int])
    case outOfOrder(pageIndex: Int)

    /// Stable identity for ignore-tracking across re-verification.
    public var key: String {
        switch self {
        case .blur(let index): "blur:\(index)"
        case .glare(let index): "glare:\(index)"
        case .shadow(let index): "shadow:\(index)"
        case .readability(let index): "readability:\(index)"
        case .smudge(let index): "smudge:\(index)"
        case .possibleDuplicate(let index, let original): "duplicate:\(original)-\(index)"
        case .missingPages(let numbers): "missing:\(numbers.map(String.init).joined(separator: ","))"
        case .outOfOrder(let index): "order:\(index)"
        }
    }

    /// The page the warning points at, when it points at one.
    public var pageIndex: Int? {
        switch self {
        case .blur(let index), .glare(let index), .shadow(let index), .readability(let index),
             .smudge(let index), .possibleDuplicate(let index, _), .outOfOrder(let index):
            index
        case .missingPages:
            nil
        }
    }
}

public struct VerificationResult: Sendable, Codable {
    /// The record's `contentRevision` when this was computed; a mismatch means it's stale.
    public let contentRevision: Int
    /// By page order.
    public let pageQualities: [PageQuality]
    public let warnings: [ScanWarning]

    public init(contentRevision: Int, pageQualities: [PageQuality], warnings: [ScanWarning]) {
        self.contentRevision = contentRevision
        self.pageQualities = pageQualities
        self.warnings = warnings
    }
}

/// What kind of document this is (PRD CLS-01). Mexico-first, matching the launch segment.
public enum DocumentKind: String, Sendable, Codable, CaseIterable {
    case factura, recibo, comprobanteDomicilio, estadoCuenta, identificacion, actaNacimiento
    case contrato, formulario, carta, unknown

    public var displayName: String {
        switch self {
        case .factura: "Factura"
        case .recibo: "Recibo"
        case .comprobanteDomicilio: "Comprobante de domicilio"
        case .estadoCuenta: "Estado de cuenta"
        case .identificacion: "Identificación"
        case .actaNacimiento: "Acta de nacimiento"
        case .contrato: "Contrato"
        case .formulario: "Formulario"
        case .carta: "Carta"
        case .unknown: "Documento"
        }
    }
}

/// A suggestion, never a decision: the user can always override (CLS-01 acceptance).
public struct ClassificationResult: Sendable, Codable {
    public let kind: DocumentKind
    /// Heuristic 0…1 — from rule weights, not a calibrated probability.
    public let confidence: Double
    /// Issuer / vendor / counterparty guess from the top of the document.
    public let party: String?
    /// Document date found in the text (not the scan date).
    public let date: Date?

    public init(kind: DocumentKind, confidence: Double, party: String?, date: Date?) {
        self.kind = kind
        self.confidence = confidence
        self.party = party
        self.date = date
    }

    /// "{kind} – {party} – {yyyy-MM-dd}", or nil when there's nothing better than the default title.
    public func suggestedTitle(fallbackDate: Date) -> String? {
        guard kind != .unknown else { return nil }
        var parts = [kind.displayName]
        if let party { parts.append(party) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        parts.append(formatter.string(from: date ?? fallbackDate))
        return parts.joined(separator: " – ")
    }
}
