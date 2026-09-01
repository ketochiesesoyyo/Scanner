import Foundation
import Observation
import ScannerCore
import Recognition
import Telemetry

/// Runs OCR for pages that don't have it yet, one page at a time per record, off the main actor.
/// Results are saved as they land, so a kill mid-way resumes where it stopped (`resumePending`).
@MainActor @Observable
final class RecognitionQueue {
    private(set) var inFlight: Set<UUID> = []
    private(set) var failed: Set<UUID> = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let library: Library
    private let recognizer = TextRecognizer()

    init(library: Library) {
        self.library = library
    }

    func isBusy(_ record: ScanRecord) -> Bool { tasks[record.id] != nil }

    func process(_ record: ScanRecord) {
        guard tasks[record.id] == nil else { return }
        let recordID = record.id
        tasks[recordID] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Recomputed each round so pages added while we're reading are picked up too.
                guard let page = record.orderedPages.first(where: { $0.recognitionData == nil && !failed.contains($0.id) }) else { break }
                await recognize(page)
            }
            tasks[recordID] = nil
        }
    }

    /// Pages left without text by an earlier run (app killed while reading).
    func resumePending() {
        for record in (try? library.allRecords()) ?? [] where record.state == .ready && !record.isFullyRecognized {
            process(record)
        }
    }

    func retry(_ page: PageRecord) {
        failed.remove(page.id)
        if let record = page.document { process(record) }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        inFlight = []
    }

    private func recognize(_ page: PageRecord) async {
        inFlight.insert(page.id)
        defer { inFlight.remove(page.id) }
        let url = library.files.url(for: page.originalPath)
        let recognizer = recognizer
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await recognizer.recognize(try ImageDecoder.image(at: url))
            }.value
            try library.setRecognition(result, for: page)
            Telemetry.record(.ocrCompleted(
                language: .es,
                documentClass: .unknown,
                confidence: TelemetryEvent.Band(rawValue: result.confidenceBand.rawValue) ?? .low,
                latencyMs: Int(result.duration / .milliseconds(1))
            ))
        } catch {
            failed.insert(page.id)
        }
    }
}
