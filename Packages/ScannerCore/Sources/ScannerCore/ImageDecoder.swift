import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// ImageIO-only decoding, shared by persistence and the pipeline. Always applies EXIF orientation so
/// every consumer can treat a page as `.up`; `maxPixelSize` downsamples during decode (cheap on memory).
public enum ImageDecoder {
    public enum Failure: Error { case unreadable }

    public static func image(at url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure.unreadable }
        return try image(from: source, maxPixelSize: maxPixelSize)
    }

    public static func image(from data: Data, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        return try image(from: source, maxPixelSize: maxPixelSize)
    }

    /// Oriented pixel size without decoding the bitmap.
    public static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(of: source)
    }

    /// Preferred filename extension for the encoded bytes ("jpg", "heic", "png"); "jpg" when unknown.
    public static func fileExtension(of data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              let ext = type.preferredFilenameExtension else { return "jpg" }
        return ext
    }

    private static func image(from source: CGImageSource, maxPixelSize: Int?) throws -> CGImage {
        let size = pixelSize(of: source)
        let longSide = Int(max(size?.width ?? 0, size?.height ?? 0))
        let limit = maxPixelSize.map { min($0, longSide > 0 ? longSide : $0) } ?? longSide
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if limit > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = limit }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        return image
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let rotated = (5...8).contains(orientation)
        return rotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
