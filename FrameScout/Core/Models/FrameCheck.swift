import Foundation

/// What a camera would see that shouldn't be in the shot: units, their stands and grip frames.
/// Port of web/src/model/frameCheck.ts: keep the sample points and rules the same. Geometry only (no
/// lens distortion, no set pieces hiding things), so the panels call it a check, not a guarantee.
/// Practicals are meant to be seen and are never listed.
enum FrameCheck {
    enum Part: String { case unit, stand }
    struct Intrusion: Hashable { var id: UUID; var name: String; var part: Part }

    /// Nearer than this to the lens is ignored (the unit is beside the camera, not in front of it).
    static let near = 0.25
    /// How far a stand's legs reach from its column (m), roughly, for a C-stand or combo.
    static let standSpread = 0.4
    /// A MegaBoom's column stands this far behind the head, as the 3D view draws it (m).
    static let boomReach = 2.2

    typealias Point = LightingCalculator.Point

    /// True when the point sits inside the camera's frame (image area at the rig's focal length).
    static func pointInFrame(_ rig: CameraRig, _ p: Point) -> Bool {
        guard rig.focalLength > 0 else { return false }
        let area = rig.imageArea
        let f = LightingCalculator.direction(bearing: rig.pan, tilt: rig.tilt)
        let right = LightingCalculator.direction(bearing: rig.pan + 90, tilt: 0)
        // up = right × forward, so a camera tilted down still has its frame's top edge up.
        let up = Point(x: right.y * f.z - right.z * f.y, y: right.z * f.x - right.x * f.z, z: right.x * f.y - right.y * f.x)
        let v = Point(x: p.x - rig.position.x, y: p.y - rig.height, z: p.z - rig.position.z)
        let depth = v.x * f.x + v.y * f.y + v.z * f.z
        guard depth >= near else { return false }
        let sx = (v.x * right.x + v.y * right.y + v.z * right.z) / depth
        let sy = (v.x * up.x + v.y * up.y + v.z * up.z) / depth
        return abs(sx) <= area.width / (2 * rig.focalLength) && abs(sy) <= area.height / (2 * rig.focalLength)
    }

    /// Walls between the lens and the point hide it where the sight line passes between the wall's
    /// bottom and top (doors and windows are treated as wall).
    private static func hiddenByWall(_ rig: CameraRig, _ p: Point, plan: FloorPlan?) -> Bool {
        guard let plan else { return false }
        for w in plan.walls {
            guard let hit = LightingCalculator.intersect(rig.position, PlanPoint(x: p.x, z: p.z), w.a, w.b),
                  hit.0 > 1e-3, hit.0 < 1 - 1e-3 else { continue }
            let y = rig.height + (p.y - rig.height) * hit.0
            if y >= w.bottom && y <= w.bottom + w.height { return true }
        }
        return false
    }

    /// Points along a unit and its stand(s): the head (and both edges of anything wide), a board's whole
    /// face (tilt and an opened floppy included), a softbox's front, then the stand from the floor to just
    /// under the head (a MegaBoom's column and arm behind it). Rigged, floor and stand-less units have no stand.
    static func samplePoints(_ l: LightFixture) -> [(part: Part, p: Point)] {
        var out: [(part: Part, p: Point)] = []
        let side = PlanPoint.unit(bearing: l.pan + 90)
        let half = max(0, l.width) / 2
        func head(_ dx: Double) -> Point { Point(x: l.position.x + side.x * dx, y: l.height, z: l.position.z + side.z * dx) }
        out.append((.unit, head(0)))
        if half > 0.05 { out.append((.unit, head(-half))); out.append((.unit, head(half))) }
        if GripCatalog.gripKinds.contains(l.kind) {
            // The face runs lo…hi along its own up, which leans with the board's tilt.
            let span = l.gripSpan
            let up = LightingCalculator.direction(bearing: l.pan, tilt: l.tilt + 90)
            let lo = span.bottom - l.height, hi = span.top - l.height
            for du in [lo, (lo + hi) / 2, hi] {
                for dx in (half > 0.05 ? [-half, 0, half] : [0]) where du != 0 { out.append((.unit, head(dx) + up * du)) }
            }
        } else if let mod = FixtureLibrary.modifier(id: l.modifierID), mod.id.hasPrefix("softbox") {
            // Same face as the 3D view: radius size/2, its depth (size/2) plus the mount ahead of the head.
            let size = mod.size ?? 0.9, r = size / 2
            let axis = LightingCalculator.direction(bearing: l.pan, tilt: l.tilt)
            let right = LightingCalculator.direction(bearing: l.pan + 90, tilt: 0)
            let up = right.cross(axis)
            let face = head(0) + axis * (0.03 + size * 0.5)
            out.append((.unit, face))
            for (a, b) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] { out.append((.unit, face + right * (a * r) + up * (b * r))) }
        }
        let s = l.supportValue
        if s == .overhead || s == .floor || s == .none { return out }
        func column(_ at: Point) {
            for t in [0.05, 0.35, 0.65] { out.append((.stand, Point(x: at.x, y: max(0.02, l.height * t), z: at.z))) }
            // The legs spread out round the base.
            for b in [0.0, 120, 240] {
                let d = PlanPoint.unit(bearing: l.pan + b)
                out.append((.stand, Point(x: at.x + d.x * standSpread, y: 0.02, z: at.z + d.z * standSpread)))
            }
        }
        if s == .megaBoom {
            // The column stands behind the head; the arm runs out over the head and on to a counterweight.
            let back = PlanPoint.unit(bearing: l.pan + 180)
            let base = head(0)
            func arm(_ k: Double) -> Point { Point(x: base.x + back.x * k, y: l.height + 0.12, z: base.z + back.z * k) }
            let c = arm(boomReach)
            column(Point(x: c.x, y: l.height, z: c.z))
            for k in [0.5, 1.1, 1.65, boomReach + 0.95] { out.append((.stand, arm(k))) }
            return out
        }
        for dx in (l.gripStandCount == 2 ? [-half, half] : [0]) { column(head(dx)) }
        return out
    }

    /// Units, grip and stands the camera would see, in the order they're listed in the room. Units that
    /// are off are still listed: a dark stand is still in shot.
    static func unitsInFrame(_ rig: CameraRig, lights: [LightFixture], plan: FloorPlan?) -> [Intrusion] {
        var result: [Intrusion] = []
        for l in lights where l.kind != .practical && l.role != .practical {
            var part: Part?
            for s in samplePoints(l) {
                guard pointInFrame(rig, s.p), !hiddenByWall(rig, s.p, plan: plan) else { continue }
                if s.part == .unit { part = .unit; break }
                part = .stand
            }
            if let part { result.append(Intrusion(id: l.id, name: l.name, part: part)) }
        }
        return result
    }

    /// "Key and Fill are in shot", "Back's stand is in shot". Empty when the frame is clean.
    static func sentence(_ list: [Intrusion]) -> String {
        guard !list.isEmpty else { return "" }
        let units = list.filter { $0.part == .unit }.map(\.name)
        let stands = list.filter { $0.part == .stand }.map(\.name)
        func join(_ n: [String]) -> String { n.count <= 1 ? n.joined() : n.dropLast().joined(separator: ", ") + " and " + n.last! }
        var parts: [String] = []
        if !units.isEmpty { parts.append("\(join(units)) \(units.count == 1 ? "is" : "are") in shot") }
        if !stands.isEmpty { parts.append(stands.count == 1 ? "\(stands[0])'s stand is in shot" : "the stands of \(join(stands)) are in shot") }
        let s = parts.joined(separator: "; ")
        return s.prefix(1).uppercased() + s.dropFirst() + "."
    }
}
