import Foundation
import CoreGraphics
import Observation
import ScannerCore
import Recognition
import Export
import Telemetry

/// The in-progress scan: pages, per-page OCR status, and export. M1 moves persistence into ScannerCore
/// (write-ahead session store, library); this model then becomes a thin view of it.
@MainActor @Observable
final class ScanSessionModel {
    enum PageStatus: Equatable {
        case queued, recognizing, done(ConfidenceBand), failed
    }

    enum Failure: LocalizedError {
        case noDocument
        var errorDescription: String? {
            switch self {
            case .noDocument: "There is no scan to export."
            }
        }
    }

    private(set) var document: ScanDocument?
    private(set) var status: [UUID: PageStatus] = [:]
    var isExporting = false
    var errorMessage: String?

    private var recognitionTask: Task<Void, Never>?
    private let recognizer = TextRecognizer()

    var isRecognizing: Bool {
        status.values.contains { $0 == .queued || $0 == .recognizing }
    }

    var recognizedPageCount: Int {
        status.values.filter { if case .done = $0 { true } else { false } }.count
    }

    func start(with images: [CGImage], source: CaptureSource) {
        recognitionTask?.cancel()
        let pages = images.map { ScanPage(original: $0) }
        document = ScanDocument(title: Self.defaultTitle(), pages: pages, source: source)
        status = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, PageStatus.queued) })

        Telemetry.record(.scanSessionStarted(entryPoint: .app, proposedMode: .document))
        let method: TelemetryEvent.CaptureMethod = source == .documentCamera ? .auto : .imported
        for _ in pages {
            Telemetry.record(.pageCaptured(method: method, mode: .document, qualityBand: nil, processingLatencyMs: 0))
        }

        recognitionTask = Task { await recognizeAll(pages) }
    }

    func reset() {
        recognitionTask?.cancel()
        document = nil
        status = [:]
    }

    /// Builds the PDF off the main actor and writes it to a protected temp file for the share sheet.
    func exportPDF(preset: ExportPreset) async throws -> URL {
        guard let document else { throw Failure.noDocument }
        isExporting = true
        defer { isExporting = false }

        let builder = SearchablePDFBuilder(preset: preset)
        let export = try await Task.detached(priority: .userInitiated) { try builder.build(document) }.value

        let url = try Self.exportsDirectory()
            .appendingPathComponent(Self.fileName(for: document))
            .appendingPathExtension("pdf")
        try export.data.write(to: url, options: [.atomic, .completeFileProtection])

        Telemetry.record(.exportCompleted(
            format: document.isFullyRecognized ? .searchablePDF : .pdf,
            pageCountBand: .init(export.pageCount),
            sizeBand: .init(bytes: export.byteCount),
            destination: .shareSheet
        ))
        return url
    }

    // MARK: - Recognition

    private func recognizeAll(_ pages: [ScanPage]) async {
        for page in pages {
            guard !Task.isCancelled else { return }
            status[page.id] = .recognizing
            do {
                let result = try await recognizer.recognize(page.original)
                apply(result, to: page.id)
            } catch {
                status[page.id] = .failed
            }
        }
    }

    private func apply(_ result: PageRecognition, to id: UUID) {
        guard var updated = document, let index = updated.pages.firstIndex(where: { $0.id == id }) else { return }
        updated.pages[index].recognition = result
        document = updated
        status[id] = .done(result.confidenceBand)

        Telemetry.record(.ocrCompleted(
            language: .es,
            documentClass: .unknown,
            confidence: TelemetryEvent.Band(rawValue: result.confidenceBand.rawValue) ?? .low,
            latencyMs: Int(result.duration / .milliseconds(1))
        ))
    }

    // MARK: - Naming (M2 replaces this with classification-driven suggestions)

    private static func defaultTitle() -> String {
        "Scan \(Date.now.formatted(date: .abbreviated, time: .shortened))"
    }

    private static func fileName(for document: ScanDocument) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Scan-\(formatter.string(from: document.createdAt))"
    }

    private static func exportsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
