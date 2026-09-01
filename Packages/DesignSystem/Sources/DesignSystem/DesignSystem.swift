import SwiftUI

public enum DS {
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
    }
}

/// PRD §10 processing label. Shown wherever the app processes a document, so users can always tell
/// where their information is (target: ≥90% of tested users answer correctly).
public struct ProcessingBadge: View {
    public init() {}

    public var body: some View {
        Label("Processed on your iPhone", systemImage: "lock.iphone")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Processed on your iPhone. Nothing is uploaded.")
    }
}
