import SwiftUI
import ScannerCore
import DesignSystem

struct ReviewView: View {
    @Environment(ScanSessionModel.self) private var session
    @State private var preset: ExportPreset = .standard
    @State private var shareItem: ShareItem?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.m)]

    var body: some View {
        Group {
            if let document = session.document {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.l) {
                        header(for: document)
                        LazyVGrid(columns: columns, spacing: DS.Spacing.m) {
                            ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                                NavigationLink(value: page.id) {
                                    PageCard(page: page, index: index, status: session.status[page.id] ?? .queued)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(DS.Spacing.l)
                }
                .navigationDestination(for: UUID.self) { id in
                    if let page = document.pages.first(where: { $0.id == id }) {
                        PageDetailView(page: page)
                    }
                }
                .safeAreaInset(edge: .bottom) { exportBar }
            } else {
                ContentUnavailableView("No scan in progress", systemImage: "doc.viewfinder")
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func header(for document: ScanDocument) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(document.title).font(.title3.weight(.semibold))
            HStack(spacing: DS.Spacing.m) {
                Text("^[\(document.pages.count) page](inflect: true)")
                    .foregroundStyle(.secondary)
                if session.isRecognizing {
                    Label("Reading text… \(session.recognizedPageCount) of \(document.pages.count)", systemImage: "text.viewfinder")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Text recognized", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            ProcessingBadge()
        }
    }

    private var exportBar: some View {
        VStack(spacing: DS.Spacing.s) {
            Picker("Quality", selection: $preset) {
                Text("Email").tag(ExportPreset.email)
                Text("Standard").tag(ExportPreset.standard)
                Text("Archive").tag(ExportPreset.archive)
            }
            .pickerStyle(.segmented)

            Button {
                Task { await export() }
            } label: {
                Group {
                    if session.isExporting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Export searchable PDF", systemImage: "square.and.arrow.up")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isExporting || session.isRecognizing)

            if session.isRecognizing {
                Text("Export unlocks when every page has been read.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.m)
        .background(.bar)
    }

    private func export() async {
        do {
            shareItem = ShareItem(url: try await session.exportPDF(preset: preset))
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PageCard: View {
    let page: ScanPage
    let index: Int
    let status: ScanSessionModel.PageStatus

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(decorative: page.original, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { statusChip.padding(6) }
            Text("Page \(index + 1)")
                .font(.subheadline.weight(.medium))
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(index + 1), \(statusText)")
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
