import Foundation

/// Depth of field: how much of the frame is acceptably sharp for a lens, stop and focus distance.
/// Thin-lens maths, the same as any depth-of-field table. Mirror of web/src/model/focus.ts.
///
/// Honesty: an estimate. It treats the T-stop as the f-stop (a real lens's f-stop is a little wider, so
/// the true depth is a touch shallower), and "acceptably sharp" depends on the circle of confusion,
/// which is a convention: here the image area's diagonal / 1500.
enum DepthOfField {
    /// The usual rule for the circle of confusion: the format's diagonal divided by this.
    static let cocDivisor = 1500.0
    /// Eyes sit at about 0.94 of a standing person's height (anthropometric average); focus is pulled on the eyes.
    static let eyeHeightRatio = 0.94
    /// Closest focus the controls offer (m).
    static let minFocus = 0.3

    enum Source: Equatable { case set, subject }
    struct Focus: Equatable { var metres: Double; var from: Source }

    struct Limits: Equatable {
        /// Focus distance (m).
        var focus: Double
        /// Nearest and furthest acceptably sharp distances (m); far is infinity past the hyperfocal distance.
        var near: Double
        var far: Double
        var hyperfocal: Double
    }

    /// Circle of confusion for this camera's image area (mm).
    static func circleOfConfusion(_ rig: CameraRig) -> Double {
        let a = rig.imageArea
        return (a.width * a.width + a.height * a.height).squareRoot() / cocDivisor
    }

    /// Where the camera is focused: the distance set on the rig, else the shot's subject's eyes.
    static func focus(_ rig: CameraRig, subject: PlanPoint? = nil, subjectHeight: Double? = nil) -> Focus? {
        if let d = rig.focusDistance, d > 0 { return Focus(metres: max(minFocus, d), from: .set) }
        guard let subject else { return nil }
        let eyes = (subjectHeight ?? 1.75) * eyeHeightRatio
        let dx = subject.x - rig.position.x, dz = subject.z - rig.position.z, dy = eyes - rig.height
        return Focus(metres: max(minFocus, (dx * dx + dy * dy + dz * dz).squareRoot()), from: .subject)
    }

    /// Near and far limits. Focal length and circle of confusion in mm, distances in m.
    static func limits(focalMm: Double, fNumber: Double, focusM: Double, cocMm: Double) -> Limits {
        let f = focalMm / 1000, c = cocMm / 1000, n = max(fNumber, 0.5)
        let s = max(focusM, f * 1.01)
        let h = f * f / (n * c) + f
        let near = s * (h - f) / (h + s - 2 * f)
        let far = s >= h ? Double.infinity : s * (h - f) / (h - s)
        return Limits(focus: s, near: near, far: far, hyperfocal: h)
    }

    static func limits(_ rig: CameraRig, tStop: Double, focusM: Double) -> Limits {
        limits(focalMm: rig.focalLength, fNumber: tStop, focusM: focusM, cocMm: circleOfConfusion(rig))
    }

    /// Blur-circle diameter on the sensor (mm) of a point at `distM` when focused at `focusM`.
    static func blurDiameter(focalMm: Double, fNumber: Double, focusM: Double, distM: Double) -> Double {
        let f = focalMm / 1000, s = max(focusM, f * 1.01), d = max(distM, 1e-3)
        return f * f / (max(fNumber, 0.5) * (s - f)) * (abs(d - s) / d) * 1000
    }

    /// "Focus 3.2 m · sharp 2.8–3.7 m" or "Focus 8.0 m · sharp 4.1 m to infinity".
    static func label(_ d: Limits, length: (Double) -> String = metres) -> String {
        let range = d.far == .infinity ? "\(length(d.near)) to infinity" : "\(length(d.near))–\(length(d.far))"
        return "Focus \(length(d.focus)) · sharp \(range)"
    }

    static func metres(_ x: Double) -> String {
        x >= 10 ? "\(Int(x.rounded())) m" : String(format: x < 1 ? "%.2f m" : "%.1f m", x)
    }
}

/// Haze in the air, for the 3D view only: whether beams show and how much of a veil hangs in the room.
/// A look for judging the frame, not a measurement of any hazer. Same levels as the desktop (focus.ts).
enum HazeLevel: String, Codable, CaseIterable, Identifiable {
    case none, light, medium, heavy
    var id: String { rawValue }
    var name: String {
        switch self {
        case .none: return "No haze"
        case .light: return "Light haze"
        case .medium: return "Medium haze"
        case .heavy: return "Heavy haze"
        }
    }
    /// Beam strength against the Beams layer's planning strength.
    var beams: Double {
        switch self { case .none: return 0; case .light: return 0.2; case .medium: return 0.35; case .heavy: return 0.6 }
    }
    /// Veil density (as an exponential-squared fog, per metre).
    var veil: Double {
        switch self { case .none: return 0; case .light: return 0.05; case .medium: return 0.09; case .heavy: return 0.14 }
    }
}
