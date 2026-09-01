import Foundation

/// PRD §12 events. Every payload is an enum or a number — by construction there is no place to put
/// OCR text, filenames, extracted values or images.
public enum TelemetryEvent: Sendable {
    case scanSessionStarted(entryPoint: EntryPoint, proposedMode: Mode)
    case pageCaptured(method: CaptureMethod, mode: Mode, qualityBand: Band?, processingLatencyMs: Int)
    case qualityWarningShown(type: WarningType, confidence: Band, pageIndex: Int)
    case qualityWarningResolved(type: WarningType, action: WarningAction)
    case ocrCompleted(language: LanguageTag, documentClass: DocumentClass, confidence: Band, latencyMs: Int)
    case exportCompleted(format: ExportFormat, pageCountBand: CountBand, sizeBand: SizeBand, destination: DestinationCategory)
    case actionCompleted(type: ActionType, integration: IntegrationCategory, success: Bool)

    public enum EntryPoint: String, Sendable { case app, control, widget, shareExtension, shortcut }
    public enum Mode: String, Sendable { case document, receipt, id, book, whiteboard, photo }
    public enum CaptureMethod: String, Sendable { case auto, manual, imported }
    public enum Band: String, Sendable { case high, medium, low }
    public enum WarningType: String, Sendable { case blur, glare, shadow, crop, perspective, readability, duplicate, sequence }
    public enum WarningAction: String, Sendable { case recapture, edit, ignore }
    public enum LanguageTag: String, Sendable { case es, en, mixed, other }
    public enum DocumentClass: String, Sendable { case unknown, receipt, invoice, id, contract, form, letter, notes, other }
    public enum ExportFormat: String, Sendable { case pdf, searchablePDF, jpeg, text }
    public enum DestinationCategory: String, Sendable { case shareSheet, files, integration }
    public enum ActionType: String, Sendable { case export, sign, route }
    public enum IntegrationCategory: String, Sendable { case none, cloudDrive, email, expense }

    public enum CountBand: String, Sendable {
        case one, twoToFive, sixToTwenty, moreThanTwenty
        public init(_ count: Int) {
            switch count {
            case ...1: self = .one
            case 2...5: self = .twoToFive
            case 6...20: self = .sixToTwenty
            default: self = .moreThanTwenty
            }
        }
    }

    public enum SizeBand: String, Sendable {
        case under1MB, under5MB, under20MB, over20MB
        public init(bytes: Int) {
            switch bytes {
            case ..<1_000_000: self = .under1MB
            case ..<5_000_000: self = .under5MB
            case ..<20_000_000: self = .under20MB
            default: self = .over20MB
            }
        }
    }

    /// Wire name, matching the PRD table.
    public var name: String {
        switch self {
        case .scanSessionStarted: "scan_session_started"
        case .pageCaptured: "page_captured"
        case .qualityWarningShown: "quality_warning_shown"
        case .qualityWarningResolved: "quality_warning_resolved"
        case .ocrCompleted: "ocr_completed"
        case .exportCompleted: "export_completed"
        case .actionCompleted: "action_completed"
        }
    }
}
