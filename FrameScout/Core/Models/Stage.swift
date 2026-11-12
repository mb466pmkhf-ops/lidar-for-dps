import Foundation

// Studio builds, daylight and window dressing. Ported to web/src/model/stage.ts with the same ids,
// numbers and rules (tests on both sides, parity in CI). See Docs/DECISIONS.md D-013.
//
// - A studio backdrop (cyc, chroma screen, paper roll or LED wall) stands against one wall, and the
//   floor can be given a finish. Only the LED wall gives light in the readings; the others are
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
    /// Metres from the wall's middle, along the wall.
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

    static func backdropPlacement(_ loc: Location, plan: FloorPlan?) -> BackdropPlacement? {
        guard let st = loc.studio, let info = backdrop(st.backdrop), let plan else { return nil }
        guard let wall = plan.walls.first(where: { $0.id == st.wallID }) ?? defaultBackdropWall(loc, plan: plan) else { return nil }
        let L = wall.length
        let inward = inwardNormal(wall.a, wall.b, plan: plan)
        let def = info.kind == .cyc ? L : info.kind == .paper ? paperWidth : min(L, 6)
        let width = clamp(st.width ?? def, 0.5, L)
        let wallTop = wall.bottom + wall.height
        let defH = info.kind == .cyc ? wallTop : info.kind == .paper ? min(wallTop, 3.0) : min(wallTop, 3.5)
        let height = clamp(st.height ?? defH, 0.5, max(0.5, wallTop))
        var u = PlanPoint(x: (wall.b.x - wall.a.x) / L, z: (wall.b.z - wall.a.z) / L)
        if u.x * inward.z - u.z * inward.x < 0 { u = PlanPoint(x: -u.x, z: -u.z) }
        let half = width / 2
        let off = clamp(st.offset ?? 0, -(L / 2 - half), L / 2 - half)
        let off2 = standoff(info.kind)
        let mid = PlanPoint(x: (wall.a.x + wall.b.x) / 2 + u.x * off + inward.x * off2, z: (wall.a.z + wall.b.z) / 2 + u.z * off + inward.z * off2)
        return BackdropPlacement(info: info, wall: wall,
                                 a: PlanPoint(x: mid.x - u.x * half, z: mid.z - u.z * half), b: PlanPoint(x: mid.x + u.x * half, z: mid.z + u.z * half),
                                 inward: inward, width: width, height: height, sweep: sweep(info.kind),
                                 colour: info.pickColour ? (st.colour ?? info.colour) : info.colour)
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
        var ledWall: AreaSource?
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
        if let bd = backdropPlacement(loc, plan: plan), bd.info.kind == .led {
            let nits = clamp(loc.studio?.nits ?? ledDefaultNits, 0, ledNitsRange.upperBound)
            let along = PlanPoint(x: (bd.b.x - bd.a.x) / bd.width, z: (bd.b.z - bd.a.z) / bd.width)
            let led = AreaSource(id: ledWallID, origin: bd.a, bottom: bd.wall.bottom, along: along, width: bd.width, height: bd.height,
                                 facing: bd.inward, luminance: nits,
                                 columns: Int(clamp((bd.width / ledCell).rounded(), 2, 12)), rows: Int(clamp((bd.height / ledCell).rounded(), 2, 8)))
            var e = env ?? Environment()
            e.ledWall = led
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
