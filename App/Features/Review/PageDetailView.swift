import SwiftUI
import ScannerCore
import Telemetry
import DesignSystem

struct PageDetailView: View {
    let page: PageRecord

    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue
    @State private var image: CGImage?

    private var pageWarnings: [ScanWarning] {
        (page.document?.activeWarnings ?? []).filter { $0.pageIndex == page.index }
    }

    private func ignore(_ warning: ScanWarning) {
        guard let record = page.document else { return }
        try? library.ignoreWarning(warning.key, in: record)
        Telemetry.record(.qualityWarningResolved(type: warning.telemetryType, action: .ignore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                ZStack {
                    Color(.secondarySystemBackground)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
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
                            Text(recognition.text)
                                .font(.callout)
                                .textSelection(.enabled)
                            Text("\(recognition.lines.count) lines · confidence \(Int(recognition.meanConfidence * 100))%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if queue.failed.contains(page.id) {
                        Label("Couldn't read this page.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Button("Try again") { queue.retry(page) }
                            .buttonStyle(.bordered)
                    } else {
                        ProgressView("Reading text…")
                    }
                }
                let warnings = pageWarnings
                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text("Warnings").font(.headline)
                        ForEach(warnings, id: \.key) { warning in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text(warning.message(pageCount: page.document?.pages.count ?? 0))
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Ignore") { ignore(warning) }
                                    .font(.subheadline)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                ProcessingBadge()
            }
            .padding(DS.Spacing.l)
        }
        .navigationTitle("Page \(page.index + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let url = library.files.url(for: page.originalPath)
            image = await Task.detached(priority: .userInitiated) { try? ImageDecoder.image(at: url, maxPixelSize: 2048) }.value
        }
    }
}
