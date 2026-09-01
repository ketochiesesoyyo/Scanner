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
    /// The capture exactly as the source delivered it. Never mutated (PRD CAP-04);
    /// enhancements are derivatives rendered from this.
    public let original: CGImage
    public var recognition: PageRecognition?

    public init(id: UUID = UUID(), original: CGImage, recognition: PageRecognition? = nil) {
        self.id = id
        self.original = original
        self.recognition = recognition
    }

    public var pixelSize: CGSize { CGSize(width: original.width, height: original.height) }
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
