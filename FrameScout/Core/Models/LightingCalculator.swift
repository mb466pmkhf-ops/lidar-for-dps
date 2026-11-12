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
/// - grip re-emits what lands on it like a matte surface (`BoardOptics`, D-013): bounce boards
///   reflect 80 %, flags and negs a few percent off the lit face, and a diffusion frame scatters
///   what it passes out of its far face as a soft source the size of the frame (one bounce);
/// - overlapping units add up.
///
/// What isn't: light reflected by walls, floor and ceiling, daylight, and furniture shadows.
/// Real readings in a room will usually be higher than these. Every result is an estimate.
/// How a piece of grip treats light that lands on it (same numbers as `boardOptics` on the web).
struct BoardOptics: Equatable {
    /// Fraction that gets through.
    var transmission: Double
    /// Share of what gets through that is diffused: 1 = full diffusion, 0 = a net (the beam just dims).
    var scatter: Double
    /// Fraction thrown back off the lit face.
    var reflectance: Double

    /// Defaults by kind (D-013): white board 0.8; black duvetyne about 3–4 %; a full diffusion passes
    /// about half, all of it scattered, and throws about a third back.
    static func defaults(for kind: LightKind) -> BoardOptics {
        switch kind {
        case .bounce: return BoardOptics(transmission: 0, scatter: 0, reflectance: 0.8)
        case .negative: return BoardOptics(transmission: 0, scatter: 0, reflectance: 0.03)
        case .flag: return BoardOptics(transmission: 0, scatter: 0, reflectance: 0.04)
        case .diffusion: return BoardOptics(transmission: 0.5, scatter: 1, reflectance: 0.35)
        default: return BoardOptics(transmission: 1, scatter: 0, reflectance: 0)
        }
    }
}

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
            /// The face is a rectangle round the pivot (`centre`, the stand's head), turned by pan and
            /// tilt: `right` is level, `up` lies in the face. It spans ±halfWidth along `right` and
            /// lo…hi along `up`; an opened floppy hangs its second panel below, so lo < −hi.
            var right: Point
            var up: Point
            var halfWidth: Double
            var lo: Double
            var hi: Double
            var area: Double
            var optics: BoardOptics
            /// Fraction that goes straight through, unscattered, when the board is in the way.
            var directTransmission: Double { optics.transmission * (1 - optics.scatter) }
        }
        /// One patch of a board lit by one unit, re-emitting like a matte surface into the side
        /// `normal` faces: the reflected part on the lit side, the scattered part out of the far side.
        struct Patch {
            var board: UUID
            var lightID: UUID
            var centre: Point
            var normal: Point
            var intensity: Double
            var radius: Double
        }

        var emitters: [Emitter] = []
        var boards: [Board] = []
        var walls: [PlanSegment] = []
        var apertures: [PlanSegment] = []
        var windowTransmission: Double = SceneDisplay.defaultWindowTransmission
        /// What the boards re-emit, worked out once per scene.
        var patches: [Patch] = []
        /// Each board is split into this many patches a side, so a frame half in the beam glows only where lit.
        static let patchesPerSide = 3

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
                    let span = l.gripSpan
                    let optics = l.drapeOptics.map { BoardOptics(transmission: $0.transmission, scatter: $0.scatter, reflectance: $0.reflectance) }
                        ?? BoardOptics.defaults(for: l.kind)
                    boards.append(Board(id: l.id, kind: l.kind, centre: Point(l.position, height: l.height), normal: axis,
                                        right: LightingCalculator.direction(bearing: l.pan + 90, tilt: 0),
                                        up: LightingCalculator.direction(bearing: l.pan, tilt: l.tilt + 90),
                                        halfWidth: span.width / 2, lo: span.bottom - l.height, hi: span.top - l.height,
                                        area: span.width * (span.top - span.bottom), optics: optics))
                }
            }
            patches = LightingCalculator.secondarySources(self)
        }
    }

    /// For each unit, the light landing on each board patch (with everything else in the way), sent
    /// back off the lit face and, through a diffusion, out of the far face. One bounce only.
    static func secondarySources(_ scene: Scene) -> [Scene.Patch] {
        var patches: [Scene.Patch] = []
        let n = Scene.patchesPerSide
        for board in scene.boards {
            let o = board.optics
            guard o.reflectance > 0 || o.transmission * o.scatter > 0 else { continue }
            let patchArea = board.area / Double(n * n), radius = (patchArea / .pi).squareRoot()
            for i in 0..<n {
                for j in 0..<n {
                    let x = ((Double(i) + 0.5) / Double(n) - 0.5) * 2 * board.halfWidth
                    let y = board.lo + (Double(j) + 0.5) / Double(n) * (board.hi - board.lo)
                    let centre = board.centre + board.right * x + board.up * y
                    for e in scene.emitters {
                        let side = (e.position - centre).dot(board.normal)
                        if side == 0 { continue }
                        let lit = side > 0 ? board.normal : board.normal * -1
                        let incident = illuminance(from: e, at: centre, normal: lit, scene: scene, ignoringBoard: board.id)
                        guard incident > 0 else { continue }
                        let each = incident * patchArea / .pi // a matte surface's intensity: exitance × area ÷ π
                        if o.reflectance > 0 {
                            patches.append(Scene.Patch(board: board.id, lightID: e.id, centre: centre, normal: lit, intensity: o.reflectance * each, radius: radius))
                        }
                        if o.transmission * o.scatter > 0 {
                            patches.append(Scene.Patch(board: board.id, lightID: e.id, centre: centre, normal: lit * -1, intensity: o.transmission * o.scatter * each, radius: radius))
                        }
                    }
                }
            }
        }
        return patches
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
        let ab = b - a
        for board in scene.boards where !ignoring.contains(board.id) {
            // Where the ray crosses the board's plane, and whether that's inside the face.
            let across = ab.dot(board.normal)
            guard abs(across) > 1e-12 else { continue }
            let s = (board.centre - a).dot(board.normal) / across
            guard s > 1e-4, s < 1 - 1e-4 else { continue }
            let q = a + ab * s - board.centre
            let y = q.dot(board.up)
            guard abs(q.dot(board.right)) <= board.halfWidth + 1e-9, y >= board.lo - 1e-9, y <= board.hi + 1e-9 else { continue }
            t *= board.directTransmission // what a diffusion scatters comes out as its own soft source
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
        for patch in scene.patches {
            let lux = fromPatch(patch, to: point, normal: normal, scene: scene)
            guard lux > 0 else { continue }
            // One contribution per unit and board, however many patches it came off.
            if let i = contributions.firstIndex(where: { $0.lightID == patch.lightID && $0.viaBounce == patch.board }) {
                contributions[i].lux += lux
            } else {
                contributions.append(Contribution(lightID: patch.lightID, lux: lux, viaBounce: patch.board))
            }
            total += lux
        }
        return Reading(lux: total, contributions: contributions)
    }

    /// Light one re-emitting patch sends to `point`: a small matte source (with the near-field term).
    static func fromPatch(_ patch: Scene.Patch, to point: Point, normal: Point, scene: Scene) -> Double {
        let toPoint = point - patch.centre
        let d = toPoint.length
        guard d > 0.05 else { return 0 }
        let v = toPoint * (1 / d)
        let out = v.dot(patch.normal), incidence = -v.dot(normal)
        guard out > 0, incidence > 0 else { return 0 }
        let lux = patch.intensity * out * incidence / (d * d + patch.radius * patch.radius)
        guard lux > 1e-6 else { return 0 }
        return lux * transmission(from: patch.centre, to: point, scene: scene, ignoring: [patch.board])
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
        /// Even at its lowest output (HMIs don't dim below about half) the unit overshoots the
        /// target: that output, and the total it gives here.
        case atMinimum(output: Double, lux: Double)
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
        if output < minOutput - 1e-9 { return .atMinimum(output: minOutput, lux: othersLux + mine * minOutput) }
        return .output(min(1, output))
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
