import CoreGraphics
import Foundation

nonisolated enum PhotoGradePipeline {
    static func run(folder: URL, preset: PhotoGradePreset, tiers: [PhotoGradeTier],
                    look: PhotoGradeLook, output: URL, preview: Bool, straighten: Bool) async throws -> PhotoGradePipelineManifest {
        let files = PhotoGradeImageLoader.collect(in: folder)
        guard !files.isEmpty else { throw PhotoGradeError.noPhotosFound }

        var evaluations: [PhotoGradeEvaluation] = []
        for file in files {
            do {
                evaluations.append(try PhotoGradeEvaluator.evaluate(url: file, preset: preset))
            } catch {
                continue
            }
        }
        evaluations.sort { $0.overallScore > $1.overallScore }

        let allowed = Set(tiers.map(\.rawValue))
        let keepers = evaluations.filter { allowed.contains($0.tier) }

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var developed: [PhotoGradePipelineManifest.Developed] = []
        let maxEdge = preview ? 1600 : nil

        for keeper in keepers {
            let source = keeper.fileURL
            let dest = output.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)_graded.jpg")
            do {
                try develop(source: source, look: look, maxEdge: maxEdge, straighten: straighten, destination: dest)
                developed.append(.init(
                    source: source.path,
                    tier: keeper.tier,
                    overallScore: keeper.overallScore,
                    output: dest.path
                ))
            } catch {
                continue
            }
        }

        let manifest = PhotoGradePipelineManifest(
            look: look.rawValue,
            targetTiers: Array(allowed),
            totalEvaluated: evaluations.count,
            totalDeveloped: developed.count,
            developed: developed
        )
        let manifestURL = output.appendingPathComponent("pipeline_manifest.json")
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        return manifest
    }

    private static func develop(source: URL, look: PhotoGradeLook, maxEdge: Int?, straighten: Bool, destination: URL) throws {
        var image = try PhotoGradeImageLoader.loadDevelopedImage(source, maxEdge: maxEdge)
        image = try PhotoGradeLooks.apply(look, to: image)
        if straighten {
            image = try PhotoGradeStraighten.apply(image)
        }
        try PhotoGradeExporter.writeJPEG(image, to: destination)
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
