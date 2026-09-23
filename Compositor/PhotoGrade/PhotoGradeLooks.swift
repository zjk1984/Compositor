import CoreGraphics
import Foundation

/// Develop look recipes from raw-photo-grade `pipeline.py`, mapped to Compositor Camera Raw settings.
nonisolated enum PhotoGradeLooks {
    static func cameraRawSettings(for look: PhotoGradeLook) -> CameraRawSettings {
        var settings = CameraRawSettings()
        switch look {
        case .natural:
            settings.exposure = 0.1
            settings.contrast = 12
            settings.highlights = -12
            settings.shadows = 16
            settings.whites = 4
            settings.blacks = -6
            settings.temperature = 2
            settings.tint = -1
            settings.vibrance = 10
            settings.saturation = 2
            settings.clarity = 10
            settings.vignetteAmount = -4
            settings.detail.sharpenAmount = 20
            settings.detail.noiseLuminance = 4
        case .warmGolden:
            settings.exposure = 0.15
            settings.contrast = 14
            settings.highlights = -18
            settings.shadows = 18
            settings.whites = 2
            settings.blacks = -8
            settings.temperature = 16
            settings.tint = 4
            settings.vibrance = 14
            settings.saturation = 6
            settings.clarity = 8
            settings.vignetteAmount = -8
            settings.detail.sharpenAmount = 18
            settings.detail.noiseLuminance = 4
        case .portrait:
            settings.exposure = 0.2
            settings.contrast = 8
            settings.highlights = -10
            settings.shadows = 22
            settings.whites = 2
            settings.blacks = -4
            settings.temperature = 8
            settings.tint = 3
            settings.vibrance = 8
            settings.saturation = -2
            settings.clarity = 4
            settings.vignetteAmount = -6
            settings.detail.sharpenAmount = 12
            settings.detail.noiseLuminance = 6
        case .coolCinematic:
            settings.exposure = -0.05
            settings.contrast = 18
            settings.highlights = -15
            settings.shadows = 10
            settings.whites = -4
            settings.blacks = -14
            settings.temperature = -12
            settings.tint = -2
            settings.vibrance = 6
            settings.saturation = -4
            settings.clarity = 12
            settings.vignetteAmount = -12
            settings.detail.sharpenAmount = 16
            settings.detail.noiseLuminance = 5
        }
        return settings.normalized
    }

    static func apply(_ look: PhotoGradeLook, to image: CGImage) throws -> CGImage {
        try cameraRawSettings(for: look).apply(image)
    }
}
