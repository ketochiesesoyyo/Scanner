import Foundation
import CoreGraphics
import ScannerCore

/// Turns a capture into what the library stores: untouched original bytes + a list thumbnail.
public enum PageIngest {
    public static let thumbnailLongSide = 400
    static let thumbnailQuality = 0.8
    /// Used only when the source hands us a decoded bitmap (VisionKit); imported files keep their bytes.
    static let originalJPEGQuality = 0.95

    /// For sources that deliver a bitmap. The original is encoded once, at near-lossless quality.
    public static func prepare(image: CGImage) throws -> PageAssets {
        let original = try ImageEncoder.jpeg(image, maxLongSide: nil, quality: originalJPEGQuality)
        let thumbnail = try ImageEncoder.jpeg(image, maxLongSide: thumbnailLongSide, quality: thumbnailQuality)
        return PageAssets(
            originalData: original.data,
            originalExtension: "jpg",
            thumbnailData: thumbnail.data,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
    }

    /// For sources that deliver a file (Photos, Files, share extension). Bytes are kept verbatim —
    /// that *is* the original — and only the thumbnail is rendered.
    public static func prepare(imageData: Data) throws -> PageAssets {
        let thumbnailImage = try ImageDecoder.image(from: imageData, maxPixelSize: thumbnailLongSide)
        let thumbnail = try ImageEncoder.jpeg(thumbnailImage, maxLongSide: nil, quality: thumbnailQuality)
        let pixelSize = try ImageDecoder.pixelSize(of: imageData) ?? {
            let full = try ImageDecoder.image(from: imageData)
            return CGSize(width: full.width, height: full.height)
        }()
        return PageAssets(
            originalData: imageData,
            originalExtension: ImageDecoder.fileExtension(of: imageData),
            thumbnailData: thumbnail.data,
            pixelSize: pixelSize
        )
    }
}
