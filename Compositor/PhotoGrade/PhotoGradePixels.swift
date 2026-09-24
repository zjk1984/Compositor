import AppKit
import CoreGraphics
import Foundation

/// Normalized RGB raster used by the native photo-grade metrics engine.
nonisolated struct PhotoGradePixels: Sendable {
    let width: Int
    let height: Int
    /// Interleaved RGB, row-major, 0…1.
    let rgb: [Float]

    var count: Int { width * height }

    func luminance() -> [Float] {
        var gray = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let base = i * 3
            gray[i] = 0.2126 * rgb[base] + 0.7152 * rgb[base + 1] + 0.0722 * rgb[base + 2]
        }
        return gray
    }

    static func from(_ image: CGImage) throws -> PhotoGradePixels {
        let width = image.width, height = image.height
        let context = try BrushRaster.context(width: width, height: height, mask: false)
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: context)
        guard let data = context.data else { throw PhotoGradeError.unreadableImage("Could not read pixels.") }
        let stride = context.bytesPerRow
        let source = data.assumingMemoryBound(to: UInt8.self)
        var rgb = [Float](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let src = y * stride + x * 4
                let dst = (y * width + x) * 3
                rgb[dst] = Float(source[src]) / 255
                rgb[dst + 1] = Float(source[src + 1]) / 255
                rgb[dst + 2] = Float(source[src + 2]) / 255
            }
        }
        return PhotoGradePixels(width: width, height: height, rgb: rgb)
    }
}

nonisolated enum PhotoGradeMath {
    static func clip(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    static func clip(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        min(upper, max(lower, value))
    }

    static func quantile(_ values: [Float], _ q: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        var sorted = values
        sorted.sort()
        let index = Int(Double(sorted.count - 1) * q)
        return sorted[min(max(0, index), sorted.count - 1)]
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var sorted = values
        sorted.sort()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) * 0.5
        }
        return sorted[mid]
    }

    static func log2(_ value: Float) -> Float {
        log(value) / log(2)
    }
}
