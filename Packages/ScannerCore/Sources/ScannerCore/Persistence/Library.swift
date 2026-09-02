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
        ActiveStore.context = context
    }

    /// The app's persistent library: Application Support/Scanner/{Library.store, Documents/}.
    /// The file store is created first so the directory exists before SwiftData opens the database.
    public static func live() throws -> Library {
        let files = try FileStore.live()
        // v2: a clean store file. Today's repeated schema changes (relationship → foreign key, added
        // attributes) can leave the old "Library.store" half-migrated and silently empty on iOS 18.
        let storeURL = files.root.deletingLastPathComponent().appending(path: "Library-v2.store")
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
    public func addPage(_ assets: PageAssets, to record: ScanRecord) async throws -> PageRecord {
        let pageID = UUID()
        let recordID = record.id
        let files = files
        // Multi-megabyte originals must not be written on the main actor. Files still hit disk
        // before the database row exists — the write-ahead order is unchanged.
        let paths = try await Task.detached(priority: .userInitiated) {
            (original: try files.writeOriginal(assets.originalData, extension: assets.originalExtension, document: recordID, page: pageID),
             thumbnail: try files.writeThumbnail(assets.thumbnailData, document: recordID, page: pageID))
        }.value
        let originalPath = paths.original
        let thumbnailPath = paths.thumbnail
        let index = (record.pages.map(\.index).max() ?? -1) + 1
        // No relationship is wired — the foreign key is set at init, so this insert+save carries no
        // relationship bookkeeping for iOS 18's SwiftData to trip over (the source of all four crashes).
        let page = PageRecord(id: pageID, documentID: record.id, index: index, originalPath: originalPath, thumbnailPath: thumbnailPath, pixelSize: assets.pixelSize)
        context.insert(page)
        record.updatedAt = .now
        record.contentRevision += 1
        try context.save()
        #if DEBUG
        print("PHASE addPage: record.modelContext isNil=\(record.modelContext == nil) sameAsLibrary=\(record.modelContext === context); record.pages.count=\(record.pages.count)")
        #endif
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
        // Cascade by hand — there is no relationship delete rule any more.
        for page in record.pages { context.delete(page) }
        context.delete(record)
        try context.save()
    }

    public func deleteEverything() throws {
        for page in try context.fetch(FetchDescriptor<PageRecord>()) { context.delete(page) }
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
