import SwiftUI
import LocalAuthentication

enum PrivacySettings {
    static let lockEnabledKey = "privacy.lockEnabled"
}

enum BiometricLock {
    /// True when the device has a passcode (and so Face ID / Touch ID / passcode can gate the app).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Runs entirely off any actor: the LAContext never crosses an isolation boundary.
    nonisolated static func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your scans")
        } catch {
            return false
        }
    }
}

/// Covers the app when the lock is on and the app comes back from the background (PRD §9 Security).
struct LockGate: ViewModifier {
    @AppStorage(PrivacySettings.lockEnabledKey) private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = false
    @State private var authenticating = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if lockEnabled && locked {
                    LockedView { Task { await unlock() } }
                        .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard lockEnabled else { return }
                switch phase {
                case .background: locked = true
                case .active: if locked { Task { await unlock() } }
                default: break
                }
            }
            .task {
                if lockEnabled {
                    locked = true
                    await unlock()
                }
            }
    }

    private func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        if await BiometricLock.authenticate() {
            withAnimation { locked = false }
        }
    }
}

private struct LockedView: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44, weight: .light))
                Text("Scanner is locked").font(.title3.weight(.semibold))
                Button("Unlock", action: unlock)
                    .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}
