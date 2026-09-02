import Foundation
import SwiftData

/// The app has exactly one live store. On a physical device a model's own `modelContext` can come back
/// nil right after a save (works in the simulator, which is why unit tests never caught it), so reads
/// fall back to this. Set by `Library`; accessed only on the main actor in practice.
public enum ActiveStore {
    nonisolated(unsafe) public static weak var context: ModelContext?
}

public enum ScanState: String, Sendable, Codable {
    /// Pages are still arriving. A record left in this state is a recoverable session (PRD §9 Reliability).
    case capturing
    case ready
}

/// A scan in the local library. Pages and their files are owned by the record (cascade delete).
@Model
public final class ScanRecord {
    // NOT @Attribute(.unique): ids are UUIDs we generate, so the constraint adds nothing — and on
    // iOS 18, unique constraints + relationships hit a SwiftData bug that remaps identifiers during
    // save and crashes ("fatal logic error in DefaultStore" / "This store went missing?").
    public var id: UUID
    public var title: String
    public var createdAt: Date
    /// Bumped on every change (pages, recognition, title) — used as a cheap cache/version key.
    public var updatedAt: Date
    public var sourceRaw: String
    public var stateRaw: String
    /// Bumped only when content changes (pages, recognition) — verification staleness tracks this,
    /// so renaming a scan doesn't trigger a re-verify.
    public var contentRevision: Int = 0
    @Attribute(.externalStorage) public var verificationData: Data? = nil
    @Attribute(.externalStorage) public var classificationData: Data? = nil
    /// Stored optional: on iOS 18, lightweight migration leaves newly added array attributes nil on
    /// pre-existing rows and then fatals on non-optional access ("Unable to convert nil to expected
    /// type Array<String>"). Deliberately a fresh column with no @Attribute(originalName:) — that
    /// rename path is itself crash-prone on iOS 18; the legacy test-only column is simply abandoned.
    private var ignoredWarningKeysStorage: [String]? = []

    public init(id: UUID = UUID(), title: String, source: CaptureSource, state: ScanState = .capturing, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sourceRaw = source.rawValue
        self.stateRaw = state.rawValue
    }

    public var source: CaptureSource {
        get { CaptureSource(rawValue: sourceRaw) ?? .files }
        set { sourceRaw = newValue.rawValue }
    }

    public var state: ScanState {
        get { ScanState(rawValue: stateRaw) ?? .ready }
        set { stateRaw = newValue.rawValue }
    }

    /// A context-attached copy to read faulting attributes from. On a physical device the record handed
    /// to the app is often detached (`modelContext == nil`); reading its externally-stored attributes
    /// then crashes ("backing data was detached from a context without resolving attribute faults").
    /// Re-fetching a live copy from the one live store makes every read safe.
    var live: ScanRecord {
        if modelContext != nil { return self }
        guard let store = ActiveStore.context else { return self }
        let id = id
        return ((try? store.fetch(FetchDescriptor<ScanRecord>())) ?? []).first { $0.id == id } ?? self
    }

    /// Keys of warnings the user chose to ignore (QLT-02: warn, let the user decide). Never nil.
    public var ignoredWarningKeys: [String] {
        get { live.ignoredWarningKeysStorage ?? [] }
        set { ignoredWarningKeysStorage = newValue }
    }

    /// Pages are looked up by foreign key, NOT a SwiftData relationship: every iOS 18 crash this
    /// project has hit ("remapped to a temporary identifier", "This store went missing?") came from
    /// relationship bookkeeping during saves. A plain ID sidesteps that machinery entirely.
    ///
    /// Filtering is done in Swift, not with a #Predicate: on iOS 18 a UUID-equality predicate silently
    /// matches nothing (works on iOS 26 — the LibraryTests passed there while the device saw 0 pages).
    /// Libraries are small, so fetch-all-then-filter costs nothing and can't be wrong.
    public var pages: [PageRecord] {
        let id = id
        let store = modelContext ?? ActiveStore.context
        let all = (try? store?.fetch(FetchDescriptor<PageRecord>())) ?? []
        return all.filter { $0.documentID == id }
    }

    public var orderedPages: [PageRecord] { pages.sorted { $0.index < $1.index } }

    public var verification: VerificationResult? {
        live.verificationData.flatMap { try? JSONDecoder().decode(VerificationResult.self, from: $0) }
    }

    public var classification: ClassificationResult? {
        live.classificationData.flatMap { try? JSONDecoder().decode(ClassificationResult.self, from: $0) }
    }

    public var isVerificationStale: Bool {
        let live = live
        return live.verification.map { $0.contentRevision != live.contentRevision } ?? true
    }

    /// Warnings still standing after the user's ignores.
    public var activeWarnings: [ScanWarning] {
        (verification?.warnings ?? []).filter { !ignoredWarningKeys.contains($0.key) }
    }

    /// True while the title is the automatic one — the only case where a suggestion is offered.
    public var hasDefaultTitle: Bool { title.hasPrefix("Scan ") }
    public var isFullyRecognized: Bool { pages.allSatisfy { $0.recognitionData != nil } }
    public var recognizedPageCount: Int { pages.filter { $0.recognitionData != nil }.count }
}

@Model
public final class PageRecord {
    // Not unique either — see the note on ScanRecord.id.
    public var id: UUID
    /// Foreign key to the owning ScanRecord — deliberately not a SwiftData relationship (see above).
    public var documentID: UUID
    public var index: Int
    public var originalPath: String
    public var thumbnailPath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// `PageRecognition` as JSON. Kept out of the main table so lists stay fast.
    @Attribute(.externalStorage) public var recognitionData: Data?
    public var confidenceBandRaw: String?

    /// The owning record, resolved by foreign key (filtered in Swift — see the note on ScanRecord.pages).
    public var document: ScanRecord? {
        let id = documentID
        let store = modelContext ?? ActiveStore.context
        let all = (try? store?.fetch(FetchDescriptor<ScanRecord>())) ?? []
        return all.first { $0.id == id }
    }

    public init(id: UUID = UUID(), documentID: UUID, index: Int, originalPath: String, thumbnailPath: String, pixelSize: CGSize) {
        self.id = id
        self.documentID = documentID
        self.index = index
        self.originalPath = originalPath
        self.thumbnailPath = thumbnailPath
        self.pixelWidth = Int(pixelSize.width)
        self.pixelHeight = Int(pixelSize.height)
    }

    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }

    /// See ScanRecord.live — pages detach on device too, and `recognitionData` is external storage.
    var live: PageRecord {
        if modelContext != nil { return self }
        guard let store = ActiveStore.context else { return self }
        let id = id
        return ((try? store.fetch(FetchDescriptor<PageRecord>())) ?? []).first { $0.id == id } ?? self
    }

    public var confidenceBand: ConfidenceBand? { confidenceBandRaw.flatMap(ConfidenceBand.init(rawValue:)) }

    public var recognition: PageRecognition? {
        get { live.recognitionData.flatMap { try? JSONDecoder().decode(PageRecognition.self, from: $0) } }
        set {
            recognitionData = newValue.flatMap { try? JSONEncoder().encode($0) }
            confidenceBandRaw = newValue?.confidenceBand.rawValue
        }
    }
}
