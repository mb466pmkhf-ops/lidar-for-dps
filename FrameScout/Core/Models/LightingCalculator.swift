import Foundation

/// Estimates illuminance from the lighting diagram. Separate from the 3D renderer on purpose:
/// the viewport shows roughly what the light does, these numbers say how much there is.
///
/// What is modelled:
/// - each unit's intensity distribution, beam angle, modifiers, filters and dimmer (`Photometrics`);
/// - distance (inverse square, with near-field corrections for soft sources and tubes);
/// - the angle the light meets the meter's receptor (cosine law);
/// - barn doors (each leaf cuts its side of the beam with a soft edge);
/// - walls block light; windows pass it at the glass's transmission; closed doors block,
///   open doors and openings don't; flags, negs and bounce boards block, diffusion frames pass half;
/// - bounce boards re-emit what lands on them (one bounce, white board reflectance 0.8);
/// - overlapping units add up.
///
/// What isn't: light reflected by walls, floor and ceiling, daylight, and furniture shadows.
/// Real readings in a room will usually be higher than these. Every result is an estimate.
enum LightingCalculator {
    /// A point in the room: plan x/z, height above the floor.
    struct Point: Hashable {
        var x: Double
        var y: Double
        var z: Double

        init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
        init(_ p: PlanPoint, height: Double) { x = p.x; y = height; z = p.z }

        static func - (a: Point, b: Point) -> Point { Point(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func + (a: Point, b: Point) -> Point { Point(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func * (a: Point, s: Double) -> Point { Point(x: a.x * s, y: a.y * s, z: a.z * s) }
        func dot(_ b: Point) -> Double { x * b.x + y * b.y + z * b.z }
        var length: Double { dot(self).squareRoot() }
        var normalized: Point { let l = length; return l > 1e-12 ? self * (1 / l) : Point(x: 0, y: 1, z: 0) }
        func cross(_ b: Point) -> Point { Point(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
        var plan: PlanPoint { PlanPoint(x: x, z: z) }
    }

    /// Unit vector for a bearing (0° = plan up = −Z, clockwise) and tilt (+ up).
    static func direction(bearing: Double, tilt: Double) -> Point {
        let b = bearing * .pi / 180, t = tilt * .pi / 180
        return Point(x: sin(b) * cos(t), y: sin(t), z: -cos(b) * cos(t))
    }

    /// Everything the calculation needs, resolved once so a whole grid of points is cheap.
    struct Scene {
        struct Emitter {
            var id: UUID
            var position: Point
            var axis: Point
            var right: Point
            var up: Point
            var photometrics: ResolvedPhotometrics
            var barnDoors: BarnDoors
        }
        struct Board {
            var id: UUID
            var kind: LightKind
            var centre: Point
            var normal: Point
            var a: PlanPoint
            var b: PlanPoint
            var bottom: Double
            var top: Double
            var area: Double
            /// Fraction passed by the board when it's in the way.
            var transmission: Double {
                kind == .diffusion ? 0.5 : 0
            }
        }

        var emitters: [Emitter] = []
        var boards: [Board] = []
        var walls: [PlanSegment] = []
        var apertures: [PlanSegment] = []
        var windowTransmission: Double = SceneDisplay.defaultWindowTransmission
        /// Reflectance of a white bounce board.
        static let bounceReflectance = 0.8

        init(lights: [LightFixture], plan: FloorPlan? = nil, windowTransmission: Double = SceneDisplay.defaultWindowTransmission) {
            self.windowTransmission = windowTransmission
            if let plan {
                walls = plan.walls
                apertures = plan.windows + plan.doors + plan.openings
            }
            for l in lights {
                let axis = LightingCalculator.direction(bearing: l.pan, tilt: l.tilt)
                if l.kind.emits {
                    let rightDir = LightingCalculator.direction(bearing: l.pan + 90, tilt: 0)
                    emitters.append(Emitter(id: l.id, position: Point(l.position, height: l.height), axis: axis,
                                            right: rightDir, up: rightDir.cross(axis).normalized,
                                            photometrics: l.photometrics,
                                            barnDoors: l.barnDoorSettings))
                } else {
                    let side = PlanPoint.unit(bearing: l.pan + 90) * (l.width / 2)
                    let h = l.boardHeight ?? (l.kind == .flag ? min(l.width, 0.9) : l.width)
                    boards.append(Board(id: l.id, kind: l.kind, centre: Point(l.position, height: l.height), normal: axis,
                                        a: l.position - side, b: l.position + side,
                                        bottom: l.height - h / 2, top: l.height + h / 2, area: l.width * h))
                }
            }
        }
    }

    struct Contribution: Hashable {
        var lightID: UUID
        var lux: Double
        /// Set when the light arrives off a bounce board (the board's id).
        var viaBounce: UUID? = nil
    }

    struct Reading {
        var lux: Double
        var contributions: [Contribution]
        /// The largest single contribution — usually the key.
        var dominant: Contribution? { contributions.max { $0.lux < $1.lux } }
        static let zero = Reading(lux: 0, contributions: [])
    }

    // MARK: Direct light

    /// Illuminance (lux) at `point` on a receptor facing `normal`, from one emitter.
    static func illuminance(from e: Scene.Emitter, at point: Point, normal: Point, scene: Scene, ignoringBoard: UUID? = nil) -> Double {
        let toPoint = point - e.position
        let d = toPoint.length
        guard d > 0.05, e.photometrics.peakIntensity > 0 else { return 0 }
        let v = toPoint * (1 / d)
        let incidence = -v.dot(normal)
        guard incidence > 0 else { return 0 }
        let pm = e.photometrics

        var relative: Double
        switch pm.distribution {
        case .tube:
            // Tube axis lies across the unit (its "right" direction).
            let along = min(1, abs(v.dot(e.right)))
            relative = (1 - along * along).squareRoot()
        default:
            let cosTheta = min(1, max(-1, v.dot(e.axis)))
            relative = pm.distribution.relativeIntensity(offAxis: acos(cosTheta) * 180 / .pi, beamAngle: pm.beamAngle)
        }
        if pm.barnDoorsAvailable && !e.barnDoors.isOpen {
            let fwd = v.dot(e.axis)
            if fwd <= 0 { return 0 }
            let h = atan2(v.dot(e.right), fwd) * 180 / .pi
            let vert = atan2(v.dot(e.up), fwd) * 180 / .pi
            relative *= e.barnDoors.transmission(horizontal: h, vertical: vert)
        }
        guard relative > 1e-6 else { return 0 }
        let falloff = Photometry.distanceFactor(d, distribution: pm.distribution,
                                                emitterRadius: pm.emitterRadius, tubeLength: pm.tubeLength)
        let lux = pm.peakIntensity * relative * falloff * incidence
        guard lux > 1e-6 else { return 0 }
        return lux * transmission(from: e.position, to: point, scene: scene, ignoring: [e.id, ignoringBoard].compactMap { $0 })
    }

    /// Fraction of light that gets from `a` to `b` past walls, windows and grip.
    static func transmission(from a: Point, to b: Point, scene: Scene, ignoring: [UUID] = []) -> Double {
        var t = 1.0
        for w in scene.walls {
            guard let hit = intersect(a.plan, b.plan, w.a, w.b) else { continue }
            let (s, q) = hit
            let y = a.y + s * (b.y - a.y)
            guard y >= w.bottom - 0.01, y <= w.bottom + w.height + 0.01 else { continue }
            // Is the crossing in a window, door or opening of this wall?
            if let ap = scene.apertures.first(where: { distance(q, toSegment: $0.a, $0.b) < 0.15 && y >= $0.bottom - 0.01 && y <= $0.bottom + $0.height + 0.01 }) {
                switch ap.kind {
                case .window: t *= scene.windowTransmission
                case .door: t *= ap.isOpen ? 1 : 0
                default: break
                }
            } else {
                return 0
            }
            if t <= 0 { return 0 }
        }
        for board in scene.boards where !ignoring.contains(board.id) {
            guard let hit = intersect(a.plan, b.plan, board.a, board.b) else { continue }
            let s = hit.0
            let y = a.y + s * (b.y - a.y)
            guard y >= board.bottom, y <= board.top else { continue }
            t *= board.transmission
            if t <= 0 { return 0 }
        }
        return t
    }

    // MARK: Totals

    /// Illuminance at a point from every unit, including first-bounce light off bounce boards.
    static func reading(at point: Point, normal: Point, scene: Scene) -> Reading {
        var contributions: [Contribution] = []
        var total = 0.0
        for e in scene.emitters {
            let lux = illuminance(from: e, at: point, normal: normal, scene: scene)
            if lux > 0 {
                contributions.append(Contribution(lightID: e.id, lux: lux))
                total += lux
            }
        }
        for board in scene.boards where board.kind == .bounce {
            for (lightID, lux) in bounce(board, to: point, normal: normal, scene: scene) where lux > 0 {
                contributions.append(Contribution(lightID: lightID, lux: lux, viaBounce: board.id))
                total += lux
            }
        }
        return Reading(lux: total, contributions: contributions)
    }

    /// Light each emitter sends to `point` off a bounce board: the board's exitance (reflectance ×
    /// incident lux) treated as a diffuse source the size of the board.
    static func bounce(_ board: Scene.Board, to point: Point, normal: Point, scene: Scene) -> [(UUID, Double)] {
        let toPoint = point - board.centre
        let d = toPoint.length
        guard d > 0.05 else { return [] }
        let v = toPoint * (1 / d)
        let out = v.dot(board.normal)
        let incidence = -v.dot(normal)
        guard out > 0, incidence > 0 else { return [] }
        let radius = (board.area / .pi).squareRoot()
        let geometry = out * incidence / (d * d + radius * radius)
        let pass = transmission(from: board.centre, to: point, scene: scene, ignoring: [board.id])
        guard pass > 0 else { return [] }
        var result: [(UUID, Double)] = []
        for e in scene.emitters {
            let incident = illuminance(from: e, at: board.centre, normal: board.normal, scene: scene, ignoringBoard: board.id)
            guard incident > 0 else { continue }
            let intensity = Scene.bounceReflectance * incident * board.area / .pi
            result.append((e.id, intensity * geometry * pass))
        }
        return result
    }

    /// Readings on a grid over `bounds`, row by row (z then x), at `height`. `normal` gives the
    /// receptor direction for each cell centre.
    static func grid(bounds: PlanRect, columns: Int, rows: Int, height: Double, scene: Scene,
                     normal: (Point) -> Point) -> [Double] {
        guard columns > 0, rows > 0 else { return [] }
        var values: [Double] = []
        values.reserveCapacity(columns * rows)
        let cw = bounds.width / Double(columns), ch = bounds.depth / Double(rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let p = Point(x: bounds.minX + (Double(c) + 0.5) * cw, y: height, z: bounds.minZ + (Double(r) + 0.5) * ch)
                values.append(reading(at: p, normal: normal(p), scene: scene).lux)
            }
        }
        return values
    }

    // MARK: Solving

    enum IntensitySolution: Equatable {
        /// Set the unit to this output (0…1) to reach the target.
        case output(Double)
        /// Even at full the unit gives too little here: what it reaches, and how close it would need to be.
        case tooDim(maxLux: Double, suggestedDistance: Double?)
        /// Other units alone already exceed the target.
        case othersTooBright(othersLux: Double)
        /// The unit doesn't reach this point (blocked, aimed away, or switched off).
        case noContribution
    }

    /// Output for `light` so the total at the point reaches `target` lux, keeping the other units as they are.
    static func solveOutput(for light: LightFixture, target: Double, at point: Point, normal: Point,
                            allLights: [LightFixture], plan: FloorPlan?, windowTransmission: Double = SceneDisplay.defaultWindowTransmission) -> IntensitySolution {
        let others = allLights.filter { $0.id != light.id }
        var full = light
        full.dimmer = 1
        full.isOn = true
        let fullScene = Scene(lights: others + [full], plan: plan, windowTransmission: windowTransmission)
        let fullReading = reading(at: point, normal: normal, scene: fullScene)
        let mine = fullReading.contributions.filter { $0.lightID == light.id }.reduce(0) { $0 + $1.lux }
        let othersLux = fullReading.lux - mine
        guard mine > 1e-6 else { return .noContribution }
        let need = target - othersLux
        if need <= 0 { return .othersTooBright(othersLux: othersLux) }
        let minOutput = light.profile.minOutput
        let output = need / mine
        if output > 1.0001 {
            // Inverse square: distance that would give `need` with the same aim.
            let d = (point - Point(light.position, height: light.height)).length
            return .tooDim(maxLux: fullReading.lux, suggestedDistance: d * (mine / need).squareRoot())
        }
        return .output(max(minOutput, min(1, output)))
    }

    // MARK: Geometry helpers

    /// Segment–segment intersection in plan: parameter along a→b and the crossing point.
    static func intersect(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint, _ d: PlanPoint) -> (Double, PlanPoint)? {
        let r = b - a, s = d - c
        let denom = r.x * s.z - r.z * s.x
        guard abs(denom) > 1e-12 else { return nil }
        let ac = c - a
        let t = (ac.x * s.z - ac.z * s.x) / denom
        let u = (ac.x * r.z - ac.z * r.x) / denom
        guard t > 1e-4, t < 1 - 1e-4, u >= 0, u <= 1 else { return nil }
        return (t, a + r * t)
    }

    static func distance(_ p: PlanPoint, toSegment a: PlanPoint, _ b: PlanPoint) -> Double {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.z * ab.z
        guard len2 > 1e-12 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.z - a.z) * ab.z) / len2))
        return p.distance(to: a + ab * t)
    }
}

/// A meter position ready for the calculator, from a placed meter or a person's face.
struct MeterPoint: Identifiable {
    enum Source: Hashable { case meter(UUID), character(UUID) }
    var source: Source
    var name: String
    var point: LightingCalculator.Point
    var normal: LightingCalculator.Point
    var targetLux: Double?
    var id: Source { source }
}

/// A camera as the meters see it.
struct MeterCamera {
    var position: PlanPoint
    var height: Double
    var pan: Double
    var horizontalFOV: Double
}

extension Location {
    /// Cameras for pointing meters: shots first, then saved positions.
    var meterCameras: [MeterCamera] {
        (shots.map(\.rig) + cameraPositions.map(\.rig)).map {
            MeterCamera(position: $0.position, height: $0.height, pan: $0.pan, horizontalFOV: $0.horizontalFOV)
        }
    }

    /// Meter positions: every placed meter, and each person's face (eye height, metered towards camera).
    func meterPoints(scanID: UUID?) -> [MeterPoint] {
        let cams = meterCameras
        var result: [MeterPoint] = []
        for m in lightMeters where m.scanID == nil || m.scanID == scanID {
            let p = LightingCalculator.Point(m.position, height: m.height)
            result.append(MeterPoint(source: .meter(m.id), name: m.name, point: p,
                                     normal: MeterGeometry.normal(for: m.facing, bearing: m.bearing, at: p, cameras: cams),
                                     targetLux: m.targetLux))
        }
        for c in previsCharacters where c.scanID == nil || c.scanID == scanID {
            let p = LightingCalculator.Point(c.position, height: max(0.3, c.eyeHeight - 0.03))
            // A face is metered towards the camera; with no camera, along the way the person faces.
            let normal = cams.isEmpty
                ? LightingCalculator.direction(bearing: c.facing, tilt: 0)
                : MeterGeometry.normal(for: .camera, bearing: c.facing, at: p, cameras: cams)
            result.append(MeterPoint(source: .character(c.id), name: c.name, point: p, normal: normal, targetLux: nil))
        }
        return result
    }
}

enum MeterGeometry {
    /// Receptor direction. "Towards camera" uses the nearest camera that has the point in frame,
    /// else the nearest camera; with no cameras it falls back to the given bearing.
    static func normal(for facing: MeterFacing, bearing: Double, at p: LightingCalculator.Point, cameras: [MeterCamera]) -> LightingCalculator.Point {
        switch facing {
        case .up:
            return LightingCalculator.Point(x: 0, y: 1, z: 0)
        case .bearing:
            return LightingCalculator.direction(bearing: bearing, tilt: 0)
        case .camera:
            guard let cam = camera(seeing: p.plan, from: cameras) else {
                return LightingCalculator.direction(bearing: bearing, tilt: 0)
            }
            return (LightingCalculator.Point(cam.position, height: cam.height) - p).normalized
        }
    }

    static func camera(seeing point: PlanPoint, from cameras: [MeterCamera]) -> MeterCamera? {
        func inFrame(_ c: MeterCamera) -> Bool {
            let bearing = PlanGeometry.bearing(from: c.position, to: point)
            var diff = abs(bearing - c.pan).truncatingRemainder(dividingBy: 360)
            if diff > 180 { diff = 360 - diff }
            return diff <= c.horizontalFOV / 2
        }
        let framed = cameras.filter(inFrame)
        let pool = framed.isEmpty ? cameras : framed
        return pool.min { $0.position.distance(to: point) < $1.position.distance(to: point) }
    }
}
