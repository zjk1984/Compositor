import Foundation
import Testing
@testable import Compositor

struct PhotoGradeTests {
    @Test func decodesEvaluationBatchJSON() throws {
        let json = """
        {
          "device": "cpu",
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

    @Test func toolkitRootFindsBundledResourcesPath() {
        #expect(PhotoGradeService.toolkitRoot()?.lastPathComponent == "raw-photo-grade")
    }

    @Test func tierSortRankOrdersKeepersFirst() {
        let tiers: [PhotoGradeTier] = [.c, .a, .s, .b]
        #expect(tiers.sorted(by: { $0.sortRank < $1.sortRank }).map(\.rawValue) == ["S", "A", "B", "C"])
    }
}
