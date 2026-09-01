import Foundation
import CoreGraphics
import Observation
import PhotosUI
import SwiftUI
import ScannerCore
import ImagePipeline
import Telemetry

/// Drives one capture flow (camera or Photos) and writes pages into the library as they arrive.
@MainActor @Observable
final class CaptureCoordinator {
    enum Item: Sendable {
        case bitmap(CGImage)
        case file(Data)

        func prepare() throws -> PageAssets {
            switch self {
            case .bitmap(let image): try PageIngest.prepare(image: image)
            case .file(let data): try PageIngest.prepare(imageData: data)
            }
        }
    }

    var showingCamera = false
    var showingPhotoPicker = false
    var pickerItems: [PhotosPickerItem] = []
    private(set) var isWorking = false
    private(set) var progress: String?
    var errorMessage: String?

    /// Write-ahead: each page is persisted before the next one is prepared. If this is interrupted,
    /// the draft stays in `.capturing` and shows up as a recoverable scan on the next launch.
    func ingest(_ items: [Item], source: CaptureSource, into existing: ScanRecord?, library: Library, queue: RecognitionQueue) async -> ScanRecord? {
        guard !items.isEmpty else { return nil }
        isWorking = true
        defer {
            isWorking = false
            progress = nil
        }
        do {
            let record: ScanRecord
            if let existing {
                record = existing
            } else {
                record = try library.createDraft(source: source)
                Telemetry.record(.scanSessionStarted(entryPoint: .app, proposedMode: .document))
            }
            let method: TelemetryEvent.CaptureMethod = source == .documentCamera ? .auto : .imported
            for (index, item) in items.enumerated() {
                progress = items.count > 1 ? "Saving page \(index + 1) of \(items.count)…" : "Saving page…"
                let assets = try await Task.detached(priority: .userInitiated) { try item.prepare() }.value
                try library.addPage(assets, to: record)
                Telemetry.record(.pageCaptured(method: method, mode: .document, qualityBand: nil, processingLatencyMs: 0))
            }
            try library.finishCapture(record)
            queue.process(record)
            return record
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func loadPickerItems(_ items: [PhotosPickerItem]) async -> [Item] {
        var loaded: [Item] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { loaded.append(.file(data)) }
        }
        return loaded
    }
}
