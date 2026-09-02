import Foundation
import CoreGraphics
import Observation
import PhotosUI
import SwiftUI
import ScannerCore
import CaptureKit
import ImagePipeline
import Telemetry

/// Drives one capture flow (camera or Photos) and writes pages into the library as they arrive.
@MainActor @Observable
final class CaptureCoordinator {
    enum Item: Sendable {
        /// A page from our camera: the still's bytes verbatim (CAP-04), plus whether auto-capture took it.
        case captured(Data, auto: Bool)
        case bitmap(CGImage)
        case file(Data)
        /// One page of a PDF picked in Files; the whole PDF's bytes plus the page index.
        case pdfPage(Data, Int)

        /// Runs inside a detached task: page rendering, orientation baking and JPEG encoding never
        /// touch the main thread.
        func prepare() throws -> PageAssets {
            switch self {
            case .captured(let data, _): return try PageIngest.prepare(imageData: data)
            case .bitmap(let image): return try PageIngest.prepare(image: image)
            case .file(let data): return try PageIngest.prepare(imageData: data)
            case .pdfPage(let data, let index): return try PageIngest.prepare(image: PDFRasterizer.image(from: data, pageIndex: index))
            }
        }

        var telemetryMethod: TelemetryEvent.CaptureMethod {
            switch self {
            case .captured(_, let auto): auto ? .auto : .manual
            case .bitmap, .file, .pdfPage: .imported
            }
        }
    }

    var showingCamera = false
    /// Pages from a finished camera session, parked until the cover's dismissal completes. Nothing
    /// is ingested before then — main-thread work mid-animation wedges the transition.
    var pendingCapture: [CameraModel.CapturedPage]?
    var showingPhotoPicker = false
    var showingFileImporter = false
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
            #if DEBUG
            print("PHASE ingest start: \(items.count) item(s) from \(source.rawValue)")
            #endif
            for (index, item) in items.enumerated() {
                progress = items.count > 1 ? "Saving page \(index + 1) of \(items.count)…" : "Saving page…"
                let assets = try await Task.detached(priority: .userInitiated) { try item.prepare() }.value
                try await library.addPage(assets, to: record)
                Telemetry.record(.pageCaptured(method: item.telemetryMethod, mode: .document, qualityBand: nil, processingLatencyMs: 0))
            }
            try library.finishCapture(record)
            let finished = library.record(id: record.id) ?? record
            #if DEBUG
            print("PHASE ingest done: \(finished.pages.count) page(s) saved")
            #endif
            queue.process(finished.id)
            return finished
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// PDFs are capped so a 500-page book doesn't grind the phone; images pass through verbatim.
    nonisolated static let maxPDFPages = 50

    /// Reads the picked files off the main actor. Returns the ingestable items and any per-file problems.
    nonisolated static func loadItems(from urls: [URL]) -> (items: [Item], problems: [String]) {
        var items: [Item] = []
        var problems: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                problems.append("Couldn't read \"\(url.lastPathComponent)\".")
                continue
            }
            if url.pathExtension.lowercased() == "pdf" || data.starts(with: Array("%PDF".utf8)) {
                guard let count = PDFRasterizer.pageCount(of: data), count > 0 else {
                    problems.append("\"\(url.lastPathComponent)\" doesn't look like a readable PDF.")
                    continue
                }
                guard count <= maxPDFPages else {
                    problems.append("\"\(url.lastPathComponent)\" has \(count) pages — PDFs up to \(maxPDFPages) pages for now.")
                    continue
                }
                items.append(contentsOf: (0..<count).map { Item.pdfPage(data, $0) })
            } else {
                items.append(.file(data))
            }
        }
        return (items, problems)
    }

    func loadPickerItems(_ items: [PhotosPickerItem]) async -> [Item] {
        var loaded: [Item] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { loaded.append(.file(data)) }
        }
        return loaded
    }
}
