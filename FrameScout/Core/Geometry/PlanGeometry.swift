import Foundation

/// 2D queries on a floor plan: clearance raycasts and snapping. Platform-independent.
enum PlanGeometry {
    /// Closest point on segment a–b to p.
    static func closestPoint(on a: PlanPoint, _ b: PlanPoint, to p: PlanPoint) -> PlanPoint {
        let d = b - a
        let len2 = d.x * d.x + d.z * d.z
        guard len2 > 1e-12 else { return a }
        let t = max(0, min(1, ((p.x - a.x) * d.x + (p.z - a.z) * d.z) / len2))
        return a + d * t
    }

    /// Distance from `origin` along world `bearing` to the first wall/object/obstacle hit.
    static func clearance(from origin: PlanPoint, bearing: Double, plan: FloorPlan,
                          includeObjects: Bool = true, maxDistance: Double = 60) -> Double? {
        let dir = PlanPoint.unit(bearing: bearing)
        var best: Double?

        func consider(_ a: PlanPoint, _ b: PlanPoint) {
            if let t = raySegment(origin: origin, dir: dir, a: a, b: b), t > 0.01, t < (best ?? maxDistance) {
                best = t
            }
        }

        // Doors and openings are passable only if they are open; windows are not.
        for w in plan.walls { consider(w.a, w.b) }
        if includeObjects {
            for o in plan.objects {
                let ux = PlanPoint(x: cos(o.rotation), z: sin(o.rotation))
                let uz = PlanPoint(x: -ux.z, z: ux.x)
                let hw = o.width / 2, hd = o.depth / 2
                let corners = [o.center + ux * -hw + uz * -hd, o.center + ux * hw + uz * -hd,
                               o.center + ux * hw + uz * hd, o.center + ux * -hw + uz * hd]
                for i in 0..<4 { consider(corners[i], corners[(i + 1) % 4]) }
            }
        }
        if !plan.occupancy.isEmpty {
            // Mesh scans: march through the occupancy grid.
            let cell = plan.occupancyCellSize
            let occupied = Set(plan.occupancy.map { cellKey($0, cell) })
            var t = cell
            let limit = best ?? maxDistance
            while t < limit {
                let p = origin + dir * t
                if occupied.contains(cellKey(p, cell)) { best = t; break }
                t += cell / 2
            }
        }
        return best
    }

    private static func cellKey(_ p: PlanPoint, _ cell: Double) -> Int64 {
        let ix = Int64((p.x / cell).rounded(.down)), iz = Int64((p.z / cell).rounded(.down))
        return (ix << 32) ^ (iz & 0xFFFF_FFFF)
    }

    /// Ray (origin + t·dir) against segment a–b. Returns t or nil.
    static func raySegment(origin: PlanPoint, dir: PlanPoint, a: PlanPoint, b: PlanPoint) -> Double? {
        let e = b - a
        let denom = dir.x * e.z - dir.z * e.x
        guard abs(denom) > 1e-9 else { return nil }
        let w = a - origin
        let t = (w.x * e.z - w.z * e.x) / denom
        let u = (w.x * dir.z - w.z * dir.x) / denom
        guard t >= 0, u >= -1e-6, u <= 1 + 1e-6 else { return nil }
        return t
    }

    /// Snaps to wall endpoints first, then onto wall lines, within `tolerance` metres.
    static func snap(_ p: PlanPoint, plan: FloorPlan, tolerance: Double) -> (point: PlanPoint, snapped: Bool) {
        var bestPoint = p
        var bestDistance = tolerance
        var snapped = false
        for w in plan.walls {
            for e in [w.a, w.b] where e.distance(to: p) < bestDistance * 0.9 {
                bestPoint = e
                bestDistance = e.distance(to: p)
                snapped = true
            }
        }
        if snapped { return (bestPoint, true) }
        for w in plan.walls {
            let c = closestPoint(on: w.a, w.b, to: p)
            let d = c.distance(to: p)
            if d < bestDistance {
                bestPoint = c
                bestDistance = d
                snapped = true
            }
        }
        return (bestPoint, snapped)
    }

    /// Bearing from a to b in the plan's world frame.
    static func bearing(from a: PlanPoint, to b: PlanPoint) -> Double {
        (b - a).worldBearing
    }

    struct Clearances {
        var front: Double?
        var behind: Double?
        var left: Double?
        var right: Double?
    }

    static func clearances(for rig: CameraRig, plan: FloorPlan) -> Clearances {
        Clearances(front: clearance(from: rig.position, bearing: rig.pan, plan: plan),
                   behind: clearance(from: rig.position, bearing: rig.pan + 180, plan: plan),
                   left: clearance(from: rig.position, bearing: rig.pan - 90, plan: plan),
                   right: clearance(from: rig.position, bearing: rig.pan + 90, plan: plan))
    }
}
