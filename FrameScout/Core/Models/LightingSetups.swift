import Foundation

/// Starting points for lighting a person: units placed round them relative to the camera and set
/// (with the photometric model) to sensible levels for the camera's exposure. A starting point to
/// adjust, not a finished setup; levels are estimates like every other reading.
enum LightingSetup: String, CaseIterable, Identifiable {
    /// Key 45° off the camera axis, fill on the other side two stops under, back light behind.
    case threePoint
    /// Large soft key from the side, negative fill opposite: contrasty and natural.
    case softSide
    /// Soft key close to the lens axis, one stop of fill from the same side: flat and flattering.
    case beauty
    /// One hard unit high from the side and nothing else: deep shadows, a low-key look.
    case hardSingle
    /// Soft key from the front side, a hard edge from behind on the other side, one stop over.
    case keyAndEdge

    var id: String { rawValue }
    var label: String {
        switch self {
        case .threePoint: return "Three-point"
        case .softSide: return "Soft side light"
        case .beauty: return "Soft front (beauty)"
        case .hardSingle: return "Hard single source"
        case .keyAndEdge: return "Key and edge"
        }
    }
    var summary: String {
        switch self {
        case .threePoint: return "Key, fill 2 stops under, back light"
        case .softSide: return "Big soft key from the side, neg fill"
        case .beauty: return "Soft key near the lens, gentle fill"
        case .hardSingle: return "One fresnel high from the side, no fill"
        case .keyAndEdge: return "Soft key, hard edge 1 stop over"
        }
    }

    struct Result {
        var lights: [LightFixture]
        /// One line per unit on what it was set to, or why it couldn't reach its level.
        var notes: [String]
    }

    /// Units for `person`, seen from `camera` (nil: from the way the person faces).
    /// The key is placed on the side of the camera axis with more room in the plan.
    func build(for person: PrevisCharacter, camera: PlanPoint?, exposure: ExposureSettings,
               plan: FloorPlan?, windowTransmission: Double = SceneDisplay.defaultWindowTransmission) -> Result {
        let p = person.position
        let towardCamera = camera.map { PlanGeometry.bearing(from: p, to: $0) } ?? person.facing
        let face = LightingCalculator.Point(p, height: max(0.3, person.eyeHeight - 0.03))
        let faceNormal = LightingCalculator.direction(bearing: towardCamera, tilt: 0)
        let key = exposure.keyLux

        struct Spec {
            var name: String
            var role: LightRole
            /// Candidate units, smallest first: the first that reaches its level with headroom is used.
            var profiles: [String]
            var modifier: String?
            var offset: Double      // degrees from the camera direction, seen from the person
            var distance: Double
            var rise: Double        // height above eye level
            var stopsUnderKey: Double
            var rim = false
            var kind: LightKind? = nil
            var width: Double? = nil
        }
        var specs: [Spec]
        switch self {
        case .threePoint:
            specs = [Spec(name: "Key", role: .key, profiles: ["cob-100-bi", "cob-300-d", "cob-600-d", "cob-1200-d"], modifier: "softbox-90-grid", offset: 45, distance: 2.2, rise: 0.6, stopsUnderKey: 0),
                     Spec(name: "Fill", role: .fill, profiles: ["panel-1x1-bi", "panel-2x1-bi"], modifier: nil, offset: -40, distance: 2.5, rise: 0.3, stopsUnderKey: 2),
                     Spec(name: "Back", role: .back, profiles: ["fresnel-led-200-bi", "fresnel-led-600-d"], modifier: nil, offset: 160, distance: 2.4, rise: 1.0, stopsUnderKey: 0, rim: true)]
        case .softSide:
            specs = [Spec(name: "Key", role: .key, profiles: ["cob-300-d", "cob-600-d", "cob-1200-d"], modifier: "softbox-150", offset: 80, distance: 2.0, rise: 0.4, stopsUnderKey: 0),
                     Spec(name: "Neg", role: .fill, profiles: [], modifier: nil, offset: -80, distance: 1.2, rise: 0, stopsUnderKey: 0, kind: .negative, width: 1.2)]
        case .beauty:
            specs = [Spec(name: "Key", role: .key, profiles: ["cob-100-bi", "cob-300-d", "cob-600-d"], modifier: "softbox-90", offset: 20, distance: 1.8, rise: 0.5, stopsUnderKey: 0),
                     Spec(name: "Fill", role: .fill, profiles: ["mat-2x2-bi", "mat-4x4-bi"], modifier: nil, offset: -10, distance: 2.0, rise: -0.4, stopsUnderKey: 1)]
        case .hardSingle:
            specs = [Spec(name: "Key", role: .key, profiles: ["fresnel-led-200-bi", "fresnel-led-600-d"], modifier: nil, offset: 60, distance: 2.6, rise: 1.0, stopsUnderKey: 0)]
        case .keyAndEdge:
            specs = [Spec(name: "Key", role: .key, profiles: ["cob-100-bi", "cob-300-d", "cob-600-d", "cob-1200-d"], modifier: "softbox-90", offset: 50, distance: 2.0, rise: 0.5, stopsUnderKey: 0),
                     Spec(name: "Edge", role: .edge, profiles: ["fresnel-led-200-bi", "fresnel-led-600-d"], modifier: nil, offset: -135, distance: 2.4, rise: 0.9, stopsUnderKey: -1, rim: true)]
        }

        // Key goes on whichever side of the camera axis has more room.
        let side: Double = room(from: p, bearing: towardCamera + 60, plan: plan) >= room(from: p, bearing: towardCamera - 60, plan: plan) ? 1 : -1
        var lights: [LightFixture] = []
        var notes: [String] = []
        for spec in specs {
            let bearing = towardCamera + side * spec.offset
            let d = min(spec.distance, max(0.6, room(from: p, bearing: bearing, plan: plan) - 0.4))
            let at = p + PlanPoint.unit(bearing: bearing) * d
            let pan = PlanGeometry.bearing(from: at, to: p)
            guard spec.kind == nil, !spec.profiles.isEmpty else {
                // Grip: a board standing at face height.
                var board = LightFixture(name: "\(spec.name) · \(person.name)", kind: spec.kind ?? .negative, position: at, pan: pan, scanID: person.scanID)
                board.role = spec.role
                if let width = spec.width { board.width = width }
                board.height = max(0.6, face.y)
                board.boardHeight = 1.2
                lights.append(board)
                continue
            }
            let target = key / pow(2, spec.stopsUnderKey)
            var chosen: (LightFixture, LightingCalculator.IntensitySolution)?
            for id in spec.profiles {
                guard let profile = FixtureLibrary.profile(id: id) else { continue }
                var light = LightFixture(name: "\(spec.name) · \(person.name)", kind: profile.kind, position: at, pan: pan, scanID: person.scanID)
                light.apply(profile: profile)
                light.role = spec.role
                if let m = spec.modifier, FixtureLibrary.modifiers(for: profile).contains(where: { $0.id == m }) { light.modifierID = m }
                light.height = max(0.4, face.y + spec.rise)
                light.tilt = -atan2(light.height - face.y, d) * 180 / .pi
                // Back light: metered facing the unit (rim), the others towards camera.
                let normal = spec.rim ? (LightingCalculator.Point(at, height: light.height) - face).normalized : faceNormal
                let solution = LightingCalculator.solveOutput(for: light, target: target, at: face, normal: normal, allLights: [light],
                                                              plan: plan, windowTransmission: windowTransmission)
                chosen = (light, solution)
                if case .output(let o) = solution, o <= 0.8 { break }
            }
            guard let pick = chosen else { continue }
            var light = pick.0
            let solution = pick.1
            switch solution {
            case .output(let o):
                light.dimmer = o
                notes.append("\(spec.name): \(light.profile.name) at \(Int((o * 100).rounded())) % for ≈ \(Int(target.rounded())) lx")
            case .tooDim(let maxLux, _):
                light.dimmer = 1
                notes.append("\(spec.name): even at full ≈ \(Int(maxLux.rounded())) lx — move it closer or open the lens")
            case .atMinimum(let o, let lux):
                light.dimmer = o
                notes.append("\(spec.name): at its lowest (\(Int((o * 100).rounded())) %) ≈ \(Int(lux.rounded())) lx, over the target — move it back or add ND")
            case .othersTooBright, .noContribution:
                light.dimmer = 0.5
                notes.append("\(spec.name): couldn't reach the face from here; check its aim")
            }
            lights.append(light)
        }
        return Result(lights: lights, notes: notes)
    }

    /// Free distance from `p` along a bearing before the nearest wall (8 m with no plan).
    func room(from p: PlanPoint, bearing: Double, plan: FloorPlan?) -> Double {
        guard let plan, !plan.walls.isEmpty else { return 8 }
        let far = p + PlanPoint.unit(bearing: bearing) * 8
        var best = 8.0
        for w in plan.walls {
            if let hit = LightingCalculator.intersect(p, far, w.a, w.b) { best = min(best, hit.0 * 8) }
        }
        return best
    }
}
