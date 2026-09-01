import SwiftUI
import PhotosUI
import ScannerCore
import CaptureKit
import DesignSystem

struct HomeView: View {
    @Environment(ScanSessionModel.self) private var session
    @State private var showingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var path: [Route] = []

    enum Route: Hashable { case review }

    var body: some View {
        NavigationStack(path: $path) {
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
                actions
            }
            .padding(DS.Spacing.l)
            .navigationTitle("Scanner")
            .navigationDestination(for: Route.self) { _ in ReviewView() }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentCameraView { outcome in
                    showingCamera = false
                    switch outcome {
                    case .scanned(let images) where !images.isEmpty:
                        session.start(with: images, source: .documentCamera)
                        path.append(.review)
                    case .failed(let message):
                        session.errorMessage = message
                    default:
                        break
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.errorMessage ?? "")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: DS.Spacing.m) {
            Button {
                showingCamera = true
            } label: {
                Label("Scan document", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!DocumentCameraView.isSupported)

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 25, matching: .images) {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !DocumentCameraView.isSupported {
                Text("The camera isn't available here (Simulator). Import a photo instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            pickerItems = []
        }
        var images: [CGImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data)?.uprightCGImage() {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            session.errorMessage = "Those photos couldn't be read."
            return
        }
        session.start(with: images, source: .photoLibrary)
        path.append(.review)
    }
}
