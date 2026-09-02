import SwiftUI
import PhotosUI
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
                capture.cameraDismissed = true
                if let record = capture.pendingPush {
                    capture.pendingPush = nil
                    onCompleted(record)
                }
            }) {
                DocumentCameraView { outcome in
                    capture.showingCamera = false
                    switch outcome {
                    case .scanned(let images) where !images.isEmpty:
                        Task { await ingest(images.map(CaptureCoordinator.Item.camera), source: .documentCamera) }
                    case .failed(let message):
                        capture.errorMessage = message
                    default:
                        break
                    }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $capture.showingPhotoPicker, selection: $capture.pickerItems, maxSelectionCount: 25, matching: .images)
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
        if source == .documentCamera && !capture.cameraDismissed {
            capture.pendingPush = record // onDismiss pushes once the cover is gone
        } else {
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
            .disabled(!DocumentCameraView.isSupported)

            Button {
                capture.showingPhotoPicker = true
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if !DocumentCameraView.isSupported {
                Text("No camera here (Simulator) — import a photo instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
