import CoreGraphics
import Foundation

/// A scan's lifecycle. A record left in `.capturing` is a recoverable session (PRD §9 Reliability).
public enum ScanState: String, Sendable, Codable {
    case capturing, ready
}

/// One page of a scan. Value type — snapshots are copied freely and can never "detach" from a store
/// (the failure mode that plagued the SwiftData version on device). Image bytes live in files; this
/// holds paths and derived data only.
public struct PageRecord: Identifiable, Sendable, Codable {
    public var id: UUID
    public var index: Int
    public var originalPath: String
    public var thumbnailPath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var recognition: PageRecognition?

    public init(id: UUID = UUID(), index: Int, originalPath: String, thumbnailPath: String, pixelSize: CGSize, recognition: PageRecognition? = nil) {
        self.id = id
        self.index = index
        self.originalPath = originalPath
        self.thumbnailPath = thumbnailPath
        self.pixelWidth = Int(pixelSize.width)
        self.pixelHeight = Int(pixelSize.height)
        self.recognition = recognition
    }

    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    public var confidenceBand: ConfidenceBand? { recognition?.confidenceBand }
    public var isRecognized: Bool { recognition != nil }
}

/// A scan in the local library. Pages are embedded (no relationships, no foreign keys). Persisted as
/// one `scan.json` per scan directory.
public struct ScanRecord: Identifiable, Sendable, Codable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    /// Bumped on every change — the list sorts by it and it keys export/estimate caches.
    public var updatedAt: Date
    public var source: CaptureSource
    public var state: ScanState
    /// Bumped only when content changes (pages, recognition) — verification staleness tracks this, so
    /// renaming a scan doesn't force a re-verify.
    public var contentRevision: Int
    public var verification: VerificationResult?
    public var classification: ClassificationResult?
    public var ignoredWarningKeys: [String]
    public var pages: [PageRecord]

    public init(
        id: UUID = UUID(), title: String, source: CaptureSource, state: ScanState = .capturing,
        createdAt: Date = .now, contentRevision: Int = 0, pages: [PageRecord] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.source = source
        self.state = state
        self.contentRevision = contentRevision
        self.ignoredWarningKeys = []
        self.pages = pages
    }

    public var orderedPages: [PageRecord] { pages.sorted { $0.index < $1.index } }
    public var isFullyRecognized: Bool { !pages.isEmpty && pages.allSatisfy(\.isRecognized) }
    public var recognizedPageCount: Int { pages.filter(\.isRecognized).count }
    public var isVerificationStale: Bool { verification.map { $0.contentRevision != contentRevision } ?? true }
    public var hasDefaultTitle: Bool { title.hasPrefix("Scan ") }

    /// Warnings still standing after the user's ignores (QLT-02).
    public var activeWarnings: [ScanWarning] {
        (verification?.warnings ?? []).filter { !ignoredWarningKeys.contains($0.key) }
    }
}
