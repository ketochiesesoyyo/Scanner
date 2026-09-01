import SwiftUI
import ScannerCore
import DesignSystem

struct PageDetailView: View {
    let page: ScanPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Image(decorative: page.original, scale: 1)
                    .resizable()
                    .scaledToFit()
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
                    } else {
                        ProgressView("Reading text…")
                    }
                }
            }
            .padding(DS.Spacing.l)
        }
        .navigationTitle("Page")
        .navigationBarTitleDisplayMode(.inline)
    }
}
