import SwiftUI
import ScannerCore
import CaptureKit
import DesignSystem

enum PageStatus: Equatable {
    case queued, recognizing, done(ConfidenceBand), failed
}

struct ReviewView: View {
    @Bindable var record: ScanRecord

    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue
    @Environment(ExportService.self) private var exporter

    @State private var capture = CaptureCoordinator()
    @State private var preset: ExportPreset = .standard
    @State private var kind: ExportKind = .searchablePDF
    @State private var estimate: Int?
    @State private var shareItems: ShareItems?
    @State private var filesItems: ShareItems?
    @State private var renaming = false
    @State private var draftTitle = ""
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.m)]
    private var pages: [PageRecord] { record.orderedPages }
    private var isReading: Bool { queue.isBusy(record) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header
                LazyVGrid(columns: columns, spacing: DS.Spacing.m) {
                    ForEach(pages) { page in
                        NavigationLink(value: page) {
                            PageCard(page: page, status: status(of: page), thumbnailURL: library.files.url(for: page.thumbnailPath))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(DS.Spacing.l)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PageRecord.self) { PageDetailView(page: $0) }
        .safeAreaInset(edge: .bottom) { exportBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Scan more pages", systemImage: "camera.viewfinder") { capture.showingCamera = true }
                        .disabled(!DocumentCameraView.isSupported)
                    Button("Add from Photos", systemImage: "photo.on.rectangle") { capture.showingPhotoPicker = true }
                    Divider()
                    Button("Rename", systemImage: "pencil") {
                        draftTitle = record.title
                        renaming = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .captureHost(capture, target: record) { _ in }
        .alert("Rename scan", isPresented: $renaming) {
            TextField("Title", text: $draftTitle)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareItems) { items in
            ShareSheet(items: items.urls)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $filesItems) { items in
            DocumentExporter(urls: items.urls)
                .ignoresSafeArea()
        }
        .alert("Something went wrong", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            // Opening an interrupted scan is how it gets resumed: it becomes a normal scan again.
            if record.state == .capturing { try? library.finishCapture(record) }
            queue.process(record)
        }
        .task(id: estimateKey) {
            estimate = nil
            guard !isReading, !pages.isEmpty else { return }
            estimate = await exporter.estimatedBytes(for: record, preset: preset, kind: kind, library: library)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(record.title).font(.title3.weight(.semibold))
            HStack(spacing: DS.Spacing.m) {
                Text("^[\(pages.count) page](inflect: true)")
                if isReading {
                    Label("Reading text… \(record.recognizedPageCount) of \(pages.count)", systemImage: "text.viewfinder")
                } else if record.isFullyRecognized {
                    Label("Text recognized", systemImage: "checkmark.circle")
                } else if !pages.isEmpty {
                    Label("Some pages couldn't be read", systemImage: "exclamationmark.circle")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ProcessingBadge()
        }
    }

    private var exportBar: some View {
        VStack(spacing: DS.Spacing.s) {
            HStack {
                Picker("Format", selection: $kind) {
                    ForEach(ExportKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Text(estimateText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
                Task { await export(to: .share) }
            } label: {
                Group {
                    if exporter.isExporting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Share \(kind.title)", systemImage: "square.and.arrow.up")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canExport)

            Button {
                Task { await export(to: .files) }
            } label: {
                Label("Save to Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(!canExport)

            if isReading {
                Text("Export unlocks when every page has been read.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.m)
        .background(.bar)
    }

    private var estimateKey: String {
        "\(preset.rawValue)|\(kind.rawValue)|\(record.updatedAt.timeIntervalSinceReferenceDate)|\(isReading)"
    }

    private var estimateText: String {
        if isReading { return "Size known once text is read" }
        guard let estimate else { return pages.isEmpty ? "" : "Estimating size…" }
        return "≈ \(estimate.formatted(.byteCount(style: .file)))"
    }

    private func status(of page: PageRecord) -> PageStatus {
        if let band = page.confidenceBand { return .done(band) }
        if page.recognitionData != nil { return .done(.medium) }
        if queue.failed.contains(page.id) { return .failed }
        if queue.inFlight.contains(page.id) { return .recognizing }
        return .queued
    }

    private enum Destination { case share, files }

    private var canExport: Bool { !exporter.isExporting && !isReading && !pages.isEmpty }

    private func export(to destination: Destination) async {
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

    private func rename() {
        do { try library.rename(record, to: draftTitle) } catch { errorMessage = error.localizedDescription }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct PageCard: View {
    let page: PageRecord
    let status: PageStatus
    let thumbnailURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ThumbnailView(url: thumbnailURL)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { statusChip.padding(6) }
            Text("Page \(page.index + 1)")
                .font(.subheadline.weight(.medium))
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Image(systemName: bandSymbol(band))
                .foregroundStyle(bandColor(band))
                .padding(6)
                .background(.regularMaterial, in: Circle())
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(6)
                .background(.regularMaterial, in: Circle())
        }
    }

    private var statusText: String {
        switch status {
        case .queued: "Waiting"
        case .recognizing: "Reading text…"
        case .done(.high): "Text read, high confidence"
        case .done(.medium): "Text read, medium confidence"
        case .done(.low): "Text read, low confidence — check it"
        case .failed: "Couldn't read text"
        }
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
