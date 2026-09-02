import SwiftUI
import ScannerCore
import CaptureKit
import Export
import Telemetry
import DesignSystem

enum PageStatus: Equatable {
    case queued, recognizing, done(ConfidenceBand), failed
}

struct ReviewView: View {
    let scanID: UUID

    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue
    @Environment(ExportService.self) private var exporter

    @State private var capture = CaptureCoordinator()
    @State private var preset: ExportPreset = .standard
    @State private var kind: ExportKind = .searchablePDF
    @State private var estimate: Int?
    @State private var shareItems: ShareItems?
    @State private var filesItems: ShareItems?
    @State private var showingTextPreview = false
    @State private var renaming = false
    @State private var draftTitle = ""
    @State private var errorMessage: String?
    @State private var startedCapture = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.m)]

    var body: some View {
        Group {
            if let record = library.record(id: scanID) {
                content(record)
            } else {
                ContentUnavailableView("Scan not found", systemImage: "doc.viewfinder")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Opening an interrupted scan resumes it, and (re)starts OCR/verification.
            if !startedCapture {
                startedCapture = true
                if let rec = library.record(id: scanID), rec.state == .capturing { try? library.finishCapture(rec) }
                queue.process(scanID)
            }
        }
    }

    @ViewBuilder
    private func content(_ record: ScanRecord) -> some View {
        let pages = record.orderedPages
        let isReading = queue.isBusy(scanID)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header(record, isReading: isReading)
                VerificationSummaryView(scanID: scanID, record: record, pages: pages, isWorking: isReading) { warning in
                    ignore(warning)
                }
                LazyVGrid(columns: columns, spacing: DS.Spacing.m) {
                    ForEach(pages) { page in
                        NavigationLink(value: PageRef(scanID: scanID, pageID: page.id)) {
                            PageCard(page: page, status: status(of: page),
                                     hasWarning: warnedPageIndexes(record).contains(page.index),
                                     thumbnailURL: library.files.url(for: page.thumbnailPath))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(DS.Spacing.l)
        }
        .safeAreaInset(edge: .bottom) { exportBar(record, isReading: isReading, pages: pages) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Scan more pages", systemImage: "camera.viewfinder") { capture.showingCamera = true }
                        .disabled(!CameraEngine.isAvailable)
                    Button("Add from Photos", systemImage: "photo.on.rectangle") { capture.showingPhotoPicker = true }
                    Button("Add from Files", systemImage: "folder") { capture.showingFileImporter = true }
                    Divider()
                    Button("View recognized text", systemImage: "text.viewfinder") { showingTextPreview = true }
                        .disabled(isReading)
                    Button("Rename", systemImage: "pencil") {
                        draftTitle = record.title
                        renaming = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .captureHost(capture, targetScanID: scanID) { _ in }
        .alert("Rename scan", isPresented: $renaming) {
            TextField("Title", text: $draftTitle)
            Button("Save") { rename(to: draftTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingTextPreview) {
            TextPreviewView(title: record.title, text: TextExporter.text(library.snapshot(record)))
        }
        .sheet(item: $shareItems) { items in
            ShareSheet(items: items.urls).presentationDetents([.medium, .large])
        }
        .sheet(item: $filesItems) { items in
            DocumentExporter(urls: items.urls).ignoresSafeArea()
        }
        .alert("Something went wrong", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: estimateKey(record, isReading: isReading)) {
            estimate = nil
            guard !isReading, !record.isVerificationStale, !pages.isEmpty else { return }
            estimate = await exporter.estimatedBytes(for: record, preset: preset, kind: kind, library: library)
        }
    }

    private func header(_ record: ScanRecord, isReading: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(record.title).font(.title3.weight(.semibold))
            HStack(spacing: DS.Spacing.m) {
                Text("^[\(record.pages.count) page](inflect: true)")
                if isReading {
                    Label("Reading text… \(record.recognizedPageCount) of \(record.pages.count)", systemImage: "text.viewfinder")
                } else if record.isFullyRecognized {
                    Label("Text recognized", systemImage: "checkmark.circle")
                } else if !record.pages.isEmpty {
                    Label("Some pages couldn't be read", systemImage: "exclamationmark.circle")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let suggestion = titleSuggestion(record) {
                HStack(spacing: DS.Spacing.s) {
                    Text("Suggested: \(suggestion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Use") { rename(to: suggestion) }
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
            ProcessingBadge()
        }
    }

    private func exportBar(_ record: ScanRecord, isReading: Bool, pages: [PageRecord]) -> some View {
        VStack(spacing: DS.Spacing.s) {
            HStack {
                Picker("Format", selection: $kind) {
                    ForEach(ExportKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                if kind == .text {
                    Button("Preview") { showingTextPreview = true }.font(.subheadline.weight(.medium)).disabled(isReading)
                }
                Spacer()
                Text(estimateText(record, isReading: isReading, pages: pages))
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            if kind.usesPreset {
                Picker("Quality", selection: $preset) {
                    Text("Email").tag(ExportPreset.email)
                    Text("Standard").tag(ExportPreset.standard)
                    Text("Archive").tag(ExportPreset.archive)
                }
                .pickerStyle(.segmented)
            }
            Button {
                Task { await export(record, to: .share) }
            } label: {
                Group {
                    if exporter.isExporting { ProgressView().tint(.white) }
                    else { Label("Share \(kind.title)", systemImage: "square.and.arrow.up") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!canExport(isReading: isReading, pages: pages))

            Button {
                Task { await export(record, to: .files) }
            } label: {
                Label("Save to Files", systemImage: "folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canExport(isReading: isReading, pages: pages))

            if isReading {
                Text("Export unlocks when every page has been read.").font(.footnote).foregroundStyle(.secondary)
            } else if !record.activeWarnings.isEmpty {
                Text("^[\(record.activeWarnings.count) warning](inflect: true) above — worth a look before sending.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.m)
        .background(.bar)
    }

    // MARK: Helpers

    private func titleSuggestion(_ record: ScanRecord) -> String? {
        guard record.hasDefaultTitle, let classification = record.classification else { return nil }
        return classification.suggestedTitle(fallbackDate: record.createdAt)
    }

    private func warnedPageIndexes(_ record: ScanRecord) -> Set<Int> {
        Set(record.activeWarnings.compactMap(\.pageIndex))
    }

    private func estimateKey(_ record: ScanRecord, isReading: Bool) -> String {
        "\(preset.rawValue)|\(kind.rawValue)|\(record.updatedAt.timeIntervalSinceReferenceDate)|\(isReading)|\(record.isVerificationStale)"
    }

    private func estimateText(_ record: ScanRecord, isReading: Bool, pages: [PageRecord]) -> String {
        if isReading { return "Size known once text is read" }
        if record.isVerificationStale { return "Size follows the quality check" }
        guard let estimate else { return pages.isEmpty ? "" : "Estimating size…" }
        return "≈ \(estimate.formatted(.byteCount(style: .file)))"
    }

    private func canExport(isReading: Bool, pages: [PageRecord]) -> Bool {
        !exporter.isExporting && !isReading && !pages.isEmpty
    }

    private func status(of page: PageRecord) -> PageStatus {
        if let band = page.confidenceBand { return .done(band) }
        if page.isRecognized { return .done(.medium) }
        if queue.failed.contains(page.id) { return .failed }
        if queue.inFlight.contains(page.id) { return .recognizing }
        return .queued
    }

    private enum Destination { case share, files }

    private func export(_ record: ScanRecord, to destination: Destination) async {
        do {
            let urls = try await exporter.export(record, preset: preset, kind: kind, library: library)
            switch destination {
            case .share: shareItems = ShareItems(urls: urls)
            case .files: filesItems = ShareItems(urls: urls)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ignore(_ warning: ScanWarning) {
        do {
            try library.ignoreWarning(warning.key, inScan: scanID)
            Telemetry.record(.qualityWarningResolved(type: warning.telemetryType, action: .ignore))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(to title: String) {
        guard let record = library.record(id: scanID) else { return }
        do { try library.rename(record, to: title) } catch { errorMessage = error.localizedDescription }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct PageCard: View {
    let page: PageRecord
    let status: PageStatus
    let hasWarning: Bool
    let thumbnailURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ThumbnailView(url: thumbnailURL)
                .frame(maxWidth: .infinity).frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { statusChip.padding(6) }
                .overlay(alignment: .topLeading) {
                    if hasWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).padding(6)
                            .background(.regularMaterial, in: Circle()).padding(6)
                            .accessibilityHidden(true)
                    }
                }
            Text("Page \(page.index + 1)").font(.subheadline.weight(.medium))
            Text(statusText).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(page.index + 1), \(statusText)")
    }

    @ViewBuilder
    private var statusChip: some View {
        switch status {
        case .queued, .recognizing:
            ProgressView().controlSize(.small).padding(6).background(.regularMaterial, in: Circle())
        case .done(let band):
            Image(systemName: bandSymbol(band)).foregroundStyle(bandColor(band))
                .padding(6).background(.regularMaterial, in: Circle())
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .padding(6).background(.regularMaterial, in: Circle())
        }
    }

    private var statusText: String {
        let base: String
        switch status {
        case .queued: base = "Waiting"
        case .recognizing: base = "Reading text…"
        case .done(.high): base = "Text read, high confidence"
        case .done(.medium): base = "Text read, medium confidence"
        case .done(.low): base = "Text read, low confidence — check it"
        case .failed: base = "Couldn't read text"
        }
        return hasWarning ? base + ", needs attention" : base
    }

    private func bandSymbol(_ band: ConfidenceBand) -> String {
        switch band {
        case .high: "checkmark.circle.fill"
        case .medium: "minus.circle.fill"
        case .low: "exclamationmark.circle.fill"
        }
    }

    private func bandColor(_ band: ConfidenceBand) -> Color {
        switch band {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }
}
