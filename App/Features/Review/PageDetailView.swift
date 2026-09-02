import SwiftUI
import ScannerCore
import Telemetry
import DesignSystem

struct PageDetailView: View {
    let ref: PageRef

    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue
    @State private var image: CGImage?

    private var page: PageRecord? {
        library.record(id: ref.scanID)?.pages.first { $0.id == ref.pageID }
    }

    var body: some View {
        Group {
            if let page {
                content(page)
            } else {
                ContentUnavailableView("Page not found", systemImage: "doc")
            }
        }
        .navigationTitle(page.map { "Page \($0.index + 1)" } ?? "Page")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ref.pageID) {
            guard let page else { return }
            let url = library.files.url(for: page.originalPath)
            image = await Task.detached(priority: .userInitiated) { try? ImageDecoder.image(at: url, maxPixelSize: 2048) }.value
        }
    }

    @ViewBuilder
    private func content(_ page: PageRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                ZStack {
                    Color(.secondarySystemBackground)
                    if let image {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .aspectRatio(page.pixelSize, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("Recognized text").font(.headline)
                    if let recognition = page.recognition {
                        if recognition.isEmpty {
                            Text("No text was found on this page.").foregroundStyle(.secondary)
                        } else {
                            Text(recognition.text).font(.callout).textSelection(.enabled)
                            Text("\(recognition.lines.count) lines · confidence \(Int(recognition.meanConfidence * 100))%")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if queue.failed.contains(page.id) {
                        Label("Couldn't read this page.", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        Button("Try again") { queue.retry(pageID: page.id, inScan: ref.scanID) }.buttonStyle(.bordered)
                    } else {
                        ProgressView("Reading text…")
                    }
                }

                let warnings = pageWarnings(page)
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text("Warnings").font(.headline)
                        ForEach(warnings, id: \.key) { warning in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                                Text(warning.message(pageCount: library.record(id: ref.scanID)?.pages.count ?? 0))
                                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                Button("Ignore") { ignore(warning) }
                                    .font(.subheadline).buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                ProcessingBadge()
            }
            .padding(DS.Spacing.l)
        }
    }

    private func pageWarnings(_ page: PageRecord) -> [ScanWarning] {
        (library.record(id: ref.scanID)?.activeWarnings ?? []).filter { $0.pageIndex == page.index }
    }

    private func ignore(_ warning: ScanWarning) {
        try? library.ignoreWarning(warning.key, inScan: ref.scanID)
        Telemetry.record(.qualityWarningResolved(type: warning.telemetryType, action: .ignore))
    }
}
