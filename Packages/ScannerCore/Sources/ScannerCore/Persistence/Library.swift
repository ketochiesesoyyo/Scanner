import Foundation
import Observation
import SwiftData

/// The local library: SwiftData records + `FileStore` files, all on the main actor.
///
/// Write-ahead by construction: `addPage` writes the files first, then inserts and saves the record, so
/// a crash between pages loses at most the page being written, and any `ScanRecord` still in
/// `.capturing` on the next launch is a session to resume (PRD §9 Reliability).
@MainActor @Observable
public final class Library {
    public enum Failure: LocalizedError {
        case pageIndexUnavailable
        public var errorDescription: String? { "Couldn't add the page to this scan." }
    }

    public let container: ModelContainer
    public let files: FileStore

    public var context: ModelContext { container.mainContext }

    public init(container: ModelContainer, files: FileStore) {
        self.container = container
        self.files = files
        context.autosaveEnabled = false
    }

    /// The app's persistent library: Application Support/Scanner/{Library.store, Documents/}.
    /// The file store is created first so the directory exists before SwiftData opens the database.
    public static func live() throws -> Library {
        let files = try FileStore.live()
        let storeURL = files.root.deletingLastPathComponent().appending(path: "Library.store")
        let configuration = ModelConfiguration("ScannerLibrary", schema: Self.schema, url: storeURL)
        return Library(container: try ModelContainer(for: Self.schema, configurations: [configuration]), files: files)
    }

    /// In-memory records with files under `filesRoot` — for tests and previews.
    public static func ephemeral(filesRoot: URL) throws -> Library {
        let configuration = ModelConfiguration("ScannerLibraryEphemeral", schema: Self.schema, isStoredInMemoryOnly: true)
        return Library(container: try ModelContainer(for: Self.schema, configurations: [configuration]), files: try FileStore(root: filesRoot))
    }

    public static let schema = Schema([ScanRecord.self, PageRecord.self])

    // MARK: Capture

    public func createDraft(source: CaptureSource, title: String? = nil) throws -> ScanRecord {
        let record = ScanRecord(title: title ?? Self.defaultTitle(for: .now), source: source)
        context.insert(record)
        try context.save()
        return record
    }

    @discardableResult
    public func addPage(_ assets: PageAssets, to record: ScanRecord) throws -> PageRecord {
        let pageID = UUID()
        let originalPath = try files.writeOriginal(assets.originalData, extension: assets.originalExtension, document: record.id, page: pageID)
        let thumbnailPath = try files.writeThumbnail(assets.thumbnailData, document: record.id, page: pageID)
        let index = (record.pages.map(\.index).max() ?? -1) + 1
        let page = PageRecord(id: pageID, index: index, originalPath: originalPath, thumbnailPath: thumbnailPath, pixelSize: assets.pixelSize)
        page.document = record
        context.insert(page)
        record.updatedAt = .now
        record.contentRevision += 1
        try context.save()
        return page
    }

    public func finishCapture(_ record: ScanRecord) throws {
        record.state = .ready
        record.updatedAt = .now
        try context.save()
    }

    public func setRecognition(_ recognition: PageRecognition, for page: PageRecord) throws {
        page.recognition = recognition
        page.document?.updatedAt = .now
        page.document?.contentRevision += 1
        try context.save()
    }

    /// Deliberately does not bump `updatedAt`/`contentRevision`: verification describes content,
    /// it isn't content.
    public func setVerification(_ result: VerificationResult, for record: ScanRecord) throws {
        record.verificationData = try JSONEncoder().encode(result)
        try context.save()
    }

    public func setClassification(_ result: ClassificationResult, for record: ScanRecord) throws {
        record.classificationData = try JSONEncoder().encode(result)
        try context.save()
    }

    public func ignoreWarning(_ key: String, in record: ScanRecord) throws {
        guard !record.ignoredWarningKeys.contains(key) else { return }
        record.ignoredWarningKeys.append(key)
        try context.save()
    }

    // MARK: Library management

    public func rename(_ record: ScanRecord, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.title = trimmed
        record.updatedAt = .now
        try context.save()
    }

    public func delete(_ record: ScanRecord) throws {
        try files.removeDocument(record.id)
        context.delete(record)
        try context.save()
    }

    public func deleteEverything() throws {
        for record in try allRecords() { context.delete(record) }
        try context.save()
        try files.removeAll()
    }

    public func allRecords() throws -> [ScanRecord] {
        try context.fetch(FetchDescriptor<ScanRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    /// Sessions interrupted mid-capture, newest first. Empty drafts are cleaned up on the way.
    public func recoverableDrafts() throws -> [ScanRecord] {
        let capturing = ScanState.capturing.rawValue
        let drafts = try context.fetch(FetchDescriptor<ScanRecord>(
            predicate: #Predicate { $0.stateRaw == capturing },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        var recoverable: [ScanRecord] = []
        for draft in drafts {
            if draft.pages.isEmpty { try delete(draft) } else { recoverable.append(draft) }
        }
        return recoverable
    }

    /// Pages that still need OCR (e.g. the app was killed while reading text).
    public func pagesAwaitingRecognition() throws -> [PageRecord] {
        try allRecords().flatMap { $0.orderedPages.filter { $0.recognitionData == nil } }
    }

    // MARK: Snapshots

    /// A `Sendable` value view of a record for export and recognition. Page images are decoded lazily
    /// from disk, one at a time.
    public func snapshot(_ record: ScanRecord) -> ScanDocument {
        let pages = record.orderedPages.map { page in
            let url = files.url(for: page.originalPath)
            return ScanPage(id: page.id, pixelSize: page.pixelSize, recognition: page.recognition) {
                try ImageDecoder.image(at: url)
            }
        }
        return ScanDocument(id: record.id, title: record.title, pages: pages, source: record.source, createdAt: record.createdAt)
    }

    public static func defaultTitle(for date: Date) -> String {
        "Scan \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
