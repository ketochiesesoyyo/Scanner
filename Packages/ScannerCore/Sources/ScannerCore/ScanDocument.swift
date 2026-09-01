import Foundation
import CoreGraphics

/// Where a page came from. Drives capture-method telemetry and, later, per-mode defaults.
public enum CaptureSource: String, Sendable, Codable {
    /// M0: VisionKit stand-in. M3: CaptureKit's own camera.
    case documentCamera
    case photoLibrary
    case files
}

public struct ScanPage: Identifiable, Sendable {
    public let id: UUID
    public let pixelSize: CGSize
    public var recognition: PageRecognition?
    private let loader: @Sendable () throws -> CGImage

    /// A page whose capture is already in memory (tests, and the moment of capture).
    public init(id: UUID = UUID(), original: CGImage, recognition: PageRecognition? = nil) {
        self.init(id: id, pixelSize: CGSize(width: original.width, height: original.height), recognition: recognition) { original }
    }

    /// A page whose capture lives on disk. `loader` decodes it on demand.
    public init(id: UUID = UUID(), pixelSize: CGSize, recognition: PageRecognition? = nil, loader: @escaping @Sendable () throws -> CGImage) {
        self.id = id
        self.pixelSize = pixelSize
        self.recognition = recognition
        self.loader = loader
    }

    /// The capture exactly as the source delivered it — never mutated (PRD CAP-04); enhancements are
    /// derivatives. Hold one page at a time: a 25-page document is over a gigabyte decoded.
    public func loadOriginal() throws -> CGImage { try loader() }
}

public struct ScanDocument: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var pages: [ScanPage]
    public let source: CaptureSource
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, pages: [ScanPage], source: CaptureSource, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.pages = pages
        self.source = source
        self.createdAt = createdAt
    }

    /// All recognized text, pages separated by a blank line.
    public var recognizedText: String {
        pages.compactMap { $0.recognition?.text }.joined(separator: "\n\n")
    }

    public var isFullyRecognized: Bool { pages.allSatisfy { $0.recognition != nil } }
}
