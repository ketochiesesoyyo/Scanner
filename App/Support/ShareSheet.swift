import SwiftUI
import UIKit

/// PRD EXP-01: export goes through the system share sheet — Files, Mail, AirDrop, any app the user chooses.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
