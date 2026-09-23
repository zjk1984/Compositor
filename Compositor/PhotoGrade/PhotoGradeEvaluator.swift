import Foundation

/// Scene-specific metric weights mirrored from `shared/scripts/eval_photo.py`.
nonisolated enum PhotoGradeWeights {
    static let general: [String: Double] = [
        "sharpness": 0.35, "dynamic_range": 0.25, "noise_control": 0.15,
        "color_harmony": 0.15, "composition": 0.10,
    ]

    static func weights(for preset: PhotoGradePreset) -> [String: Double] {
        switch preset {
        case .general: general
        case .landscape: [
            "sharpness": 0.30, "dynamic_range": 0.35, "noise_control": 0.15,
            "color_harmony": 0.10, "composition": 0.10,
        ]
        case .portrait: [
            "sharpness": 0.35, "dynamic_range": 0.20, "noise_control": 0.20,
            "color_harmony": 0.15, "composition": 0.10,
        ]
        case .street: [
            "sharpness": 0.25, "dynamic_range": 0.20, "noise_control": 0.10,
            "color_harmony": 0.20, "composition": 0.25,
        ]
        case .night: [
            "sharpness": 0.25, "dynamic_range": 0.30, "noise_control": 0.30,
            "color_harmony": 0.10, "composition": 0.05,
        ]
        }
    }
}

/// Native S/A/B/C evaluation engine ported from raw-photo-grade `eval_photo.py`.
nonisolated enum PhotoGradeEvaluator {
    static func evaluate(url: URL, preset: PhotoGradePreset) throws -> PhotoGradeEvaluation {
        let pixels = try PhotoGradeImageLoader.loadEvaluationPixels(url)
        return evaluate(pixels: pixels, url: url, preset: preset)
    }

    static func evaluate(pixels: PhotoGradePixels, url: URL, preset: PhotoGradePreset) -> PhotoGradeEvaluation {
        let weights = PhotoGradeWeights.weights(for: preset)
        let gray = pixels.luminance()

        let (sharpness, rawSharp) = computeSharpness(gray: gray, width: pixels.width, height: pixels.height)
        var flags: [String] = []
        let (dynamicRange, drDetails, drFlags) = computeDynamicRange(gray: gray)
        flags.append(contentsOf: drFlags)
        let (noiseScore, rawNoise) = computeNoiseControl(gray: gray, width: pixels.width, height: pixels.height)
        let (colorScore, colorDetails) = computeColorHarmony(pixels: pixels)
        let (composition, compDetails) = computeComposition(pixels: pixels)

        var overall = sharpness * weights["sharpness"]!
            + dynamicRange * weights["dynamic_range"]!
            + noiseScore * weights["noise_control"]!
            + colorScore * weights["color_harmony"]!
            + composition * weights["composition"]!

        if sharpness < 28 {
            if !flags.contains("blurry") { flags.append("blurry") }
            overall -= 22
        } else if sharpness < 42 {
            overall -= 10
        }
        if flags.contains("clipped_highlights") { overall -= 14 }
        if flags.contains("crushed_shadows") { overall -= 8 }
        let tilt = compDetails["tilt_angle_deg"]?.doubleValue ?? 0
        if abs(tilt) >= 4, !flags.contains("tilted_horizon") { flags.append("tilted_horizon") }

        overall = PhotoGradeMath.clip(overall, 0, 100)
        let tier = classifyTier(overall: overall, flags: flags)

        var details: [String: JSONValue] = [
            "raw_sharpness": .number(rawSharp),
            "raw_noise": .number(rawNoise),
            "compute_device": .string("native"),
        ]
        for (key, value) in drDetails { details[key] = value }
        for (key, value) in colorDetails { details[key] = value }
        for (key, value) in compDetails { details[key] = value }

        return PhotoGradeEvaluation(
            path: url.standardizedFileURL.path,
            filename: url.lastPathComponent,
            overallScore: (overall * 10).rounded() / 10,
            tier: tier.rawValue,
            sharpness: sharpness,
            dynamicRange: dynamicRange,
            noiseControl: noiseScore,
            colorHarmony: colorScore,
            composition: composition,
            flags: flags,
            details: details
        )
    }

    private static func classifyTier(overall: Double, flags: [String]) -> PhotoGradeTier {
        if overall >= 85,
           !flags.contains(where: { ["blurry", "clipped_highlights", "underexposed"].contains($0) }) {
            return .s
        }
        if overall >= 72, !flags.contains("blurry") { return .a }
        if overall >= 58 { return .b }
        return .c
    }

    private static func computeSharpness(gray: [Float], width: Int, height: Int) -> (Double, Double) {
        var magnitudes: [Float] = []
        magnitudes.reserveCapacity(max(0, (width - 2) * (height - 2)))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let gx = -gray[idx - width - 1] - 2 * gray[idx - 1] - gray[idx + width - 1]
                    + gray[idx - width + 1] + 2 * gray[idx + 1] + gray[idx + width + 1]
                let gy = -gray[idx - width - 1] - 2 * gray[idx - width] - gray[idx - width + 1]
                    + gray[idx + width - 1] + 2 * gray[idx + width] + gray[idx + width + 1]
                magnitudes.append(sqrt(gx * gx + gy * gy + 1e-6))
            }
        }
        let raw = Double(PhotoGradeMath.quantile(magnitudes, 0.95))
        let score = PhotoGradeMath.clip((raw / 0.28) * 80, 0, 100)
        return ((score * 10).rounded() / 10, (raw * 10000).rounded() / 10000)
    }

    private static func computeDynamicRange(gray: [Float]) -> (Double, [String: JSONValue], [String]) {
        var flags: [String] = []
        var clippedHi = 0, clippedSh = 0
        var sum: Double = 0
        var histogram = [Int](repeating: 0, count: 64)
        for value in gray {
            sum += Double(value)
            if value > 0.985 { clippedHi += 1 }
            if value < 0.015 { clippedSh += 1 }
            let bin = min(63, max(0, Int(value * 63.999)))
            histogram[bin] += 1
        }
        let count = max(1, gray.count)
        let clippedHiPct = Double(clippedHi) / Double(count)
        let clippedShPct = Double(clippedSh) / Double(count)
        let meanLuma = sum / Double(count)

        if clippedHiPct > 0.08 { flags.append("clipped_highlights") }
        if clippedShPct > 0.20 { flags.append("crushed_shadows") }
        if meanLuma < 0.10 { flags.append("underexposed") }
        else if meanLuma > 0.85 { flags.append("overexposed") }

        var entropy: Double = 0
        for bin in histogram where bin > 0 {
            let prob = Double(bin) / Double(count)
            entropy -= prob * Double(PhotoGradeMath.log2(Float(prob)))
        }

        let entropyScore = PhotoGradeMath.clip((entropy / 5.4) * 85, 20, 95)
        let hiPenalty = PhotoGradeMath.clip(clippedHiPct * 150, 0, 40)
        let shPenalty = PhotoGradeMath.clip(clippedShPct * 100, 0, 30)
        let expDev = abs(meanLuma - 0.42)
        let expPenalty = PhotoGradeMath.clip(max(0, expDev - 0.15) * 60, 0, 30)
        let score = PhotoGradeMath.clip(entropyScore - hiPenalty - shPenalty - expPenalty + 10, 0, 100)

        let details: [String: JSONValue] = [
            "entropy": .number((entropy * 100).rounded() / 100),
            "clipped_highlights_pct": .number((clippedHiPct * 10000).rounded() / 100),
            "clipped_shadows_pct": .number((clippedShPct * 10000).rounded() / 100),
            "mean_luma": .number((meanLuma * 1000).rounded() / 1000),
        ]
        return ((score * 10).rounded() / 10, details, flags)
    }

    private static func computeNoiseControl(gray: [Float], width: Int, height: Int) -> (Double, Double) {
        var residuals: [Float] = []
        residuals.reserveCapacity(max(0, (width - 2) * (height - 2)))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let lap = gray[idx - width] + gray[idx + width] + gray[idx - 1] + gray[idx + 1] - 4 * gray[idx]
                residuals.append(abs(lap))
            }
        }
        let noise = Double(PhotoGradeMath.median(residuals))
        let score = PhotoGradeMath.clip(100 - (noise / 0.045) * 50, 10, 100)
        return ((score * 10).rounded() / 10, (noise * 100000).rounded() / 100000)
    }

    private static func computeColorHarmony(pixels: PhotoGradePixels) -> (Double, [String: JSONValue]) {
        var rgValues: [Float] = []
        var ybValues: [Float] = []
        var satValues: [Float] = []
        rgValues.reserveCapacity(pixels.count)
        ybValues.reserveCapacity(pixels.count)
        satValues.reserveCapacity(pixels.count)

        for i in 0..<pixels.count {
            let base = i * 3
            let r = pixels.rgb[base], g = pixels.rgb[base + 1], b = pixels.rgb[base + 2]
            rgValues.append(r - g)
            ybValues.append(0.5 * (r + g) - b)
            satValues.append(max(r, g, b) - min(r, g, b))
        }

        let stdRG = stdDev(rgValues), stdYB = stdDev(ybValues)
        let meanRG = mean(rgValues), meanYB = mean(ybValues)
        let stdRGYB = sqrt(stdRG * stdRG + stdYB * stdYB)
        let meanRGYB = sqrt(meanRG * meanRG + meanYB * meanYB)
        let colorfulness = stdRGYB + 0.3 * meanRGYB
        let meanSat = mean(satValues)

        let score: Double
        if meanSat < 0.03 {
            score = 65
        } else {
            score = PhotoGradeMath.clip(100 - abs(colorfulness - 0.25) * 160, 30, 100)
        }

        let details: [String: JSONValue] = [
            "colorfulness": .number((Double(colorfulness) * 1000).rounded() / 1000),
            "mean_saturation": .number((Double(meanSat) * 1000).rounded() / 1000),
        ]
        return ((score * 10).rounded() / 10, details)
    }

    private static func computeComposition(pixels: PhotoGradePixels) -> (Double, [String: JSONValue]) {
        let step = max(1, min(pixels.width, pixels.height) / 240)
        var gray = [Float]()
        var sat = [Float]()
        var sw = 0, sh = 0
        for y in Swift.stride(from: 0, to: pixels.height, by: step) {
            sh += 1
            var rowGray = [Float](), rowSat = [Float]()
            for x in Swift.stride(from: 0, to: pixels.width, by: step) {
                if sh == 1 { sw += 1 }
                let base = (y * pixels.width + x) * 3
                let r = pixels.rgb[base], g = pixels.rgb[base + 1], b = pixels.rgb[base + 2]
                rowGray.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
                rowSat.append(max(r, g, b) - min(r, g, b))
            }
            gray.append(contentsOf: rowGray)
            sat.append(contentsOf: rowSat)
        }

        var edge = [Float](repeating: 0, count: sw * sh)
        for y in 0..<sh {
            for x in 0..<sw {
                let idx = y * sw + x
                let left = gray[y * sw + max(0, x - 1)]
                let up = gray[max(0, y - 1) * sw + x]
                edge[idx] = abs(gray[idx] - left) + abs(gray[idx] - up)
            }
        }

        let cy = Double(sh - 1) / 2, cx = Double(sw - 1) / 2
        var attention = [Double](repeating: 0, count: sw * sh)
        var minAttention = Double.infinity
        for y in 0..<sh {
            for x in 0..<sw {
                let idx = y * sw + x
                let dist = sqrt(pow((Double(y) - cy) / max(cy, 1), 2) + pow((Double(x) - cx) / max(cx, 1), 2))
                let centerBias = PhotoGradeMath.clip(1 - dist * 0.55, 0.15, 1)
                let value = (0.55 * Double(edge[idx]) + 0.45 * Double(sat[idx])) * centerBias
                attention[idx] = value
                minAttention = min(minAttention, value)
            }
        }

        var total = 0.0, weightedX = 0.0, weightedY = 0.0
        for y in 0..<sh {
            for x in 0..<sw {
                let idx = y * sw + x
                let value = attention[idx] - minAttention
                total += value
                weightedX += value * Double(x)
                weightedY += value * Double(y)
            }
        }
        total += 1e-8
        let subjX = weightedX / total / max(Double(sw - 1), 1)
        let subjY = weightedY / total / max(Double(sh - 1), 1)

        let thirdNodes: [(Double, Double)] = [
            (1.0 / 3, 1.0 / 3), (1.0 / 3, 2.0 / 3), (2.0 / 3, 1.0 / 3), (2.0 / 3, 2.0 / 3),
            (0.5, 0.5), (0.5, 1.0 / 3), (0.5, 2.0 / 3),
        ]
        let minDist = thirdNodes.map { hypot(subjX - $0.0, subjY - $0.1) }.min() ?? 0
        let tilt = PhotoGradeEvaluatorTilt.estimate(gray: gray, width: sw, height: sh, quantile: 0.96, step: 0.5)

        var compScore = 90 - minDist * 75
        if abs(tilt) > 2 { compScore -= min(15, abs(tilt) * 2.5) }
        compScore = PhotoGradeMath.clip(compScore, 40, 100)

        let details: [String: JSONValue] = [
            "subject_center": .array([.number((subjX * 1000).rounded() / 1000), .number((subjY * 1000).rounded() / 1000)]),
            "tilt_angle_deg": .number((tilt * 100).rounded() / 100),
        ]
        return ((compScore * 10).rounded() / 10, details)
    }

    private static func mean(_ values: [Float]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func stdDev(_ values: [Float]) -> Double {
        guard !values.isEmpty else { return 0 }
        let avg = mean(values)
        let variance = values.reduce(0) { $0 + pow(Double($1) - avg, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
