import UIKit

extension UIImage {
    /// A CGImage with the EXIF orientation baked in, so OCR and export can treat every page as `.up`.
    @MainActor
    public func uprightCGImage() -> CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: pixelSize, format: format)
            .image { _ in draw(in: CGRect(origin: .zero, size: pixelSize)) }
            .cgImage
    }
}
