import SwiftUI
import ScannerCore
import DesignSystem

/// Identifies a page across navigation without carrying a value snapshot (which changes as OCR lands).
struct PageRef: Hashable {
    let scanID: UUID
    let pageID: UUID
}

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue

    @State private var capture = CaptureCoordinator()
    @State private var path = NavigationPath()
    @State private var showingSettings = false
    @State private var errorMessage: String?

    private var ready: [ScanRecord] { library.records.filter { $0.state == .ready } }
    private var interrupted: [ScanRecord] { library.records.filter { $0.state == .capturing && !$0.pages.isEmpty } }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if ready.isEmpty && interrupted.isEmpty {
                    EmptyLibraryView()
                } else {
                    libraryList
                }
            }
            .safeAreaInset(edge: .bottom) {
                CaptureButtons(capture: capture)
                    .padding(DS.Spacing.m)
                    .background(.bar)
            }
            .navigationTitle("Scanner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { ReviewView(scanID: $0) }
            .navigationDestination(for: PageRef.self) { PageDetailView(ref: $0) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .captureHost(capture) { record in path.append(record.id) }
            .task {
                _ = library.recoverableDrafts() // prunes empty drafts on launch
                queue.resumePending()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-openFirstScan"), let first = ready.first, path.isEmpty {
                    path.append(first.id)
                }
                #endif
            }
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var libraryList: some View {
        List {
            if !interrupted.isEmpty {
                Section("Interrupted") {
                    ForEach(interrupted) { draft in
                        NavigationLink(value: draft.id) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Continue \"\(draft.title)\"")
                                    Text("^[\(draft.pages.count) page](inflect: true) saved before the app closed")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "arrow.uturn.forward.circle.fill")
                            }
                        }
                    }
                }
            }
            Section {
                ForEach(ready) { record in
                    NavigationLink(value: record.id) {
                        LibraryRow(record: record, thumbnailURL: record.orderedPages.first.map { library.files.url(for: $0.thumbnailPath) })
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("^[\(ready.count) scan](inflect: true)")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func delete(at offsets: IndexSet) {
        do {
            for record in offsets.map({ ready[$0] }) { try library.delete(record) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: DS.Spacing.s) {
                Text("Scan it. Verify it. Send it where it belongs.")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Documents become searchable PDFs, entirely on your iPhone.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            ProcessingBadge()
            Spacer()
        }
        .padding(DS.Spacing.l)
        .frame(maxWidth: .infinity)
    }
}

private struct LibraryRow: View {
    let record: ScanRecord
    let thumbnailURL: URL?

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Group {
                if let thumbnailURL {
                    ThumbnailView(url: thumbnailURL, maxPixelSize: 160)
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: 56, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(record.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: DS.Spacing.s) {
                    Text("^[\(record.pages.count) page](inflect: true)")
                    Text("·")
                    Text(record.createdAt, format: .dateTime.day().month(.abbreviated))
                    if record.isFullyRecognized {
                        Image(systemName: "text.viewfinder").accessibilityLabel("Text recognized")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
