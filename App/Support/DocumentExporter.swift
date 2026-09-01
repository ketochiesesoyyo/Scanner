import SwiftUI
import UIKit

/// "Save to Files" without going through the share sheet (PRD EXP-01): the system document picker
/// copies the exported files wherever the user chooses — iCloud Drive, On My iPhone, any provider.
struct DocumentExporter: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
