import Foundation
import CoreGraphics

/// Everything the library needs to persist one page: the untouched capture bytes plus a small
/// derivative for lists. Produced by `ImagePipeline.PageIngest`, consumed by `Library.addPage`.
public struct PageAssets: Sendable {
    public let originalData: Data
    /// File extension for `originalData` ("jpg", "heic", "png"…).
    public let originalExtension: String
    public let thumbnailData: Data
    /// Oriented pixel size of the original (EXIF rotation already applied).
    public let pixelSize: CGSize

    public init(originalData: Data, originalExtension: String, thumbnailData: Data, pixelSize: CGSize) {
        self.originalData = originalData
        self.originalExtension = originalExtension
        self.thumbnailData = thumbnailData
        self.pixelSize = pixelSize
    }
}
