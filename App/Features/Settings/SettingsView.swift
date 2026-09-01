import SwiftUI
import ScannerCore
import DesignSystem

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @Environment(RecognitionQueue.self) private var queue
    @Environment(ExportService.self) private var exporter
    @AppStorage(PrivacySettings.lockEnabledKey) private var lockEnabled = false

    @State private var confirmingDelete = false
    @State private var lockUnavailable = false
    @State private var storageBytes = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Require Face ID or passcode", isOn: $lockEnabled)
                        .onChange(of: lockEnabled) { _, enabled in
                            if enabled && !BiometricLock.isAvailable {
                                lockEnabled = false
                                lockUnavailable = true
                            }
                        }
                    Text("Locks Scanner whenever you leave it. Uses the same Face ID or passcode as your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }

                Section {
                    LabeledContent("Stored on this iPhone", value: storageBytes.formatted(.byteCount(style: .file)))
                    Text("Scans, thumbnails and recognized text stay on this device, protected by iOS file encryption. Nothing is uploaded — there is no server. Exports go only where you send them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Delete all scans", role: .destructive) { confirmingDelete = true }
                } header: {
                    Text("Your data")
                }

                Section {
                    LabeledContent("Text recognition", value: "Spanish, English · on-device")
                    LabeledContent("Version", value: Self.version)
                } header: {
                    Text("About")
                } footer: {
                    ProcessingBadge().padding(.top, DS.Spacing.s)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all scans?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { deleteEverything() }
            } message: {
                Text("Removes every scan and its files from this iPhone. Files you already exported are not affected. This can't be undone.")
            }
            .alert("Set a passcode first", isPresented: $lockUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Turn on a passcode or Face ID in the Settings app, then come back to lock Scanner.")
            }
            .alert("Something went wrong", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { storageBytes = library.files.totalSize() }
        }
    }

    private func deleteEverything() {
        queue.cancelAll()
        exporter.clearCache()
        do {
            try library.deleteEverything()
            storageBytes = library.files.totalSize()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
