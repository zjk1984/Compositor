import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PhotoGradeExporter {
    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.92) throws {
        let data = try jpegData(image, quality: quality)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) }
            catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    static func jpegData(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoGradeError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: min(1, max(0, quality)),
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoGradeError.encodeFailed }
        return data as Data
    }
}
