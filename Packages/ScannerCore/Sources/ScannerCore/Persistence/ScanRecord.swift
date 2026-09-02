import Foundation
import SwiftData

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
    /// Keys of warnings the user chose to ignore (QLT-02: warn, let the user decide).
    public var ignoredWarningKeys: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \PageRecord.document)
    public var pages: [PageRecord] = []

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

    public var orderedPages: [PageRecord] { pages.sorted { $0.index < $1.index } }

    public var verification: VerificationResult? {
        verificationData.flatMap { try? JSONDecoder().decode(VerificationResult.self, from: $0) }
    }

    public var classification: ClassificationResult? {
        classificationData.flatMap { try? JSONDecoder().decode(ClassificationResult.self, from: $0) }
    }

    public var isVerificationStale: Bool {
        verification.map { $0.contentRevision != contentRevision } ?? true
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
    public var index: Int
    public var originalPath: String
    public var thumbnailPath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// `PageRecognition` as JSON. Kept out of the main table so lists stay fast.
    @Attribute(.externalStorage) public var recognitionData: Data?
    public var confidenceBandRaw: String?
    public var document: ScanRecord?

    public init(id: UUID = UUID(), index: Int, originalPath: String, thumbnailPath: String, pixelSize: CGSize) {
        self.id = id
        self.index = index
        self.originalPath = originalPath
        self.thumbnailPath = thumbnailPath
        self.pixelWidth = Int(pixelSize.width)
        self.pixelHeight = Int(pixelSize.height)
    }

    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }

    public var confidenceBand: ConfidenceBand? { confidenceBandRaw.flatMap(ConfidenceBand.init(rawValue:)) }

    public var recognition: PageRecognition? {
        get { recognitionData.flatMap { try? JSONDecoder().decode(PageRecognition.self, from: $0) } }
        set {
            recognitionData = newValue.flatMap { try? JSONEncoder().encode($0) }
            confidenceBandRaw = newValue?.confidenceBand.rawValue
        }
    }
}
