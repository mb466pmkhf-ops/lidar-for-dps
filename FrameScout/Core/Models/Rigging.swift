import Foundation

/// What holds a lighting unit or a board. Drawn in 3D and listed on the plan; it never changes the
/// light maths. Heights are typical published ranges for the class of stand, not a specific model.
enum LightSupport: String, Codable, CaseIterable, Identifiable {
    case cStand, comboStand, turtleBase, megaBoom, rollerStand, windUp, overhead, floor, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cStand: return "C-stand"
        case .comboStand: return "Combo stand"
        case .turtleBase: return "Turtle base"
        case .megaBoom: return "MegaBoom"
        case .rollerStand: return "Roller stand"
        case .windUp: return "Wind-up stand"
        case .overhead: return "Rigged overhead"
        case .floor: return "On the floor"
        case .none: return "No stand"
        }
    }

    /// Head height range the support reaches (m), roughly. nil: no limit worth showing.
    var heightRange: ClosedRange<Double>? {
        switch self {
        case .cStand: return 1.0...3.3
        case .comboStand: return 1.2...4.0
        case .turtleBase: return 0.2...0.75
        case .megaBoom: return 1.5...4.5
        case .rollerStand: return 1.4...4.9
        case .windUp: return 1.7...4.6
        case .overhead, .floor, .none: return nil
        }
    }

    /// Arm reach in front of the stand (m), for booms. The head sits at the light's position and the
    /// stand stands back along the light's facing direction.
    var boomReach: Double { self == .megaBoom ? 2.2 : 0 }

    /// What the app picks when the user hasn't: practicals sit on their own, space lights hang, very
    /// low units go on a turtle base, 6×6 and bigger frames on wind-ups, heavy heads and 4×4 frames on
    /// a combo, the rest on a C-stand.
    static func automatic(for light: LightFixture) -> LightSupport {
        switch light.kind {
        case .practical: return .none
        case .spaceLight: return .overhead
        default: break
        }
        if light.height < 0.15 { return .floor }
        if light.height < 0.75 { return .turtleBase }
        if GripCatalog.gripKinds.contains(light.kind) && light.width >= 1.7 { return .windUp }
        switch light.kind {
        case .bounce, .negative, .diffusion: return light.width >= 1 ? .comboStand : .cStand
        case .flag: return .cStand
        default: break
        }
        let p = light.profile
        let modifierSize = light.modifierItem?.size ?? 0
        if p.category == .hmi || p.ratedPower >= 1000 || modifierSize >= 0.9 || p.emitterWidth >= 0.9 { return .comboStand }
        return .cStand
    }
}

/// What the camera sits on.
enum CameraSupport: String, Codable, CaseIterable, Identifiable {
    case tripod, babyLegs, highHat, dolly, slider, handheld, gimbal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tripod: return "Tripod · O'Connor head"
        case .babyLegs: return "Baby legs"
        case .highHat: return "High hat"
        case .dolly: return "Dolly"
        case .slider: return "Slider"
        case .handheld: return "Handheld"
        case .gimbal: return "Gimbal"
        }
    }

    var shortLabel: String {
        switch self {
        case .tripod: return "Tripod"
        default: return label
        }
    }

    /// Lens height range it reaches (m), roughly.
    var heightRange: ClosedRange<Double>? {
        switch self {
        case .tripod: return 0.9...2.0
        case .babyLegs: return 0.45...1.05
        case .highHat: return 0.1...0.45
        case .dolly: return 0.6...2.1
        case .slider: return 0.2...1.9
        case .handheld, .gimbal: return 0.6...1.9
        }
    }

    /// An O'Connor-style head on sticks, unless the lens is too low for full-size legs.
    static func automatic(height: Double) -> CameraSupport {
        if height < 0.45 { return .highHat }
        if height < 0.9 { return .babyLegs }
        return .tripod
    }
}

extension LightFixture {
    /// The support the user chose, or the automatic one.
    var supportValue: LightSupport { support ?? LightSupport.automatic(for: self) }

    /// "Above a C-stand's usual reach (3.3 m)", when the height is outside what the support does.
    var supportWarning: String? {
        let s = supportValue
        guard let r = s.heightRange else { return nil }
        if height > r.upperBound + 0.05 { return "Higher than a \(s.label) usually goes (\(Self.metres(r.upperBound)))" }
        if height < r.lowerBound - 0.05 { return "Lower than a \(s.label) usually goes (\(Self.metres(r.lowerBound)))" }
        return nil
    }

    fileprivate static func metres(_ v: Double) -> String { String(format: "%.1f m", v) }
}

extension CameraRig {
    var supportValue: CameraSupport { support ?? CameraSupport.automatic(height: height) }

    var supportWarning: String? {
        let s = supportValue
        guard let r = s.heightRange else { return nil }
        if height > r.upperBound + 0.05 { return "Higher than \(s.shortLabel.lowercased()) usually goes (\(LightFixture.metres(r.upperBound)))" }
        if height < r.lowerBound - 0.05 { return "Lower than \(s.shortLabel.lowercased()) usually goes (\(LightFixture.metres(r.lowerBound)))" }
        return nil
    }
}

/// Where a drawn beam should stop: at the room's walls, windows and closed doors, so beams don't
/// spill across the plan outside the location. Drawing only; the lux maths has its own occlusion.
enum BeamClip {
    /// Plan distance from `origin` along `bearing` to the first wall, window or closed door, capped at `limit`.
    static func planReach(from origin: PlanPoint, bearing: Double, limit: Double, plan: FloorPlan?) -> Double {
        guard let plan, limit > 0 else { return limit }
        let end = origin + PlanPoint.unit(bearing: bearing) * limit
        var best = 1.0
        for seg in plan.walls + plan.windows + plan.doors where !seg.isOpen {
            if let (t, _) = LightingCalculator.intersect(origin, end, seg.a, seg.b), t < best { best = t }
        }
        return limit * best
    }
}
