import CoreGraphics
import Foundation
import Observation

/// The local library, backed by plain files — no SwiftData, no database contexts, no detachable
/// model objects. Each scan is a directory holding page images, thumbnails, and a `scan.json`. The
/// in-memory `records` array is the source of truth for the UI; every mutation rewrites the affected
/// `scan.json` atomically. This behaves identically on device and in tests (it is only Foundation
/// file I/O), which the SwiftData version did not.
@MainActor @Observable
public final class Library {
    public enum Failure: LocalizedError {
        case scanNotFound
        public var errorDescription: String? { "That scan is no longer available." }
    }

    public let files: FileStore
    /// Newest first. Reassigned wholesale on every change so SwiftUI observation fires.
    public private(set) var records: [ScanRecord] = []

    public init(files: FileStore) {
        self.files = files
        self.records = Self.loadAll(from: files).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The app's persistent library under Application Support.
    public static func live() throws -> Library {
        Library(files: try FileStore.live())
    }

    /// A library rooted at a throwaway directory — for tests and previews.
    public static func ephemeral(filesRoot: URL) throws -> Library {
        Library(files: try FileStore(root: filesRoot))
    }

    // MARK: Lookups

    public func record(id: UUID) -> ScanRecord? { records.first { $0.id == id } }
    public func allRecords() -> [ScanRecord] { records }

    /// Sessions interrupted mid-capture, newest first. Empty drafts are cleaned up on the way.
    public func recoverableDrafts() -> [ScanRecord] {
        var recoverable: [ScanRecord] = []
        for record in records where record.state == .capturing {
            if record.pages.isEmpty { try? delete(record) } else { recoverable.append(record) }
        }
        return recoverable
    }

    // MARK: Capture (write-ahead: files hit disk before the record is persisted)

    public func createDraft(source: CaptureSource, title: String? = nil) throws -> ScanRecord {
        let record = ScanRecord(title: title ?? Self.defaultTitle(for: .now), source: source)
        try persist(record)
        upsert(record)
        return record
    }

    @discardableResult
    public func addPage(_ assets: PageAssets, to record: ScanRecord) async throws -> PageRecord {
        let pageID = UUID()
        let recordID = record.id
        let files = files
        // Multi-megabyte writes never touch the main actor.
        let paths = try await Task.detached(priority: .userInitiated) {
            (original: try files.writeOriginal(assets.originalData, extension: assets.originalExtension, document: recordID, page: pageID),
             thumbnail: try files.writeThumbnail(assets.thumbnailData, document: recordID, page: pageID))
        }.value

        var current = self.record(id: recordID) ?? record
        let index = (current.pages.map(\.index).max() ?? -1) + 1
        let page = PageRecord(id: pageID, index: index, originalPath: paths.original, thumbnailPath: paths.thumbnail, pixelSize: assets.pixelSize)
        current.pages.append(page)
        current.updatedAt = .now
        current.contentRevision += 1
        try save(current)
        return page
    }

    public func finishCapture(_ record: ScanRecord) throws {
        try mutate(record.id) { $0.state = .ready; $0.updatedAt = .now }
    }

    public func setRecognition(_ recognition: PageRecognition, forPage pageID: UUID, inScan scanID: UUID) throws {
        try mutate(scanID) { record in
            guard let index = record.pages.firstIndex(where: { $0.id == pageID }) else { return }
            record.pages[index].recognition = recognition
            record.updatedAt = .now
            record.contentRevision += 1
        }
    }

    /// Verification/classification describe content; they deliberately do not bump contentRevision.
    public func setVerification(_ result: VerificationResult, forScan scanID: UUID) throws {
        try mutate(scanID) { $0.verification = result }
    }

    public func setClassification(_ result: ClassificationResult, forScan scanID: UUID) throws {
        try mutate(scanID) { $0.classification = result }
    }

    public func ignoreWarning(_ key: String, inScan scanID: UUID) throws {
        try mutate(scanID) { record in
            guard !record.ignoredWarningKeys.contains(key) else { return }
            record.ignoredWarningKeys.append(key)
        }
    }

    public func rename(_ record: ScanRecord, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try mutate(record.id) { $0.title = trimmed; $0.updatedAt = .now }
    }

    // MARK: Library management

    public func delete(_ record: ScanRecord) throws {
        try files.removeDocument(record.id)
        records.removeAll { $0.id == record.id }
    }

    public func deleteEverything() throws {
        records = []
        try files.removeAll()
    }

    // MARK: Snapshots for OCR/export (pages decode lazily from disk, one at a time)

    public func snapshot(_ record: ScanRecord) -> ScanDocument {
        let current = self.record(id: record.id) ?? record
        let pages = current.orderedPages.map { page in
            let url = files.url(for: page.originalPath)
            return ScanPage(id: page.id, pixelSize: page.pixelSize, recognition: page.recognition) {
                try ImageDecoder.image(at: url)
            }
        }
        return ScanDocument(id: current.id, title: current.title, pages: pages, source: current.source, createdAt: current.createdAt)
    }

    public static func defaultTitle(for date: Date) -> String {
        "Scan \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: Persistence internals

    private func mutate(_ id: UUID, _ change: (inout ScanRecord) -> Void) throws {
        guard var record = self.record(id: id) else { throw Failure.scanNotFound }
        change(&record)
        try save(record)
    }

    private func save(_ record: ScanRecord) throws {
        try persist(record)
        upsert(record)
    }

    /// Replaces (or inserts) the record in the in-memory list, keeping it newest-first.
    private func upsert(_ record: ScanRecord) {
        var updated = records.filter { $0.id != record.id }
        updated.append(record)
        records = updated.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist(_ record: ScanRecord) throws {
        let data = try Self.encoder.encode(record)
        try files.writeMetadata(data, document: record.id)
    }

    private static func loadAll(from files: FileStore) -> [ScanRecord] {
        files.documentIDs().compactMap { id in
            guard let data = try? files.readMetadata(document: id) else { return nil }
            return try? decoder.decode(ScanRecord.self, from: data)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
