import SwiftUI

/// The capture screen (CAP-01/CAP-02): live guidance, auto-capture with manual override, torch,
/// multi-page session, volume-button shutter.
public struct CaptureView: View {
    @State private var model = CameraModel()
    @State private var flashOpacity = 0.0
    @State private var confirmingCancel = false

    private let onFinish: ([CameraModel.CapturedPage]) -> Void
    private let onCancel: () -> Void

    public init(onFinish: @escaping ([CameraModel.CapturedPage]) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.permissionDenied {
                permissionDenied
            } else {
                CameraPreview(engine: model.engine, quad: model.quad) { model.shutterTapped() }
                    .ignoresSafeArea()
                Color.white.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)
                controls
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.shutterTick) {
            flashOpacity = 0.7
            withAnimation(.easeOut(duration: 0.25)) { flashOpacity = 0 }
        }
        .alert("Something went wrong", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Discard this scan?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Discard \(model.pages.count) page(s)", role: .destructive) { onCancel() }
            Button("Keep scanning", role: .cancel) {}
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    if model.pages.isEmpty { onCancel() } else { confirmingCancel = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Cancel")
                Spacer()
                Button {
                    model.autoCapture.toggle()
                } label: {
                    Text(model.autoCapture ? "Auto" : "Manual")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel(model.autoCapture ? "Automatic capture on" : "Automatic capture off")
                Button {
                    model.torchOn.toggle()
                } label: {
                    Image(systemName: model.torchOn ? "bolt.fill" : "bolt.slash")
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(model.torchOn ? "Torch on" : "Torch off")
            }
            .padding()

            Spacer()

            Text(guidanceText)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
                .accessibilityLabel(guidanceText)

            HStack {
                pagesBadge
                    .frame(width: 72, alignment: .leading)
                Spacer()
                Button {
                    model.shutterTapped()
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                        Circle().fill(.white).frame(width: 60, height: 60)
                    }
                }
                .accessibilityLabel("Take photo")
                Spacer()
                Button("Done") { onFinish(model.pages) }
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .disabled(model.pages.isEmpty)
                    .opacity(model.pages.isEmpty ? 0.4 : 1)
                    .frame(width: 72)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var pagesBadge: some View {
        if model.pages.isEmpty {
            Color.clear.frame(width: 44, height: 44)
        } else {
            Text("\(model.pages.count)")
                .font(.headline.monospacedDigit())
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("\(model.pages.count) pages captured")
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.ellipsis").font(.system(size: 44))
            Text("Scanner needs camera access").font(.title3.weight(.semibold))
            Text("Allow it in Settings to scan documents. Photos and Files import keep working without it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
            Button("Close", action: onCancel)
        }
        .padding(32)
        .foregroundStyle(.white)
    }

    private var guidanceText: String {
        switch model.guidance {
        case .searching: "Point at a document"
        case .moveCloser: "Move closer"
        case .includeEdges: "Include the whole page"
        case .moreLight: "More light"
        case .holdStill: "Hold still…"
        case .ready: "Ready"
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
