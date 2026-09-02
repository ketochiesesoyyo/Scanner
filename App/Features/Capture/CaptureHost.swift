import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ScannerCore
import CaptureKit
import DesignSystem

/// Attaches the camera cover, the Photos picker, progress and errors for one `CaptureCoordinator`.
struct CaptureHost: ViewModifier {
    @Bindable var capture: CaptureCoordinator
    let target: ScanRecord?
    let onCompleted: (ScanRecord) -> Void

    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $capture.showingCamera, onDismiss: {
                // The cover is now fully gone — only here is it safe to do work and to push.
                guard let pages = capture.pendingCapture, !pages.isEmpty else { return }
                capture.pendingCapture = nil
                #if DEBUG
                print("PHASE camera dismissed; ingesting \(pages.count) page(s)")
                #endif
                let items = pages.map { CaptureCoordinator.Item.captured($0.data, auto: $0.auto) }
                Task { await ingest(items, source: .documentCamera) }
            }) {
                CaptureView { pages in
                    capture.pendingCapture = pages // ingested after onDismiss, off the main thread
                    capture.showingCamera = false
                } onCancel: {
                    capture.showingCamera = false
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $capture.showingPhotoPicker, selection: $capture.pickerItems, maxSelectionCount: 25, matching: .images)
            .fileImporter(isPresented: $capture.showingFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return } // cancel is normal
                Task {
                    let (items, problems) = await Task.detached { CaptureCoordinator.loadItems(from: urls) }.value
                    if let problem = problems.first { capture.errorMessage = problem }
                    guard !items.isEmpty else { return }
                    #if DEBUG
                    print("PHASE files load: \(items.count) page(s) from \(urls.count) file(s)")
                    #endif
                    await ingest(items, source: .files)
                }
            }
            .onChange(of: capture.pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    let loaded = await capture.loadPickerItems(items)
                    capture.pickerItems = []
                    guard !loaded.isEmpty else {
                        capture.errorMessage = "Those photos couldn't be read."
                        return
                    }
                    await ingest(loaded, source: .photoLibrary)
                }
            }
            .overlay {
                if capture.isWorking {
                    ProgressView(capture.progress ?? "Working…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(capture.errorMessage ?? "")
            }
    }

    private func ingest(_ items: [CaptureCoordinator.Item], source: CaptureSource) async {
        guard let record = await capture.ingest(items, source: source, into: target, library: library, queue: queue) else { return }
        switch source {
        case .photoLibrary, .files:
            // These pickers give no dismissal callback, and pushing while their sheet is still
            // animating away wedges the transition on device (dead touches, spinners keep moving).
            // A fast ingest can finish before the animation does — let it settle.
            try? await Task.sleep(for: .milliseconds(800))
            #if DEBUG
            print("PHASE push review (\(source.rawValue))")
            #endif
            onCompleted(record)
        default:
            #if DEBUG
            print("PHASE push review (\(source.rawValue))")
            #endif
            onCompleted(record)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { capture.errorMessage != nil },
            set: { if !$0 { capture.errorMessage = nil } }
        )
    }
}

extension View {
    func captureHost(_ capture: CaptureCoordinator, target: ScanRecord? = nil, onCompleted: @escaping (ScanRecord) -> Void) -> some View {
        modifier(CaptureHost(capture: capture, target: target, onCompleted: onCompleted))
    }
}

/// The two ways in. Camera is disabled where there is none (Simulator).
struct CaptureButtons: View {
    @Bindable var capture: CaptureCoordinator

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            Button {
                capture.showingCamera = true
            } label: {
                Label("Scan document", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!CameraEngine.isAvailable)

            HStack(spacing: DS.Spacing.s) {
                Button {
                    capture.showingPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    capture.showingFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !CameraEngine.isAvailable {
                Text("No camera here (Simulator) — import a photo instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
