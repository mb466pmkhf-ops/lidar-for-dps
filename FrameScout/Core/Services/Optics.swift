import Foundation

/// Thin-lens / pinhole optics used for field-of-view and framing answers.
/// All distances in metres, sensor sizes and focal lengths in millimetres, angles in degrees.
enum Optics {
    /// Angle of view for one sensor dimension.
    static func fieldOfView(size: Double, focalLength: Double) -> Double {
        guard focalLength > 0 else { return 0 }
        return 2 * atan(size / (2 * focalLength)) * 180 / .pi
    }

    /// Focal length that gives a particular angle of view on one sensor dimension.
    static func focalLength(forFOV degrees: Double, size: Double) -> Double {
        let half = degrees * .pi / 360
        guard half > 0 else { return .infinity }
        return size / (2 * tan(half))
    }

    /// Width (or height) of the frame at `distance` for a sensor dimension.
    static func frameSize(atDistance distance: Double, size: Double, focalLength: Double) -> Double {
        guard focalLength > 0 else { return 0 }
        return distance * size / focalLength
    }

    /// Camera-to-subject distance needed for the frame (one dimension) to cover `coverage` metres.
    static func distance(toCover coverage: Double, size: Double, focalLength: Double) -> Double {
        guard size > 0 else { return 0 }
        return coverage * focalLength / size
    }

    /// Image area after fitting a delivery aspect ratio inside the sensor.
    static func imageArea(sensor: SensorFormat, aspect: FrameAspect) -> (width: Double, height: Double) {
        guard let ratio = aspect.ratio else { return (sensor.width, sensor.height) }
        if ratio >= sensor.aspectRatio {
            return (sensor.width, sensor.width / ratio)
        } else {
            return (sensor.height * ratio, sensor.height)
        }
    }

    /// Full-frame (36×24) equivalent focal length by diagonal crop factor.
    static func fullFrameEquivalent(focalLength: Double, sensor: SensorFormat) -> Double {
        let ffDiagonal = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()
        return focalLength * ffDiagonal / sensor.diagonal
    }

    static func formatFocal(_ f: Double) -> String {
        f.rounded() == f ? String(format: "%.0fmm", f) : String(format: "%.1fmm", f)
    }

    static func formatAngle(_ a: Double) -> String { String(format: "%.1f°", a) }

    /// Rule-of-thumb shot sizes expressed as subject height in frame (m), for a 1.75 m person.
    enum ShotSize: String, CaseIterable, Identifiable {
        case wide, full, medium, closeUp

        var id: String { rawValue }
        var label: String {
            switch self {
            case .wide: return "Wide (3.5 m tall)"
            case .full: return "Full body"
            case .medium: return "Medium (waist up)"
            case .closeUp: return "Close-up"
            }
        }
        /// Vertical coverage in metres.
        var verticalCoverage: Double {
            switch self {
            case .wide: return 3.5
            case .full: return 2.1
            case .medium: return 1.0
            case .closeUp: return 0.40
            }
        }
    }
}
