import Foundation

/// PRD EXP-02: email-friendly, standard, or archival output.
public enum ExportPreset: String, CaseIterable, Identifiable, Sendable {
    case email, standard, archive

    public var id: String { rawValue }

    /// Longest side in pixels after downscaling; `nil` keeps the capture's full resolution.
    public var maxLongSide: Int? {
        switch self {
        case .email: 1500
        case .standard: 2500
        case .archive: nil
        }
    }

    public var jpegQuality: Double {
        switch self {
        case .email: 0.5
        case .standard: 0.75
        case .archive: 0.92
        }
    }
}

/// PRD §10: every feature says where it runs. The MVP has exactly one value.
public enum ProcessingLocation: String, Sendable {
    case onDevice, cloud
}
