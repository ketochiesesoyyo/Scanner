import SwiftUI
import ScannerCore

/// Decodes a page file off the main actor, downsampled to `maxPixelSize`, and shows it scaled to fit.
struct ThumbnailView: View {
    let url: URL
    var maxPixelSize: Int = 400
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            }
        }
        .task(id: url) {
            let url = url
            let maxPixelSize = maxPixelSize
            image = await Task.detached(priority: .utility) { try? ImageDecoder.image(at: url, maxPixelSize: maxPixelSize) }.value
        }
    }
}
