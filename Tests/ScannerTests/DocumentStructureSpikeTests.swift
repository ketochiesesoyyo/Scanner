import Testing
import CoreGraphics
import Vision
import Recognition

/// M2.8 spike: what does iOS 26's RecognizeDocumentsRequest add over RecognizeTextRequest?
/// Findings go into docs/roadmap.md → Learnings. Runs only where the API exists.
struct DocumentStructureSpikeTests {
    @Test func structureRequestReadsTextAndTiming() async throws {
        guard #available(iOS 26.0, *) else { return }
        let image = Fixtures.page(lines: ["FACTURA CFDI", "Subtotal $100.00", "IVA $16.00", "Total $116.00"])
        let clock = ContinuousClock()

        var start = clock.now
        let documents = try await RecognizeDocumentsRequest().perform(on: image)
        let structureTime = clock.now - start

        start = clock.now
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        _ = try await textRequest.perform(on: image)
        let textTime = clock.now - start

        let observation = try #require(documents.first)
        let transcript = observation.document.text.transcript
        print("SPIKE RecognizeDocumentsRequest: transcript=\(transcript.count) chars, tables=\(observation.document.tables.count), paragraphs=\(observation.document.paragraphs.count), lists=\(observation.document.lists.count), time=\(structureTime) vs RecognizeTextRequest=\(textTime)")
        #expect(transcript.localizedCaseInsensitiveContains("FACTURA"))
    }
}
