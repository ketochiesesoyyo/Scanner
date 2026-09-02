import Foundation
import ScannerCore

/// Rule-based, on-device, Mexico-first document classification (PRD CLS-01). Output is a suggestion
/// with a visible confidence — never a forced action. A Create ML text classifier replaces the rules
/// once the consented corpus exists (roadmap M2.7 note).
public struct DocumentClassifier: Sendable {
    public init() {}

    /// Patterns are matched against folded text (lowercased, diacritics stripped, whitespace collapsed,
    /// padded with spaces) — so short tokens are written with surrounding spaces to get word boundaries.
    static let rules: [(kind: DocumentKind, weight: Int, pattern: String)] = [
        (.comprobanteDomicilio, 4, "comprobante de domicilio"),
        (.comprobanteDomicilio, 2, " cfe "), (.comprobanteDomicilio, 2, "comision federal de electricidad"),
        (.comprobanteDomicilio, 2, "suministrador"), (.comprobanteDomicilio, 2, " kwh "),
        (.comprobanteDomicilio, 2, " telmex "), (.comprobanteDomicilio, 2, " izzi "), (.comprobanteDomicilio, 2, " totalplay "),
        (.factura, 4, " cfdi "), (.factura, 3, " factura"), (.factura, 2, "uso de cfdi"), (.factura, 2, "folio fiscal"),
        (.factura, 2, "subtotal"), (.factura, 1, " iva "), (.factura, 3, " invoice "),
        (.recibo, 3, " recibo "), (.recibo, 3, "recibo de nomina"), (.recibo, 3, " receipt "),
        (.recibo, 2, " efectivo "), (.recibo, 2, " cambio "), (.recibo, 1, " total "),
        (.estadoCuenta, 4, "estado de cuenta"), (.estadoCuenta, 2, " saldo "), (.estadoCuenta, 2, "movimientos"),
        (.estadoCuenta, 3, " statement "),
        (.identificacion, 4, "instituto nacional electoral"), (.identificacion, 3, "credencial para votar"),
        (.identificacion, 3, " curp "), (.identificacion, 2, " pasaporte "), (.identificacion, 2, "licencia de conducir"),
        (.identificacion, 2, " passport "), (.identificacion, 2, " ine "),
        (.actaNacimiento, 5, "acta de nacimiento"), (.actaNacimiento, 3, "registro civil"),
        (.contrato, 4, " contrato"), (.contrato, 3, "clausula"), (.contrato, 2, "las partes"),
        (.contrato, 2, "arrendamiento"), (.contrato, 3, " agreement "), (.contrato, 1, " clause "),
        (.formulario, 3, " solicitud"), (.formulario, 3, "formulario"), (.formulario, 2, "firma del solicitante"),
        (.formulario, 1, " form "),
        (.carta, 2, " estimado"), (.carta, 2, "atentamente"), (.carta, 2, " dear "), (.carta, 2, " sincerely "),
    ]

    /// Class headers that shouldn't be mistaken for the issuing party.
    static let headerPrefixes = [
        "comprobante de domicilio", "estado de cuenta", "acta de nacimiento", "factura", "recibo",
        "contrato", "solicitud", "formulario", "instituto nacional electoral", "credencial para votar",
        "pagina", "page", "invoice", "receipt", "statement", "agreement",
    ]

    public func classify(text: String, referenceDate: Date = .now) -> ClassificationResult {
        let folded = Self.fold(text)
        var scores: [DocumentKind: Int] = [:]
        for rule in Self.rules where folded.contains(rule.pattern) {
            scores[rule.kind, default: 0] += rule.weight
        }
        let party = Self.party(in: text)
        let date = Self.date(in: text, folded: folded, reference: referenceDate)
        let best = scores.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }.first
        guard let best, best.value >= 3 else {
            return ClassificationResult(kind: .unknown, confidence: 0, party: party, date: date)
        }
        return ClassificationResult(kind: best.key, confidence: min(1, Double(best.value) / 8), party: party, date: date)
    }

    /// Lowercase, strip diacritics, collapse whitespace, pad — gives cheap word-boundary matching.
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_MX"))
        return " " + folded.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() + " "
    }

    /// The issuer is usually one of the first lines that isn't a class header or a number.
    static func party(in text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for line in lines.prefix(4) {
            let folded = fold(line).trimmingCharacters(in: .whitespaces)
            if headerPrefixes.contains(where: { folded.hasPrefix($0) }) { continue }
            guard line.count >= 3, line.count <= 48, line.rangeOfCharacter(from: .letters) != nil else { continue }
            let digits = line.filter(\.isNumber).count
            guard digits * 2 < line.count else { continue }
            return line
        }
        return nil
    }

    // MARK: Document date (the date *on* the document, not the scan date)

    static let spanishMonths = ["enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
                                "julio": 7, "agosto": 8, "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12]
    static let spanishDatePattern = try! NSRegularExpression(
        pattern: #"(\d{1,2})\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\s+de)?\s+(\d{4})"#
    )
    static let numericDatePattern = try! NSRegularExpression(pattern: #"\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b"#)

    static func date(in text: String, folded: String, reference: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        func plausible(_ date: Date?) -> Date? {
            guard let date,
                  date > reference.addingTimeInterval(-10 * 365 * 86_400),
                  date < reference.addingTimeInterval(2 * 365 * 86_400) else { return nil }
            return date
        }

        let range = NSRange(folded.startIndex..., in: folded)
        if let match = spanishDatePattern.firstMatch(in: folded, range: range),
           let dayRange = Range(match.range(at: 1), in: folded), let monthRange = Range(match.range(at: 2), in: folded),
           let yearRange = Range(match.range(at: 3), in: folded),
           let day = Int(folded[dayRange]), let month = spanishMonths[String(folded[monthRange])], let year = Int(folded[yearRange]),
           let date = plausible(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))) {
            return date
        }
        // Mexico reads dd/mm/yyyy.
        if let match = numericDatePattern.firstMatch(in: folded, range: range),
           let dayRange = Range(match.range(at: 1), in: folded), let monthRange = Range(match.range(at: 2), in: folded),
           let yearRange = Range(match.range(at: 3), in: folded),
           let day = Int(folded[dayRange]), let month = Int(folded[monthRange]), let year = Int(folded[yearRange]),
           month >= 1, month <= 12, day >= 1, day <= 31,
           let date = plausible(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))) {
            return date
        }
        // Fall back to the system detector for everything else (English formats etc.).
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let textRange = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: textRange) {
                if let date = plausible(match.date) { return date }
            }
        }
        return nil
    }
}
