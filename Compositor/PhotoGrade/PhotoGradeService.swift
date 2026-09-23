import Foundation

/// Runs the vendored raw-photo-grade Python toolkit bundled under `Compositor/Resources/raw-photo-grade`.
nonisolated enum PhotoGradeService {
    static func toolkitRoot() -> URL? {
        if let bundled = Bundle.main.url(forResource: "eval", withExtension: "py",
                                         subdirectory: "raw-photo-grade/photo-eval-grade/scripts") {
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

    static var isAvailable: Bool {
        toolkitRoot() != nil && FileManager.default.isExecutableFile(atPath: "/usr/bin/python3")
    }

    static func evaluate(folder: URL, preset: PhotoGradePreset, tiers: [PhotoGradeTier]) async throws -> PhotoGradeBatch {
        var arguments = [
            evalScript().path,
            folder.path,
            "--json",
            "--preset", preset.rawValue,
            "--device", "auto",
        ]
        if !tiers.isEmpty {
            arguments += ["--filter", tiers.map(\.rawValue).joined(separator: ",")]
        }
        let data = try await runPython(arguments: arguments)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PhotoGradeBatch.self, from: data)
        } catch {
            throw PhotoGradeError.invalidOutput(String(data: data, encoding: .utf8) ?? "Unreadable JSON")
        }
    }

    static func organize(folder: URL, preset: PhotoGradePreset, destination: URL) async throws -> PhotoGradeBatch {
        let arguments = [
            evalScript().path,
            folder.path,
            "--json",
            "--preset", preset.rawValue,
            "--device", "auto",
            "--organize", destination.path,
            "--organize-method", "copy",
        ]
        let data = try await runPython(arguments: arguments)
        return try JSONDecoder().decode(PhotoGradeBatch.self, from: data)
    }

    static func pipeline(folder: URL, preset: PhotoGradePreset, tiers: [PhotoGradeTier],
                         look: PhotoGradeLook, output: URL, preview: Bool, straighten: Bool) async throws -> PhotoGradePipelineManifest {
        let arguments = [
            pipelineScript().path,
            folder.path,
            "--tiers", tiers.map(\.rawValue).joined(separator: ","),
            "--preset", preset.rawValue,
            "--look", look.rawValue,
            "--out-dir", output.path,
        ] + (preview ? ["--preview"] : []) + (straighten ? ["--straighten"] : [])
        _ = try await runPython(arguments: arguments)
        let manifest = output.appendingPathComponent("pipeline_manifest.json")
        guard let data = try? Data(contentsOf: manifest) else {
            throw PhotoGradeError.invalidOutput("Pipeline finished without a manifest at \(manifest.path)")
        }
        return try JSONDecoder().decode(PhotoGradePipelineManifest.self, from: data)
    }

    private static func evalScript() throws -> URL {
        guard let root = toolkitRoot() else { throw PhotoGradeError.toolkitMissing }
        let script = root.appendingPathComponent("photo-eval-grade/scripts/eval.py")
        guard FileManager.default.fileExists(atPath: script.path) else { throw PhotoGradeError.toolkitMissing }
        return script
    }

    private static func pipelineScript() throws -> URL {
        guard let root = toolkitRoot() else { throw PhotoGradeError.toolkitMissing }
        let script = root.appendingPathComponent("photo-eval-grade/scripts/pipeline.py")
        guard FileManager.default.fileExists(atPath: script.path) else { throw PhotoGradeError.toolkitMissing }
        return script
    }

    private static func runPython(arguments: [String]) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw PhotoGradeError.pythonMissing
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = arguments
            if let root = toolkitRoot() { process.currentDirectoryURL = root }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: outData)
                } else {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: PhotoGradeError.scriptFailed(message?.isEmpty == false ? message! :
                        (fallback?.isEmpty == false ? fallback! : "Photo grade script failed.")))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
