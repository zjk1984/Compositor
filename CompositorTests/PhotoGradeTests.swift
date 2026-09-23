import CoreGraphics
import Foundation
import Testing
@testable import Compositor

struct PhotoGradeTests {
    @Test func decodesEvaluationBatchJSON() throws {
        let json = """
        {
          "device": "native",
          "total_count": 2,
          "results": [
            {
              "path": "/tmp/sharp.jpg",
              "filename": "sharp.jpg",
              "overall_score": 88.4,
              "tier": "S",
              "sharpness": 82.0,
              "dynamic_range": 76.5,
              "noise_control": 90.0,
              "color_harmony": 71.0,
              "composition": 84.0,
              "flags": [],
              "details": { "entropy": 5.1 }
            },
            {
              "path": "/tmp/blur.jpg",
              "filename": "blur.jpg",
              "overall_score": 41.2,
              "tier": "C",
              "sharpness": 18.0,
              "dynamic_range": 55.0,
              "noise_control": 60.0,
              "color_harmony": 65.0,
              "composition": 50.0,
              "flags": ["blurry"],
              "details": {}
            }
          ]
        }
        """
        let batch = try JSONDecoder().decode(PhotoGradeBatch.self, from: Data(json.utf8))
        #expect(batch.totalCount == 2)
        #expect(batch.results[0].tierValue == .s)
        #expect(batch.results[1].flags == ["blurry"])
        #expect(batch.results[0].details["entropy"]?.doubleValue == 5.1)
    }

    @Test func nativeServiceIsAvailable() {
        #expect(PhotoGradeService.isAvailable)
    }

    @Test func tierSortRankOrdersKeepersFirst() {
        let tiers: [PhotoGradeTier] = [.c, .a, .s, .b]
        #expect(tiers.sorted(by: { $0.sortRank < $1.sortRank }).map(\.rawValue) == ["S", "A", "B", "C"])
    }

    @Test func presetWeightsSumToOne() {
        for preset in PhotoGradePreset.allCases {
            let weights = PhotoGradeWeights.weights(for: preset)
            let total = weights.values.reduce(0, +)
            #expect(abs(total - 1.0) < 0.001)
        }
    }

    @Test func sharpnessDiscriminatesFlatAndDetailedImages() throws {
        let flat = try makeSolidImage(width: 600, height: 600, red: 0.47, green: 0.47, blue: 0.47)
        let detailed = try makeGridImage(width: 1000, height: 800)
        let flatEval = PhotoGradeEvaluator.evaluate(
            pixels: try PhotoGradePixels.from(flat),
            url: URL(fileURLWithPath: "/tmp/flat.jpg"),
            preset: .general
        )
        let detailedEval = PhotoGradeEvaluator.evaluate(
            pixels: try PhotoGradePixels.from(detailed),
            url: URL(fileURLWithPath: "/tmp/detailed.jpg"),
            preset: .general
        )
        #expect(detailedEval.sharpness > flatEval.sharpness)
        #expect(flatEval.flags.contains("blurry"))
    }

    @Test func clippingFlagsOverexposedImage() throws {
        let blown = try makeSolidImage(width: 600, height: 600, red: 1, green: 1, blue: 1)
        let evaluation = PhotoGradeEvaluator.evaluate(
            pixels: try PhotoGradePixels.from(blown),
            url: URL(fileURLWithPath: "/tmp/blown.jpg"),
            preset: .general
        )
        #expect(evaluation.flags.contains("clipped_highlights"))
    }

    @Test func lookRecipesProduceNonIdentitySettings() {
        for look in PhotoGradeLook.allCases {
            let settings = PhotoGradeLooks.cameraRawSettings(for: look)
            #expect(!settings.isIdentity)
        }
    }

    private func makeSolidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw PhotoGradeError.unreadableImage("test context")
        }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw PhotoGradeError.unreadableImage("test image") }
        return image
    }

    private func makeGridImage(width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw PhotoGradeError.unreadableImage("test context")
        }
        context.setFillColor(CGColor(srgbRed: 0.18, green: 0.22, blue: 0.29, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(srgbRed: 0.86, green: 0.71, blue: 0.2, alpha: 1))
        context.setLineWidth(3)
        for x in stride(from: 50, to: width - 50, by: 30) {
            context.move(to: CGPoint(x: x, y: 50))
            context.addLine(to: CGPoint(x: x, y: height - 50))
            context.strokePath()
        }
        for y in stride(from: 50, to: height - 50, by: 40) {
            context.move(to: CGPoint(x: 50, y: y))
            context.addLine(to: CGPoint(x: width - 50, y: y))
            context.strokePath()
        }
        context.setFillColor(CGColor(srgbRed: 0.94, green: 0.2, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 300, y: 220, width: 120, height: 120))
        guard let image = context.makeImage() else { throw PhotoGradeError.unreadableImage("test image") }
        return image
    }
}
