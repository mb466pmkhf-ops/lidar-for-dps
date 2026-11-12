import Foundation

// Studio builds, daylight and window dressing. Ported to web/src/model/stage.ts with the same ids,
// numbers and rules (tests on both sides, parity in CI). See Docs/DECISIONS.md D-014.
//
// - A studio backdrop (cyc, chroma screen, paper roll or LED wall) stands against one wall or runs
//   on round several (a corner cyc, a U, an LED volume), and the floor can be given a finish. Only the LED wall gives light in the readings; the others are
//   surfaces, and the readings don't include light bouncing off surfaces.
// - Daylight: a sun and a sky outside the windows, from the location's clock (when the scan knows
//   north and the location has coordinates) or set by hand. Levels come from the IES daylight
//   availability model for a clear, hazy or overcast sky. Estimates: no buildings or trees outside,
//   a uniform sky, and no light reflected round the room.
// - Curtains on a window: sheer passes about half the light and turns sun into a soft glow, blackout
//   passes none.

// MARK: Settings stored on the location (all optional, so older files load)

enum SkyKind: String, Codable, CaseIterable, Identifiable {
    case clear, hazy, overcast
    var id: String { rawValue }
}

struct DaylightSetup: Codable, Hashable {
    var isOn: Bool? = nil
    var sky: SkyKind? = nil
    /// Place the sun from `time` and the location's coordinates (needs the scan's north).
    var fromClock: Bool? = nil
    /// Seconds since 1970 (UTC).
    var time: Double? = nil
    /// Set by hand: plan bearing the sun shines from (0 = plan up, clockwise), and its height.
    var sunBearing: Double? = nil
    var sunElevation: Double? = nil
}

struct StudioSetup: Codable, Hashable {
    /// `StageCatalog.backdrops` id; nil = no backdrop.
    var backdrop: String? = nil
    /// The wall it stands against; nil = the wall facing the camera (or the longest).
    var wallID: UUID? = nil
    /// Metres from the wall's middle, along the wall. nil = centred, or into the corner it shares
    /// with another backdrop wall.
    var offset: Double? = nil
    var width: Double? = nil
    var height: Double? = nil
    /// Paint or paper colour for the "colour" backdrops, #rrggbb.
    var colour: String? = nil
    /// LED wall: average brightness of what it shows, cd/m² (nits).
    var nits: Double? = nil
    /// LED wall: white point of the content, K (3D colour only).
    var kelvin: Double? = nil
    /// `StageCatalog.floors` id; nil = as scanned or drawn.
    var floor: String? = nil
    var floorColour: String? = nil
    /// The same backdrop carried on round more walls (a corner, a U). Each piece has its own width
    /// and place along its wall; where two pieces meet in a corner they join (a cyc curves round it).
    var moreWalls: [BackdropWall]? = nil
}

/// One more wall a backdrop runs on (see `StudioSetup.moreWalls`).
struct BackdropWall: Codable, Hashable {
    var wallID: UUID
    /// As `StudioSetup.offset` and `.width`, for this wall.
    var offset: Double? = nil
    var width: Double? = nil
}

enum CurtainKind: String, Codable, CaseIterable, Identifiable {
    case sheer, blackout
    var id: String { rawValue }
    var label: String { self == .sheer ? "Sheer" : "Blackout" }
    /// Share of light passed (sheer diffuses it; blackout stops it).
    var transmission: Double { self == .sheer ? Stage.sheerTransmission : 0 }
}

// MARK: Catalogues

enum BackdropKind: String { case cyc, paper, led }

struct BackdropInfo: Hashable, Identifiable {
    var id: String
    var label: String
    var kind: BackdropKind
    var colour: String
    /// Rough share of light the surface reflects (a guide; not in the readings).
    var reflectance: Double
    var pickColour = false
    var note: String
}

struct FloorInfo: Hashable, Identifiable {
    var id: String
    var label: String
    var colour: String
    var reflectance: Double
    var roughness: Double
    var pickColour = false
}

enum Stage {
    static let backdrops: [BackdropInfo] = [
        BackdropInfo(id: "cyc-white", label: "White cyc", kind: .cyc, colour: "#f1f1ee", reflectance: 0.85, note: "Curves into the floor, so there is no line where wall meets floor."),
        BackdropInfo(id: "cyc-black", label: "Black cyc", kind: .cyc, colour: "#151515", reflectance: 0.04, note: "Matt black. Takes light without giving much back."),
        BackdropInfo(id: "cyc-green", label: "Green screen", kind: .cyc, colour: "#3a9b4c", reflectance: 0.3, note: "Chroma green. Keep it evenly lit and keep people a few metres off it to cut spill."),
        BackdropInfo(id: "cyc-blue", label: "Blue screen", kind: .cyc, colour: "#2a54b0", reflectance: 0.18, note: "Chroma blue. Spills less than green, needs more light."),
        BackdropInfo(id: "cyc-colour", label: "Painted cyc", kind: .cyc, colour: "#c8b9a0", reflectance: 0.5, pickColour: true, note: "Any paint colour."),
        BackdropInfo(id: "led-wall", label: "LED wall", kind: .led, colour: "#0d0f12", reflectance: 0.03, note: "Gives light: it counts in the readings at the brightness you set."),
        BackdropInfo(id: "paper-white", label: "White paper roll", kind: .paper, colour: "#f4f4f1", reflectance: 0.85, note: "Seamless paper on two stands and a crossbar, swept onto the floor."),
        BackdropInfo(id: "paper-grey", label: "Mid-grey paper roll", kind: .paper, colour: "#8d8d8b", reflectance: 0.18, note: "About an 18 % grey card."),
        BackdropInfo(id: "paper-black", label: "Black paper roll", kind: .paper, colour: "#1a1a1a", reflectance: 0.05, note: ""),
        BackdropInfo(id: "paper-colour", label: "Colour paper roll", kind: .paper, colour: "#3c6e8f", reflectance: 0.3, pickColour: true, note: "Pick the colour."),
    ]

    static let floors: [FloorInfo] = [
        FloorInfo(id: "concrete-grey", label: "Grey concrete", colour: "#8f8c87", reflectance: 0.25, roughness: 0.8),
        FloorInfo(id: "concrete-black", label: "Black concrete", colour: "#262626", reflectance: 0.06, roughness: 0.55),
        FloorInfo(id: "concrete-colour", label: "Painted concrete", colour: "#6b7f73", reflectance: 0.2, roughness: 0.6, pickColour: true),
        FloorInfo(id: "painted-white", label: "White painted floor", colour: "#ecebe7", reflectance: 0.8, roughness: 0.5),
    ]

    static func backdrop(_ id: String?) -> BackdropInfo? { backdrops.first { $0.id == id } }
    static func floor(_ id: String?) -> FloorInfo? { floors.first { $0.id == id } }

    /// Standard seamless paper width (m).
    static let paperWidth = 2.72
    static let ledDefaultNits = 300.0
    static let ledNitsRange = 10.0...2000.0
    static func standoff(_ k: BackdropKind) -> Double { k == .cyc ? 0.02 : k == .paper ? 0.35 : 0.15 }
    static func sweep(_ k: BackdropKind) -> Double { k == .cyc ? 1.5 : k == .paper ? 2.0 : 0 }

    static let sheerTransmission = 0.5
    static func curtainPass(_ c: CurtainKind?) -> Double { c?.transmission ?? 1 }

    // MARK: Daylight levels (IES daylight availability model)

    struct SkyModel { var label: String; var extinction: Double; var a: Double; var b: Double; var c: Double }
    /// IES Lighting Handbook coefficients: extinction for the direct sun, and the sky's horizontal
    /// illuminance A + B·sin(α)^C in kilolux.
    static func sky(_ k: SkyKind) -> SkyModel {
        switch k {
        case .clear: return SkyModel(label: "Clear", extinction: 0.21, a: 0.8, b: 15.5, c: 0.5)
        case .hazy: return SkyModel(label: "Hazy, some cloud", extinction: 0.8, a: 0.3, b: 45.0, c: 1.0)
        case .overcast: return SkyModel(label: "Overcast", extinction: .infinity, a: 0.3, b: 21.0, c: 1.0)
        }
    }
    /// Sunlight above the atmosphere, lux.
    static let extraterrestrialLux = 127500.0
    static let groundReflectance = 0.2

    /// Relative air mass at elevation `el` degrees (Kasten & Young 1989).
    static func airMass(_ el: Double) -> Double {
        1 / (sin(el * .pi / 180) + 0.50572 * pow(el + 6.07995, -1.6364))
    }

    struct DaylightLevels: Hashable {
        /// Sun on a surface square to it, lux.
        var directNormal: Double
        /// Sky alone on a level surface, lux.
        var skyHorizontal: Double
    }

    static func daylightLevels(_ sky: SkyKind, elevation: Double) -> DaylightLevels {
        let k = Self.sky(sky)
        guard elevation > -6 else { return DaylightLevels(directNormal: 0, skyHorizontal: 0) }
        if elevation <= 0 { return DaylightLevels(directNormal: 0, skyHorizontal: k.a * 1000 * (elevation + 6) / 6) }
        let s = sin(elevation * .pi / 180)
        let direct = k.extinction.isFinite ? extraterrestrialLux * Foundation.exp(-k.extinction * airMass(elevation)) : 0
        return DaylightLevels(directNormal: direct, skyHorizontal: (k.a + k.b * pow(s, k.c)) * 1000)
    }

    /// What a window shows from inside, before the glass: sky in its upper half, sunlit ground in
    /// the lower half (uniform sky, nothing outside). cd/m².
    static func windowViewLuminance(_ l: DaylightLevels, elevation: Double) -> Double {
        let s = max(0, sin(elevation * .pi / 180))
        let ground = groundReflectance * (l.skyHorizontal + l.directNormal * s)
        return 0.5 * l.skyHorizontal / .pi + 0.5 * ground / .pi
    }

    // MARK: Where the sun is

    static let defaultSunBearing = 135.0
    static let defaultSunElevation = 35.0

    struct SunPlacement: Hashable {
        /// Plan bearing the sun shines from (0 = plan up, clockwise).
        var bearing: Double
        var elevation: Double
        var fromClock: Bool
        /// True bearing from north, when known.
        var azimuth: Double?
    }

    /// Why the clock can't place the sun, or nil when it can.
    static func clockProblem(_ loc: Location, scan: ScanRecord?) -> String? {
        if loc.coordinate == nil { return "The location has no coordinates. Add the address or a pin first." }
        if scan?.northOffset == nil { return "The scan doesn't know which way is north. Set north, or place the sun by hand." }
        return nil
    }

    static func sunPlacement(_ loc: Location, scan: ScanRecord?) -> SunPlacement {
        let d = loc.daylight ?? DaylightSetup()
        if d.fromClock == true, let time = d.time, clockProblem(loc, scan: scan) == nil,
           let c = loc.coordinate, let north = scan?.northOffset {
            let pos = SolarCalculator.position(date: Date(timeIntervalSince1970: time), latitude: c.latitude, longitude: c.longitude)
            var bearing = (pos.azimuth - north + 360).truncatingRemainder(dividingBy: 360)
            bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)
            return SunPlacement(bearing: bearing, elevation: pos.elevation, fromClock: true, azimuth: pos.azimuth)
        }
        return SunPlacement(bearing: d.sunBearing ?? defaultSunBearing, elevation: d.sunElevation ?? defaultSunElevation, fromClock: false, azimuth: nil)
    }

    // MARK: Room geometry

    static func pointInPolygon(_ p: PlanPoint, _ poly: [PlanPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.z > p.z) != (b.z > p.z) && p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Inside the room: in a floor polygon, or inside the plan's bounds when it has none.
    static func insideRoom(_ p: PlanPoint, plan: FloorPlan) -> Bool {
        let polys = plan.floorPolygons.filter { $0.count >= 3 }
        if !polys.isEmpty { return polys.contains { pointInPolygon(p, $0) } }
        let b = plan.bounds
        return p.x > b.minX && p.x < b.maxX && p.z > b.minZ && p.z < b.maxZ
    }

    /// Unit normal of a wall or window pointing into the room.
    static func inwardNormal(_ a: PlanPoint, _ b: PlanPoint, plan: FloorPlan) -> PlanPoint {
        let len = a.distance(to: b)
        let L = len > 0 ? len : 1e-6
        let n = PlanPoint(x: -(b.z - a.z) / L, z: (b.x - a.x) / L)
        let mid = PlanPoint(x: (a.x + b.x) / 2, z: (a.z + b.z) / 2)
        let plus = insideRoom(PlanPoint(x: mid.x + n.x * 0.3, z: mid.z + n.z * 0.3), plan: plan)
        let minus = insideRoom(PlanPoint(x: mid.x - n.x * 0.3, z: mid.z - n.z * 0.3), plan: plan)
        if plus != minus { return plus ? n : PlanPoint(x: -n.x, z: -n.z) }
        let c = PlanPoint(x: (plan.bounds.minX + plan.bounds.maxX) / 2, z: (plan.bounds.minZ + plan.bounds.maxZ) / 2)
        return (c.x - mid.x) * n.x + (c.z - mid.z) * n.z >= 0 ? n : PlanPoint(x: -n.x, z: -n.z)
    }

    // MARK: Backdrop placement

    struct BackdropPlacement: Hashable {
        var info: BackdropInfo
        var wall: PlanSegment
        /// Left and right ends of its face, seen from the room.
        var a: PlanPoint
        var b: PlanPoint
        /// Into the room.
        var inward: PlanPoint
        var width: Double
        var height: Double
        var sweep: Double
        var colour: String
        /// Where it sits along its wall: metres from the wall's middle (before any corner trim).
        var offset: Double = 0
    }

    /// The wall a backdrop goes on when none is chosen: the one the camera looks at, else the longest.
    static func defaultBackdropWall(_ loc: Location, plan: FloorPlan) -> PlanSegment? {
        let walls = plan.walls.filter { $0.length > 0.5 }
        guard let first = walls.first else { return nil }
        if let rig = loc.shots.first?.rig ?? loc.cameraPositions.first?.rig {
            let r = PlanPoint(x: sin(rig.pan * .pi / 180), z: -cos(rig.pan * .pi / 180))
            var best: (w: PlanSegment, t: Double)?
            for w in walls {
                let s = w.b - w.a
                let denom = r.x * s.z - r.z * s.x
                if abs(denom) < 1e-9 { continue }
                let ac = w.a - rig.position
                let t = (ac.x * s.z - ac.z * s.x) / denom, u = (ac.x * r.z - ac.z * r.x) / denom
                if t > 0.1, u >= 0, u <= 1, best == nil || t < best!.t { best = (w, t) }
            }
            if let best { return best.w }
        }
        // The first longest, like the web.
        return walls.reduce(first) { $1.length > $0.length ? $1 : $0 }
    }

    /// Where two backdrop pieces meet in an inside corner. `point` is where their faces would meet;
    /// a cyc curves round a vertical radius centred on `centre`, so each piece stops `radius` short of
    /// the bend at its tangent point. Paper and LED pieces simply butt together (radius 0).
    struct BackdropCorner: Hashable {
        var point: PlanPoint
        var centre: PlanPoint
        var radius: Double
        /// Tangent points on the two faces, and the two faces' into-the-room directions.
        var tangentA: PlanPoint
        var tangentB: PlanPoint
        var inwardA: PlanPoint
        var inwardB: PlanPoint
        var height: Double
        var bottom: Double
    }

    struct BackdropLayout: Hashable {
        var info: BackdropInfo
        /// The first is on the main wall (`StudioSetup.wallID`).
        var pieces: [BackdropPlacement]
        var corners: [BackdropCorner]
        var sweep: Double { pieces.first?.sweep ?? 0 }
        var colour: String { pieces.first?.colour ?? info.colour }
    }

    /// Radius of the vertical bend where a cyc turns a corner (more than the 0.5–0.6 m floor cove).
    static let cycCornerRadius = 0.75
    /// How close two wall ends must be to count as the same corner.
    static let cornerSnap = 0.15

    private static let sideNames = ["Top", "Top right", "Right", "Bottom right", "Bottom", "Bottom left", "Left", "Top left"]
    /// Names for the walls as they sit on the plan ("Top wall", "Left wall"; numbered when two share a
    /// side), for walls longer than half a metre. Same as the web.
    static func wallNames(_ plan: FloorPlan) -> [UUID: String] {
        let walls = plan.walls.filter { $0.length > 0.5 }
        let side = walls.map { w -> String in
            let n = inwardNormal(w.a, w.b, plan: plan)
            // The wall sits on the side opposite its inward normal; plan up is −z.
            let bearing = (atan2(-n.x, n.z) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            return sideNames[Int((bearing / 45).rounded()) % 8]
        }
        var out: [UUID: String] = [:]
        for (i, w) in walls.enumerated() {
            let same = side.filter { $0 == side[i] }.count
            let k = side[...i].filter { $0 == side[i] }.count
            out[w.id] = same > 1 ? "\(side[i]) wall \(k)" : "\(side[i]) wall"
        }
        return out
    }

    /// Two walls that meet end to end (a corner a backdrop can turn).
    static func wallsTouch(_ w: PlanSegment, _ o: PlanSegment) -> Bool {
        [w.a, w.b].contains { p in [o.a, o.b].contains { $0.distance(to: p) < cornerSnap } }
    }

    static func defaultBackdropWidth(_ k: BackdropKind, wallLength L: Double) -> Double {
        k == .cyc ? L : k == .paper ? paperWidth : min(L, 6)
    }

    /// The main piece only (the wall the backdrop was first put on).
    static func backdropPlacement(_ loc: Location, plan: FloorPlan?) -> BackdropPlacement? {
        backdropLayout(loc, plan: plan)?.pieces.first
    }

    /// Every piece of the backdrop, trimmed where pieces meet in a corner, and the corners.
    static func backdropLayout(_ loc: Location, plan: FloorPlan?) -> BackdropLayout? {
        guard let st = loc.studio, let info = backdrop(st.backdrop), let plan else { return nil }
        guard let main = plan.walls.first(where: { $0.id == st.wallID }) ?? defaultBackdropWall(loc, plan: plan) else { return nil }
        var parts: [(wall: PlanSegment, offset: Double?, width: Double?)] = [(main, st.offset, st.width)]
        for m in st.moreWalls ?? [] {
            guard let w = plan.walls.first(where: { $0.id == m.wallID }), w.length > 0.5, !parts.contains(where: { $0.wall.id == w.id }) else { continue }
            parts.append((w, m.offset, m.width))
        }
        let ends = parts.map { [$0.wall.a, $0.wall.b] }
        /// Does this end of wall `i` meet another backdrop wall?
        func shared(_ i: Int, _ p: PlanPoint) -> Bool {
            ends.indices.contains { j in j != i && ends[j].contains { $0.distance(to: p) < cornerSnap } }
        }
        var pieces: [BackdropPlacement] = []
        for (i, part) in parts.enumerated() {
            let wall = part.wall, L = wall.length
            let inward = inwardNormal(wall.a, wall.b, plan: plan)
            let width = clamp(part.width ?? defaultBackdropWidth(info.kind, wallLength: L), 0.5, L)
            let wallTop = wall.bottom + wall.height
            let defH = info.kind == .cyc ? wallTop : info.kind == .paper ? min(wallTop, 3.0) : min(wallTop, 3.5)
            let height = clamp(st.height ?? defH, 0.5, max(0.5, wallTop))
            var u = PlanPoint(x: (wall.b.x - wall.a.x) / L, z: (wall.b.z - wall.a.z) / L)
            if u.x * inward.z - u.z * inward.x < 0 { u = PlanPoint(x: -u.x, z: -u.z) }
            let half = width / 2, slack = L / 2 - half
            let wallMid = PlanPoint(x: (wall.a.x + wall.b.x) / 2, z: (wall.a.z + wall.b.z) / 2)
            var off = part.offset ?? 0
            if part.offset == nil, slack > 1e-6 {
                // Into the corner it shares with another backdrop wall.
                let left = shared(i, PlanPoint(x: wallMid.x - u.x * L / 2, z: wallMid.z - u.z * L / 2))
                let right = shared(i, PlanPoint(x: wallMid.x + u.x * L / 2, z: wallMid.z + u.z * L / 2))
                if left != right { off = left ? -slack : slack }
            }
            off = clamp(off, -slack, slack)
            let off2 = standoff(info.kind)
            let mid = PlanPoint(x: wallMid.x + u.x * off + inward.x * off2, z: wallMid.z + u.z * off + inward.z * off2)
            pieces.append(BackdropPlacement(info: info, wall: wall,
                                            a: PlanPoint(x: mid.x - u.x * half, z: mid.z - u.z * half), b: PlanPoint(x: mid.x + u.x * half, z: mid.z + u.z * half),
                                            inward: inward, width: width, height: height, sweep: sweep(info.kind),
                                            colour: info.pickColour ? (st.colour ?? info.colour) : info.colour, offset: off))
        }
        // Join pieces whose ends reach the same room corner.
        var corners: [BackdropCorner] = []
        let reach = standoff(info.kind) + 0.05
        /// The end of piece `k` (0 = a, 1 = b) that sits at a wall end, and that wall end.
        func atCorner(_ k: Int, _ end: Int) -> PlanPoint? {
            let p = pieces[k], e = end == 0 ? p.a : p.b
            return [p.wall.a, p.wall.b].first { $0.distance(to: e) < reach * 1.5 }
        }
        for i in pieces.indices {
            for j in pieces.indices where j > i {
                for ei in 0..<2 {
                    for ej in 0..<2 {
                        guard let ci = atCorner(i, ei), let cj = atCorner(j, ej), ci.distance(to: cj) < cornerSnap else { continue }
                        let pi = pieces[i], pj = pieces[j]
                        let ei0 = ei == 0 ? pi.a : pi.b, ei1 = ei == 0 ? pi.b : pi.a
                        let ej0 = ej == 0 ? pj.a : pj.b, ej1 = ej == 0 ? pj.b : pj.a
                        // Where the two faces meet.
                        let di = (ei1 - ei0) * (1 / max(ei0.distance(to: ei1), 1e-9))
                        let dj = (ej1 - ej0) * (1 / max(ej0.distance(to: ej1), 1e-9))
                        let denom = di.x * dj.z - di.z * dj.x
                        guard abs(denom) > 0.05 else { continue }
                        let w = ej0 - ei0
                        let t = (w.x * dj.z - w.z * dj.x) / denom
                        let x = ei0 + di * t
                        // Inside corners only: each piece on the room side of the other.
                        guard (ei1 - x).dot(pj.inward) > 0.05, (ej1 - x).dot(pi.inward) > 0.05 else { continue }
                        let fi = (ei1 - x).dot(di) >= 0 ? di : di * -1
                        let fj = (ej1 - x).dot(dj) >= 0 ? dj : dj * -1
                        let phi = acos(max(-1, min(1, fi.dot(fj))))
                        let leni = x.distance(to: ei1), lenj = x.distance(to: ej1)
                        var r = info.kind == .cyc ? cycCornerRadius : 0
                        var tn = r > 0 ? r / tan(phi / 2) : 0
                        let room = min(leni, lenj) * 0.5
                        if tn > room { r *= room / tn; tn = room }
                        let ti = x + fi * tn, tj = x + fj * tn
                        let bis = (fi + fj) * (1 / max((fi + fj).length, 1e-9))
                        let centre = r > 0 ? x + bis * (r / sin(phi / 2)) : x
                        var a = pieces[i], b = pieces[j]
                        if ei == 0 { a.a = ti } else { a.b = ti }
                        if ej == 0 { b.a = tj } else { b.b = tj }
                        a.width = a.a.distance(to: a.b)
                        b.width = b.a.distance(to: b.b)
                        pieces[i] = a
                        pieces[j] = b
                        corners.append(BackdropCorner(point: x, centre: centre, radius: r, tangentA: ti, tangentB: tj, inwardA: a.inward, inwardB: b.inward,
                                                      height: min(a.height, b.height), bottom: max(a.wall.bottom, b.wall.bottom)))
                    }
                }
            }
        }
        return BackdropLayout(info: info, pieces: pieces, corners: corners)
    }

    /// The floor a corner covers: between the two faces, out to `sweep` from each.
    static func cornerFootprint(_ c: BackdropCorner, sweep: Double) -> [PlanPoint] {
        // The point `sweep` in from both faces: (q − x)·nA = (q − x)·nB = sweep.
        let a = c.inwardA, b = c.inwardB
        let det = a.x * b.z - a.z * b.x
        guard abs(det) > 1e-6 else { return [] }
        let q = PlanPoint(x: c.point.x + sweep * (b.z - a.z) / det, z: c.point.z + sweep * (a.x - b.x) / det)
        return [c.point, c.tangentA, c.tangentA + a * sweep, q, c.tangentB + b * sweep, c.tangentB]
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    // MARK: For the calculator

    /// A flat vertical rectangle that gives diffuse light: a window seen from inside, or an LED wall.
    struct AreaSource: Hashable {
        var id: UUID
        /// Bottom-left corner, seen from the side it lights.
        var origin: PlanPoint
        var bottom: Double
        /// Unit direction along its width.
        var along: PlanPoint
        var width: Double
        var height: Double
        /// Unit plan direction it lights towards.
        var facing: PlanPoint
        var luminance: Double
        var columns: Int
        var rows: Int
    }

    struct Environment: Hashable {
        struct Sun: Hashable { var bearing: Double; var elevation: Double; var directNormal: Double }
        var sun: Sun?
        /// What a window shows from inside, before glass and curtains.
        var windowLuminance: Double = 0
        /// One per LED piece (a volume round several walls has several); all count as "LED wall".
        var ledWalls: [AreaSource] = []
    }

    static let sunID = UUID(uuidString: "5A11D000-0000-4000-8000-000000000001")!
    static let skyID = UUID(uuidString: "5A11D000-0000-4000-8000-000000000002")!
    static let ledWallID = UUID(uuidString: "5A11D000-0000-4000-8000-000000000003")!

    static func ambientName(_ id: UUID) -> String? {
        switch id {
        case sunID: return "Sun through the window"
        case skyID: return "Daylight through the windows"
        case ledWallID: return "LED wall"
        default: return nil
        }
    }

    static let ledCell = 0.5
    static let windowCell = 0.4

    static func environment(_ loc: Location, plan: FloorPlan?, scan: ScanRecord?) -> Environment? {
        var env: Environment?
        if let d = loc.daylight, d.isOn == true {
            let sun = sunPlacement(loc, scan: scan)
            let levels = daylightLevels(d.sky ?? .clear, elevation: sun.elevation)
            var e = Environment(windowLuminance: windowViewLuminance(levels, elevation: sun.elevation))
            if levels.directNormal > 0 { e.sun = .init(bearing: sun.bearing, elevation: sun.elevation, directNormal: levels.directNormal) }
            env = e
        }
        if let layout = backdropLayout(loc, plan: plan), layout.info.kind == .led {
            let nits = clamp(loc.studio?.nits ?? ledDefaultNits, 0, ledNitsRange.upperBound)
            var e = env ?? Environment()
            for bd in layout.pieces where bd.width > 0.01 {
                let along = PlanPoint(x: (bd.b.x - bd.a.x) / bd.width, z: (bd.b.z - bd.a.z) / bd.width)
                e.ledWalls.append(AreaSource(id: ledWallID, origin: bd.a, bottom: bd.wall.bottom, along: along, width: bd.width, height: bd.height,
                                             facing: bd.inward, luminance: nits,
                                             columns: Int(clamp((bd.width / ledCell).rounded(), 2, 12)), rows: Int(clamp((bd.height / ledCell).rounded(), 2, 8))))
            }
            env = e
        }
        return env
    }
}

extension Location {
    /// Light from outside and from the set for the calculator (nil when there is none).
    func environment(plan: FloorPlan?, scan: ScanRecord?) -> Stage.Environment? {
        Stage.environment(self, plan: plan, scan: scan)
    }
}

private extension PlanPoint {
    func dot(_ o: PlanPoint) -> Double { x * o.x + z * o.z }
    var length: Double { (x * x + z * z).squareRoot() }
}
