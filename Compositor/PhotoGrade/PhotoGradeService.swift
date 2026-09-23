import Foundation

/// Native photo grading: evaluation, tier organization, and develop pipeline.
nonisolated enum PhotoGradeService {
    static func toolkitRoot() -> URL? {
        if let bundled = Bundle.main.url(forResource: "eval-presets", withExtension: "json",
                                         subdirectory: "raw-photo-grade/photo-eval-grade/references") {
            return bundled.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        }
        if let env = ProcessInfo.processInfo.environment["PHOTOGRADE_TOOLKIT"],
           FileManager.default.fileExists(atPath: env) {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/raw-photo-grade", isDirectory: true)
        if FileManager.default.fileExists(atPath: dev.path) { return dev }
        return nil
    }

    /// Native engine is always available; bundled toolkit docs remain optional reference material.
    static var isAvailable: Bool { true }

    static func evaluate(folder: URL, preset: PhotoGradePreset, tiers: [PhotoGradeTier]) async throws -> PhotoGradeBatch {
        let files = PhotoGradeImageLoader.collect(in: folder)
        guard !files.isEmpty else { throw PhotoGradeError.noPhotosFound }

        var results: [PhotoGradeEvaluation] = []
        for file in files {
            do {
                results.append(try PhotoGradeEvaluator.evaluate(url: file, preset: preset))
            } catch {
                continue
            }
        }
        guard !results.isEmpty else { throw PhotoGradeError.noPhotosFound }

        results.sort { $0.overallScore > $1.overallScore }
        if !tiers.isEmpty {
            let allowed = Set(tiers.map(\.rawValue))
            results = results.filter { allowed.contains($0.tier) }
        }

        return PhotoGradeBatch(device: "native", totalCount: results.count, results: results)
    }

    static func organize(folder: URL, preset: PhotoGradePreset, destination: URL) async throws -> PhotoGradeBatch {
        let batch = try await evaluate(folder: folder, preset: preset, tiers: [])
        try PhotoGradeOrganizer.organize(results: batch.results, destination: destination, method: .copy)
        return batch
    }

    static func pipeline(folder: URL, preset: PhotoGradePreset, tiers: [PhotoGradeTier],
                         look: PhotoGradeLook, output: URL, preview: Bool, straighten: Bool) async throws -> PhotoGradePipelineManifest {
        try await PhotoGradePipeline.run(
            folder: folder, preset: preset, tiers: tiers, look: look,
            output: output, preview: preview, straighten: straighten
        )
    }
}
