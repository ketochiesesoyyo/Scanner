import Foundation
import Observation
import ScannerCore
import Export
import Telemetry

enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case searchablePDF, jpeg, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .searchablePDF: "Searchable PDF"
        case .jpeg: "JPEG images"
        case .text: "Text"
        }
    }

    var symbol: String {
        switch self {
        case .searchablePDF: "doc.text.magnifyingglass"
        case .jpeg: "photo.stack"
        case .text: "text.alignleft"
        }
    }

    var usesPreset: Bool { self != .text }
}

/// Builds exports off the main actor and caches them per (record version, preset, format), so the
/// size shown before export is the real size (PRD EXP-02) and the export itself is instant.
@MainActor @Observable
final class ExportService {
    private(set) var isExporting = false
    private var cache: [CacheKey: Prepared] = [:]

    private struct CacheKey: Hashable {
        let record: UUID
        let preset: ExportPreset
        let kind: ExportKind
        let version: Date
    }

    private enum Prepared: Sendable {
        case pdf(PDFExport)
        case jpegs([Data])
        case text(String)

        var byteCount: Int {
            switch self {
            case .pdf(let export): export.byteCount
            case .jpegs(let datas): datas.reduce(0) { $0 + $1.count }
            case .text(let string): string.utf8.count
            }
        }
    }

    func estimatedBytes(for record: ScanRecord, preset: ExportPreset, kind: ExportKind, library: Library) async -> Int? {
        // Pre-computation for a label — never compete with OCR/verification for cores.
        try? await prepared(record, preset: preset, kind: kind, library: library, priority: .utility).byteCount
    }

    /// Writes the export to a protected temp folder and returns the file URLs for the share sheet.
    func export(_ record: ScanRecord, preset: ExportPreset, kind: ExportKind, library: Library) async throws -> [URL] {
        isExporting = true
        defer { isExporting = false }

        let prepared = try await prepared(record, preset: preset, kind: kind, library: library, priority: .userInitiated)
        let directory = Self.exportsDirectory.appending(path: record.id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = ExportFileName.base(from: record.title)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]

        var urls: [URL] = []
        switch prepared {
        case .pdf(let export):
            let url = directory.appending(path: "\(base).pdf")
            try export.data.write(to: url, options: options)
            urls = [url]
        case .jpegs(let datas):
            for (index, data) in datas.enumerated() {
                let name = datas.count > 1 ? "\(base)-p\(String(format: "%02d", index + 1)).jpg" : "\(base).jpg"
                let url = directory.appending(path: name)
                try data.write(to: url, options: options)
                urls.append(url)
            }
        case .text(let string):
            let url = directory.appending(path: "\(base).txt")
            try Data(string.utf8).write(to: url, options: options)
            urls = [url]
        }

        Telemetry.record(.exportCompleted(
            format: Self.telemetryFormat(kind, fullyRecognized: record.isFullyRecognized),
            pageCountBand: .init(record.pages.count),
            sizeBand: .init(bytes: prepared.byteCount),
            destination: .shareSheet
        ))
        return urls
    }

    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: Self.exportsDirectory)
    }

    private func prepared(_ record: ScanRecord, preset: ExportPreset, kind: ExportKind, library: Library, priority: TaskPriority) async throws -> Prepared {
        let key = CacheKey(record: record.id, preset: kind.usesPreset ? preset : .standard, kind: kind, version: record.updatedAt)
        if let hit = cache[key] { return hit }
        #if DEBUG
        print("PHASE export-build start: \(kind.rawValue)/\(preset.rawValue) at \(priority == .utility ? "utility" : "userInitiated")")
        #endif
        let document = library.snapshot(record)
        let result: Prepared = try await Task.detached(priority: priority) {
            switch kind {
            case .searchablePDF: .pdf(try SearchablePDFBuilder(preset: preset).build(document))
            case .jpeg: .jpegs(try JPEGExporter(preset: preset).export(document))
            case .text: .text(TextExporter.text(document))
            }
        }.value
        if cache.count >= 8 { cache.removeAll() }
        cache[key] = result
        #if DEBUG
        print("PHASE export-build done: \(kind.rawValue)/\(preset.rawValue), \(result.byteCount) bytes")
        #endif
        return result
    }

    private static var exportsDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
    }

    private static func telemetryFormat(_ kind: ExportKind, fullyRecognized: Bool) -> TelemetryEvent.ExportFormat {
        switch kind {
        case .searchablePDF: fullyRecognized ? .searchablePDF : .pdf
        case .jpeg: .jpeg
        case .text: .text
        }
    }
}
