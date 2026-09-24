import Foundation

nonisolated enum PhotoGradeOrganizer {
    static func organize(results: [PhotoGradeEvaluation], destination: URL, method: OrganizeMethod = .copy) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for evaluation in results {
            let tierFolder = destination.appendingPathComponent(evaluation.tier, isDirectory: true)
            try FileManager.default.createDirectory(at: tierFolder, withIntermediateDirectories: true)
            let source = evaluation.fileURL
            let target = tierFolder.appendingPathComponent(source.lastPathComponent)
            switch method {
            case .copy:
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: source, to: target)
            case .move:
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: source, to: target)
            case .symlink:
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
            }
        }
    }
}

nonisolated enum OrganizeMethod: Sendable {
    case copy, move, symlink
}
