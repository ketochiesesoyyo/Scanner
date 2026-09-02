import Testing
import Foundation
import ScannerCore
import Recognition

/// M2.5/M2.6: ≥80% on the labeled corpus; suggestions carry party and document date.
struct ClassifierTests {
    /// Rendered-text corpus (M2.7): no real documents, Spanish-first with English coverage.
    static let corpus: [(text: String, expected: DocumentKind)] = [
        ("COMPROBANTE DE DOMICILIO\nCFE Suministrador de Servicios Básicos\nPeriodo: julio 2026\nConsumo 250 kWh", .comprobanteDomicilio),
        ("Telmex\nRecibo de servicio telefónico\nComprobante de domicilio\nTotal a pagar $499.00", .comprobanteDomicilio),
        ("izzi\nComprobante de domicilio\nInternet 100 Mbps\nPeriodo agosto 2026", .comprobanteDomicilio),
        ("FACTURA\nCFDI de ingreso\nFolio fiscal: 8A3B-...\nSubtotal $1,000.00\nIVA $160.00\nUso de CFDI: G03", .factura),
        ("Distribuidora del Norte SA de CV\nFactura A-4521\nSubtotal $5,200.00\nIVA $832.00", .factura),
        ("INVOICE\nAcme Corp\nInvoice #2231\nSubtotal $300.00\nAmount due $348.00", .factura),
        ("OXXO\nRecibo de compra\nTotal $187.50\nEfectivo $200.00\nCambio $12.50", .recibo),
        ("Recibo de nómina\nPeriodo 01/08/2026 - 15/08/2026\nPercepciones $12,000.00", .recibo),
        ("RECEIPT\nCoffee House\nTotal $8.50\nCash $10.00\nChange $1.50", .recibo),
        ("BBVA\nEstado de cuenta\nSaldo anterior $10,250.00\nMovimientos del periodo", .estadoCuenta),
        ("Bank Statement\nAccount 1234\nStatement period Aug 2026\nClosing balance $2,400.00", .estadoCuenta),
        ("Instituto Nacional Electoral\nCredencial para votar\nCURP: GOMC900101HDFLNS09", .identificacion),
        ("Pasaporte\nEstados Unidos Mexicanos\nCURP: XEXX010101MNEXXXA8", .identificacion),
        ("Licencia de conducir\nCiudad de México\nVigencia 2028", .identificacion),
        ("ACTA DE NACIMIENTO\nRegistro Civil\nEntidad: Jalisco", .actaNacimiento),
        ("Estados Unidos Mexicanos\nRegistro Civil\nActa de nacimiento certificada", .actaNacimiento),
        ("CONTRATO DE ARRENDAMIENTO\nLas partes convienen la siguiente cláusula primera", .contrato),
        ("Contrato de prestación de servicios\nCláusula segunda: honorarios", .contrato),
        ("SERVICE AGREEMENT\nThis agreement is made between the parties\nClause 1: Services", .contrato),
        ("Solicitud de beca\nFormulario 22-B\nFirma del solicitante", .formulario),
        ("Application Form\nPlease fill out this form in block letters", .formulario),
        ("Estimado señor García:\nLe escribo para confirmar nuestra cita.\nAtentamente,\nLuis", .carta),
        ("Dear Ms. Smith,\nThank you for your time last week.\nSincerely,\nJohn", .carta),
        ("Lista del súper\nmanzanas\ntortillas\njabón", .unknown),
    ]

    @Test func corpusAccuracyIsAtLeastEightyPercent() {
        let classifier = DocumentClassifier()
        var misses: [String] = []
        for sample in Self.corpus {
            let got = classifier.classify(text: sample.text).kind
            if got != sample.expected {
                misses.append("\(sample.text.prefix(28))… expected \(sample.expected) got \(got)")
            }
        }
        let accuracy = Double(Self.corpus.count - misses.count) / Double(Self.corpus.count)
        #expect(accuracy >= 0.8, "accuracy \(accuracy): \(misses.joined(separator: " | "))")
    }

    @Test func suggestionCarriesKindPartyAndDocumentDate() {
        let result = DocumentClassifier().classify(
            text: "COMPROBANTE DE DOMICILIO\nCFE Suministrador de Servicios Básicos\nFecha: 15 de julio de 2026\nTotal a pagar: $1,234.56",
            referenceDate: ISO8601DateFormatter().date(from: "2026-08-31T12:00:00Z")!
        )
        #expect(result.kind == .comprobanteDomicilio)
        #expect(result.party == "CFE Suministrador de Servicios Básicos")
        let title = result.suggestedTitle(fallbackDate: .now)
        #expect(title == "Comprobante de domicilio – CFE Suministrador de Servicios Básicos – 2026-07-15", "\(title ?? "nil")")
    }

    @Test func unknownYieldsNoSuggestion() {
        let result = DocumentClassifier().classify(text: "hola\nqué tal")
        #expect(result.kind == .unknown)
        #expect(result.suggestedTitle(fallbackDate: .now) == nil)
    }

    @Test func numericDatesReadAsDayMonthYear() {
        let result = DocumentClassifier().classify(
            text: "Recibo de nómina\nFecha de pago: 05/08/2026",
            referenceDate: ISO8601DateFormatter().date(from: "2026-08-31T12:00:00Z")!
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(result.date.map(formatter.string(from:)) == "2026-08-05")
    }
}
