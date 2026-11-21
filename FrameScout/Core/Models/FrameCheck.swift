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

    /// Walls between the lens and the point hide it (doors and windows are treated as wall).
    private static func hiddenByWall(_ rig: CameraRig, _ p: PlanPoint, plan: FloorPlan?) -> Bool {
        guard let plan else { return false }
        for w in plan.walls {
            if let hit = LightingCalculator.intersect(rig.position, p, w.a, w.b), hit.0 > 1e-3, hit.0 < 1 - 1e-3 { return true }
        }
        return false
    }

    /// Points along a unit and its stand(s): the head (and both edges of anything wide), then the stand
    /// from the floor to just under the head. Rigged, floor and stand-less units have no stand.
    static func samplePoints(_ l: LightFixture) -> [(part: Part, p: Point)] {
        var out: [(part: Part, p: Point)] = []
        let side = PlanPoint.unit(bearing: l.pan + 90)
        let half = max(0, l.width) / 2
        func head(_ dx: Double) -> Point { Point(x: l.position.x + side.x * dx, y: l.height, z: l.position.z + side.z * dx) }
        out.append((.unit, head(0)))
        if half > 0.05 { out.append((.unit, head(-half))); out.append((.unit, head(half))) }
        let s = l.supportValue
        if s == .overhead || s == .floor || s == .none { return out }
        let legs: [Double] = l.gripStandCount == 2 ? [-half, half] : [0]
        for dx in legs {
            let at = head(dx)
            for t in [0.05, 0.35, 0.65] { out.append((.stand, Point(x: at.x, y: max(0.02, l.height * t), z: at.z))) }
            // The legs spread out round the base.
            for b in [0.0, 120, 240] {
                let d = PlanPoint.unit(bearing: l.pan + b)
                out.append((.stand, Point(x: at.x + d.x * standSpread, y: 0.02, z: at.z + d.z * standSpread)))
            }
        }
        return out
    }

    /// Units, grip and stands the camera would see, in the order they're listed in the room. Units that
    /// are off are still listed: a dark stand is still in shot.
    static func unitsInFrame(_ rig: CameraRig, lights: [LightFixture], plan: FloorPlan?) -> [Intrusion] {
        var result: [Intrusion] = []
        for l in lights where l.kind != .practical && l.role != .practical {
            var part: Part?
            for s in samplePoints(l) {
                guard pointInFrame(rig, s.p), !hiddenByWall(rig, PlanPoint(x: s.p.x, z: s.p.z), plan: plan) else { continue }
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
