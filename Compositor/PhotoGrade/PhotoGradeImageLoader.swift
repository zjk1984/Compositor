import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Loads and downsamples photos for evaluation and pipeline develop.
nonisolated enum PhotoGradeImageLoader {
    static let maxEvaluationEdge = 1920

    private static let rawExtensions: Set<String> = [
        "nef", "cr2", "cr3", "arw", "raf", "orf", "rw2", "pef", "srw", "dng",
    ]
    private static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "webp", "heic", "heif",
    ]

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return rawExtensions.contains(ext) || standardExtensions.contains(ext)
    }

    static func collect(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
            guard !(try? file.resourceValues(forKeys: [.isHiddenKey]).isHidden ?? false) ?? false else { continue }
            guard !file.lastPathComponent.hasPrefix(".") else { continue }
            if isSupported(file) { files.append(file) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func loadEvaluationPixels(_ url: URL) throws -> PhotoGradePixels {
        let image = try loadCGImage(url, maxEdge: maxEvaluationEdge)
        return try PhotoGradePixels.from(image)
    }

    static func loadDevelopedImage(_ url: URL, maxEdge: Int?) throws -> CGImage {
        try loadCGImage(url, maxEdge: maxEdge)
    }

    private static func loadCGImage(_ url: URL, maxEdge: Int?) throws -> CGImage {
        if RawImporter.matches(url) {
            let limit = maxEdge.map { CGFloat($0) }
            return try RawImporter.develop(url, settings: asShotSettings(url), limit: limit)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PhotoGradeError.unreadableImage(url.lastPathComponent)
        }
        guard let maxEdge, max(image.width, image.height) > maxEdge else { return image }
        return try downsample(image, maxEdge: maxEdge)
    }

    private static func asShotSettings(_ url: URL) -> RawDevelopSettings {
        RawImporter.asShot(url) ?? RawDevelopSettings()
    }

    private static func downsample(_ image: CGImage, maxEdge: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        let scale = Double(maxEdge) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw PhotoGradeError.unreadableImage("Could not resize image.")
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else {
            throw PhotoGradeError.unreadableImage("Could not resize image.")
        }
        return scaled
    }
}
