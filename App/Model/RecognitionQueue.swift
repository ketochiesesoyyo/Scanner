import Foundation
import Observation
import ScannerCore
import Recognition
import Telemetry

/// Runs OCR for pages that don't have it yet, one page at a time per scan, off the main actor.
/// It always re-reads the current record from the library (records are value snapshots), so results
/// saved mid-run are picked up and a kill mid-way resumes where it stopped (`resumePending`).
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

    func isBusy(_ scanID: UUID) -> Bool { tasks[scanID] != nil }

    func process(_ scanID: UUID) {
        guard tasks[scanID] == nil else { return }
        tasks[scanID] = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let record = library.record(id: scanID),
                      let page = record.orderedPages.first(where: { !$0.isRecognized && !failed.contains($0.id) }) else { break }
                await recognize(page, inScan: scanID)
            }
            await verifyIfNeeded(scanID)
            tasks[scanID] = nil
        }
    }

    /// Pages left without text by an earlier run (app killed while reading).
    func resumePending() {
        for record in library.allRecords() where record.state == .ready && !record.isFullyRecognized {
            process(record.id)
        }
    }

    func retry(pageID: UUID, inScan scanID: UUID) {
        failed.remove(pageID)
        process(scanID)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        inFlight = []
    }

    /// Quality gate + classification (QLT-01/02, CLS-01), after OCR settles. Best-effort.
    private func verifyIfNeeded(_ scanID: UUID) async {
        guard let record = library.record(id: scanID),
              record.state == .ready, !record.pages.isEmpty, record.isVerificationStale, !Task.isCancelled else { return }
        let snapshot = library.snapshot(record)
        let revision = record.contentRevision
        let createdAt = record.createdAt
        let verifier = DocumentVerifier()
        let classifier = DocumentClassifier()
        #if DEBUG
        print("PHASE verify start: \(record.pages.count) page(s)")
        #endif
        do {
            let (verification, classification) = try await Task.detached(priority: .utility) {
                let verification = try await verifier.verify(snapshot, contentRevision: revision)
                let classification = classifier.classify(text: snapshot.recognizedText, referenceDate: createdAt)
                return (verification, classification)
            }.value
            #if DEBUG
            print("PHASE verify done: \(verification.warnings.count) warning(s)")
            #endif
            guard library.record(id: scanID)?.contentRevision == revision else { return } // pages changed; next run redoes it
            try library.setVerification(verification, forScan: scanID)
            try library.setClassification(classification, forScan: scanID)
            let ignored = library.record(id: scanID)?.ignoredWarningKeys ?? []
            for warning in verification.warnings where !ignored.contains(warning.key) {
                Telemetry.record(.qualityWarningShown(type: warning.telemetryType, confidence: .medium, pageIndex: warning.pageIndex ?? 0))
            }
        } catch {
            #if DEBUG
            print("PHASE verify FAILED: \(error)")
            #endif
        }
    }

    private func recognize(_ page: PageRecord, inScan scanID: UUID) async {
        inFlight.insert(page.id)
        defer { inFlight.remove(page.id) }
        let url = library.files.url(for: page.originalPath)
        let recognizer = recognizer
        #if DEBUG
        print("PHASE ocr start: page \(page.index)")
        #endif
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await recognizer.recognize(try ImageDecoder.image(at: url))
            }.value
            try library.setRecognition(result, forPage: page.id, inScan: scanID)
            Telemetry.record(.ocrCompleted(
                language: .es,
                documentClass: .unknown,
                confidence: TelemetryEvent.Band(rawValue: result.confidenceBand.rawValue) ?? .low,
                latencyMs: Int(result.duration / .milliseconds(1))
            ))
        } catch {
            #if DEBUG
            print("PHASE ocr FAILED: page \(page.index): \(error)")
            #endif
            failed.insert(page.id)
        }
    }
}
