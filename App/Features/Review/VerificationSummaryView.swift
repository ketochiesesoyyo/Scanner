import SwiftUI
import ScannerCore
import Telemetry
import DesignSystem

extension ScanWarning {
    /// User-facing message. Page numbers are 1-based.
    func message(pageCount: Int) -> String {
        switch self {
        case .blur(let index): "Page \(index + 1) looks blurry"
        case .glare(let index): "Glare may hide text on page \(index + 1)"
        case .shadow(let index): "A strong shadow crosses page \(index + 1)"
        case .readability(let index): "Some text on page \(index + 1) couldn't be read confidently"
        case .smudge(let index): "Page \(index + 1) may have been shot through a smudged lens"
        case .possibleDuplicate(let index, let original): "Pages \(original + 1) and \(index + 1) look identical"
        case .missingPages(let numbers): numbers.count == 1
            ? "Page \(numbers[0]) seems to be missing (the document says it has more pages)"
            : "Pages \(numbers.map(String.init).joined(separator: ", ")) seem to be missing"
        case .outOfOrder(let index): "Page \(index + 1) may be out of order"
        }
    }

    var telemetryType: TelemetryEvent.WarningType {
        switch self {
        case .blur: .blur
        case .glare: .glare
        case .shadow: .shadow
        case .readability: .readability
        case .smudge: .smudge
        case .possibleDuplicate: .duplicate
        case .missingPages, .outOfOrder: .sequence
        }
    }
}

/// PRD §7 step 6: the verification summary. Warnings link to their page and can be ignored —
/// never auto-fixed (QLT-02).
struct VerificationSummaryView: View {
    let scanID: UUID
    let record: ScanRecord
    let pages: [PageRecord]
    let isWorking: Bool
    let onIgnore: (ScanWarning) -> Void

    var body: some View {
        let warnings = record.activeWarnings
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if record.isVerificationStale {
                if isWorking {
                    Label("Checking scan quality…", systemImage: "wand.and.rays")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if warnings.isEmpty {
                Label("Verified — no issues found", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(warnings, id: \.key) { warning in
                    warningRow(warning)
                }
            }
        }
    }

    private func warningRow(_ warning: ScanWarning) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(warning.message(pageCount: pages.count))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let index = warning.pageIndex, let page = pages.first(where: { $0.index == index }) {
                NavigationLink(value: PageRef(scanID: scanID, pageID: page.id)) {
                    Text("View").font(.subheadline.weight(.medium))
                }
                .accessibilityLabel("View page \(index + 1)")
            }
            Button("Ignore") { onIgnore(warning) }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Ignore this warning")
        }
        .padding(DS.Spacing.s)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(warning.message(pageCount: pages.count))")
    }
}
