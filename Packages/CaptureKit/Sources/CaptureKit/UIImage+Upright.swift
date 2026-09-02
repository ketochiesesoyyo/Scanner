import UIKit

extension UIImage {
    /// A CGImage with the EXIF orientation baked in, so OCR and export can treat every page as `.up`.
    /// Safe off the main thread (UIGraphicsImageRenderer is documented thread-safe) — and it should be
    /// called there: a 12 MP render on the main thread is 100–300 ms of frozen UI per page.
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
