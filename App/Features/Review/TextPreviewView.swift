import SwiftUI
import DesignSystem

/// The recognized text of the whole document, readable before anything is shared —
/// you always know exactly what would leave the app (PRD: explain automation, verify before export).
struct TextPreviewView: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if text.isEmpty {
                    ContentUnavailableView("No text recognized yet", systemImage: "text.viewfinder")
                        .padding(.top, DS.Spacing.xl)
                } else {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Spacing.l)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text) { Label("Share text", systemImage: "square.and.arrow.up") }
                        .disabled(text.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !text.isEmpty {
                    Text("\(text.split(whereSeparator: \.isWhitespace).count) words · \(text.count) characters · you can select and copy")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(DS.Spacing.s)
                        .background(.bar)
                }
            }
        }
    }
}
