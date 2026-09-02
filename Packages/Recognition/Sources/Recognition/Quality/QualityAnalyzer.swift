import Foundation
import CoreGraphics
import ScannerCore

/// Per-page quality metrics from pixels + OCR (PRD QLT-01). Pure computation, no thresholds here.
public enum QualityAnalyzer {
    /// Grayscale working copy; metrics don't need more than ~512 px on the long side.
    struct LumaBuffer {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// Words below this OCR confidence count as "hard to read".
    public static let wordConfidenceFloor: Float = 0.45

    public static func quality(of image: CGImage, recognition: PageRecognition?, smudgeConfidence: Double?) -> PageQuality {
        quality(luma: luma(of: image), recognition: recognition, smudgeConfidence: smudgeConfidence)
    }

    static func quality(luma: LumaBuffer?, recognition: PageRecognition?, smudgeConfidence: Double?) -> PageQuality {
        guard let luma else {
            return PageQuality(blurVariance: .infinity, glareRatio: 0, shadowSpread: 0,
                               lowConfidenceShare: lowConfidenceShare(of: recognition), smudgeConfidence: smudgeConfidence)
        }
        return PageQuality(
            blurVariance: blurVariance(luma),
            glareRatio: glareRatio(luma),
            shadowSpread: shadowSpread(luma),
            lowConfidenceShare: lowConfidenceShare(of: recognition),
            smudgeConfidence: smudgeConfidence
        )
    }

    static func lowConfidenceShare(of recognition: PageRecognition?) -> Double? {
        guard let words = recognition?.words, !words.isEmpty else { return nil }
        return Double(words.filter { $0.confidence < wordConfidenceFloor }.count) / Double(words.count)
    }

    static func luma(of image: CGImage, maxLongSide: Int = 512) -> LumaBuffer? {
        let scale = min(1, Double(maxLongSide) / Double(max(image.width, image.height)))
        let width = max(8, Int(Double(image.width) * scale))
        let height = max(8, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { destination in
            for row in 0..<height {
                memcpy(destination.baseAddress! + row * width, base + row * bytesPerRow, width)
            }
        }
        return LumaBuffer(width: width, height: height, pixels: pixels)
    }

    /// Variance of a 4-neighbour Laplacian — the classic focus measure. Higher = sharper edges.
    static func blurVariance(_ luma: LumaBuffer) -> Double {
        let w = luma.width, h = luma.height
        guard w > 2, h > 2 else { return 0 }
        var sum = 0.0, sumSquares = 0.0
        let count = Double((w - 2) * (h - 2))
        luma.pixels.withUnsafeBufferPointer { p in
            for y in 1..<(h - 1) {
                let row = y * w
                for x in 1..<(w - 1) {
                    let i = row + x
                    let value = 4.0 * Double(p[i]) - Double(p[i - 1]) - Double(p[i + 1]) - Double(p[i - w]) - Double(p[i + w])
                    sum += value
                    sumSquares += value * value
                }
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }

    /// Fraction of clipped-highlight pixels. Paper under normal exposure sits well below 250;
    /// specular glare clips.
    static func glareRatio(_ luma: LumaBuffer) -> Double {
        let clipped = luma.pixels.reduce(into: 0) { if $1 >= 250 { $0 += 1 } }
        return Double(clipped) / Double(luma.pixels.count)
    }

    /// Estimates the paper brightness per block (85th percentile, so text doesn't drag it down) and
    /// returns the spread between the brightest and darkest blocks, 0…1.
    static func shadowSpread(_ luma: LumaBuffer, grid: Int = 4) -> Double {
        let w = luma.width, h = luma.height
        guard w >= grid, h >= grid else { return 0 }
        var minBackground = 255.0, maxBackground = 0.0
        for blockY in 0..<grid {
            for blockX in 0..<grid {
                var histogram = [Int](repeating: 0, count: 256)
                var total = 0
                let x0 = blockX * w / grid, x1 = (blockX + 1) * w / grid
                let y0 = blockY * h / grid, y1 = (blockY + 1) * h / grid
                for y in y0..<y1 {
                    let row = y * w
                    for x in x0..<x1 {
                        histogram[Int(luma.pixels[row + x])] += 1
                        total += 1
                    }
                }
                guard total > 0 else { continue }
                let target = Int(Double(total) * 0.85)
                var running = 0
                var percentile = 0
                for value in 0..<256 {
                    running += histogram[value]
                    if running >= target { percentile = value; break }
                }
                minBackground = min(minBackground, Double(percentile))
                maxBackground = max(maxBackground, Double(percentile))
            }
        }
        return max(0, (maxBackground - minBackground) / 255.0)
    }
}
