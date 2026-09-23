import AppKit
import CoreGraphics
import Foundation

/// Horizon straightening ported from raw-photo-grade `shared/scripts/crop.py`.
nonisolated enum PhotoGradeStraighten {
    static func tiltAngleDegrees(_ image: CGImage) throws -> Double {
        let pixels = try PhotoGradePixels.from(image)
        let gray = pixels.luminance()
        let step = max(1, min(pixels.width, pixels.height) / 800)
        let sw = (pixels.width + step - 1) / step
        let sh = (pixels.height + step - 1) / step
        var sampled = [Float](repeating: 0, count: sw * sh)
        for sy in 0..<sh {
            for sx in 0..<sw {
                let x = min(sx * step, pixels.width - 1)
                let y = min(sy * step, pixels.height - 1)
                sampled[sy * sw + sx] = gray[y * pixels.width + x]
            }
        }
        return PhotoGradeEvaluatorTilt.estimate(gray: sampled, width: sw, height: sh, quantile: 0.97, step: 0.25)
    }

    static func apply(_ image: CGImage, minimumDegrees: Double = 0.15) throws -> CGImage {
        let angle = try tiltAngleDegrees(image)
        guard abs(angle) >= minimumDegrees else { return image }
        return try rotate(image, degrees: angle)
    }

    private static func rotate(_ image: CGImage, degrees: Double) throws -> CGImage {
        let radians = degrees * .pi / 180
        let width = CGFloat(image.width), height = CGFloat(image.height)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: width / 2, y: height / 2)
        transform = transform.rotated(by: CGFloat(radians))
        transform = transform.translatedBy(x: -width / 2, y: -height / 2)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: Int(width) * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw PhotoGradeError.unreadableImage("Could not straighten image.")
        }
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rotated = context.makeImage() else {
            throw PhotoGradeError.unreadableImage("Could not straighten image.")
        }
        return try cropInscribed(rotated, angleDegrees: degrees)
    }

    private static func cropInscribed(_ image: CGImage, angleDegrees: Double) throws -> CGImage {
        let radians = abs(angleDegrees) * .pi / 180
        let width = Double(image.width), height = Double(image.height)
        let cosA = abs(cos(radians)), sinA = abs(sin(radians))
        let newWidth = Int((width * cosA - height * sinA).rounded(.down))
        let newHeight = Int((height * cosA - width * sinA).rounded(.down))
        guard newWidth > 0, newHeight > 0 else { return image }
        let x = (image.width - newWidth) / 2
        let y = (image.height - newHeight) / 2
        return image.cropping(to: CGRect(x: x, y: y, width: newWidth, height: newHeight)) ?? image
    }
}

/// Shared tilt estimation helpers extracted for pipeline straightening.
nonisolated enum PhotoGradeEvaluatorTilt {
    static func estimate(gray: [Float], width: Int, height: Int, quantile: Double, step: Double) -> Double {
        var magnitudes: [(x: Int, y: Int, mag: Float)] = []
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let gx = gray[idx + 1] - gray[idx - 1]
                let gy = gray[idx + width] - gray[idx - width]
                magnitudes.append((x, y, hypot(gx, gy)))
            }
        }
        guard magnitudes.count >= 200 else { return 0 }
        let threshold = PhotoGradeMath.quantile(magnitudes.map(\.mag), quantile)
        let strong = magnitudes.filter { $0.mag >= max(threshold, 1e-4) }
        guard strong.count >= 200 else { return 0 }

        let cx = Double(width) / 2, cy = Double(height) / 2
        var bestScore = 0.0, bestAngle = 0.0
        var theta = -10.0
        while theta <= 10.001 {
            var bins: [Double: Double] = [:]
            let radians = (90 + theta) * .pi / 180
            let cosR = cos(radians), sinR = sin(radians)
            for point in strong {
                let xs = Double(point.x) - cx, ys = Double(point.y) - cy
                let rho = xs * cosR + ys * sinR
                let key = floor(rho * 2.0)
                bins[key, default: 0] += Double(point.mag)
            }
            let score = bins.values.max() ?? 0
            if score > bestScore {
                bestScore = score
                bestAngle = theta
            }
            theta += step
        }
        return abs(bestAngle) <= 10 ? bestAngle : 0
    }
}
