import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScannerCore

public struct EncodedImage: Sendable {
    /// JPEG-backed, so CoreGraphics embeds the compressed bytes as-is when this is drawn into a PDF context.
    public let image: CGImage
    public let data: Data

    public var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
}

public enum ImageEncodingError: Error {
    case contextUnavailable, destinationUnavailable, encodingFailed, decodingFailed
}

public enum ImageEncoder {
    /// Downscales to the preset's long side and JPEG-encodes (PRD EXP-02).
    public static func jpeg(_ image: CGImage, preset: ExportPreset) throws -> EncodedImage {
        try jpeg(image, maxLongSide: preset.maxLongSide, quality: preset.jpegQuality)
    }

    public static func jpeg(_ image: CGImage, maxLongSide: Int?, quality: Double) throws -> EncodedImage {
        let source = try downscaled(image, maxLongSide: maxLongSide)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageEncodingError.destinationUnavailable
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, source, options)
        guard CGImageDestinationFinalize(destination) else { throw ImageEncodingError.encodingFailed }
        guard let imageSource = CGImageSourceCreateWithData(data, nil),
              let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageEncodingError.decodingFailed
        }
        return EncodedImage(image: decoded, data: data as Data)
    }

    /// Returns the input untouched when it already fits.
    public static func downscaled(_ image: CGImage, maxLongSide: Int?) throws -> CGImage {
        let longSide = max(image.width, image.height)
        guard let maxLongSide, longSide > maxLongSide else { return image }
        let scale = Double(maxLongSide) / Double(longSide)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw ImageEncodingError.contextUnavailable
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ImageEncodingError.contextUnavailable }
        return result
    }
}
