import Foundation

/// S/A/B/C quality tier from the raw-photo-grade evaluation engine.
enum PhotoGradeTier: String, Codable, CaseIterable, Sendable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"

    var label: String { rawValue }

    var sortRank: Int {
        switch self {
        case .s: 0
        case .a: 1
        case .b: 2
        case .c: 3
        }
    }
}

/// Scene-specific weight presets mirrored from `shared/scripts/eval_photo.py`.
enum PhotoGradePreset: String, CaseIterable, Identifiable, Sendable {
    case general, landscape, portrait, street, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .landscape: "Landscape"
        case .portrait: "Portrait"
        case .street: "Street"
        case .night: "Night"
        }
    }
}

/// Develop look recipes from the raw-photo-grade pipeline.
enum PhotoGradeLook: String, CaseIterable, Identifiable, Sendable {
    case natural, warmGolden = "warm-golden", portrait, coolCinematic = "cool-cinematic"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .natural: "Natural"
        case .warmGolden: "Warm Golden"
        case .portrait: "Portrait"
        case .coolCinematic: "Cool Cinematic"
        }
    }
}

enum PhotoGradeWorkflow: String, CaseIterable, Identifiable, Sendable {
    case evaluate
    case evaluateOrganize
    case pipeline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .evaluate: "Evaluate & Rank"
        case .evaluateOrganize: "Evaluate & Organize by Tier"
        case .pipeline: "Evaluate, Develop Keepers"
        }
    }
}

struct PhotoGradeEvaluation: Codable, Identifiable, Hashable, Sendable {
    let path: String
    let filename: String
    let overallScore: Double
    let tier: String
    let sharpness: Double
    let dynamicRange: Double
    let noiseControl: Double
    let colorHarmony: Double
    let composition: Double
    let flags: [String]
    let details: [String: JSONValue]

    var id: String { path }

    var tierValue: PhotoGradeTier { PhotoGradeTier(rawValue: tier) ?? .c }

    var fileURL: URL { URL(fileURLWithPath: path) }

    enum CodingKeys: String, CodingKey {
        case path, filename, tier, sharpness, composition, flags, details
        case overallScore = "overall_score"
        case dynamicRange = "dynamic_range"
        case noiseControl = "noise_control"
        case colorHarmony = "color_harmony"
    }
}

struct PhotoGradeBatch: Codable, Sendable {
    let device: String?
    let totalCount: Int
    let results: [PhotoGradeEvaluation]

    enum CodingKeys: String, CodingKey {
        case device, results
        case totalCount = "total_count"
    }
}

struct PhotoGradePipelineManifest: Codable, Sendable {
    struct Developed: Codable, Sendable {
        let source: String
        let tier: String
        let overallScore: Double
        let output: String

        enum CodingKeys: String, CodingKey {
            case source, tier, output
            case overallScore = "overall_score"
        }

        var outputURL: URL { URL(fileURLWithPath: output) }
    }

    let look: String
    let targetTiers: [String]
    let totalEvaluated: Int
    let totalDeveloped: Int
    let developed: [Developed]

    enum CodingKeys: String, CodingKey {
        case look, developed
        case targetTiers = "target_tiers"
        case totalEvaluated = "total_evaluated"
        case totalDeveloped = "total_developed"
    }
}

/// Loose JSON values for evaluation `details` without pinning every metric key.
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

enum PhotoGradeError: LocalizedError {
    case toolkitMissing
    case noPhotosFound
    case unreadableImage(String)
    case encodeFailed
    case scriptFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .toolkitMissing:
            "The raw-photo-grade reference bundle was not found in the app."
        case .noPhotosFound:
            "No supported photo files were found in the selected folder."
        case .unreadableImage(let message):
            "Could not read \(message)."
        case .encodeFailed:
            "The developed photo could not be encoded as JPEG."
        case .scriptFailed(let message):
            message
        case .invalidOutput(let message):
            message
        }
    }
}
