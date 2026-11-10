import Foundation

/// A room drawn by hand instead of scanned: a starting shape plus typed sizes become the same
/// `FloorPlan` a scan produces, so the 2D plan, the 3D view and the lighting maths all work on it.
/// Mirrors `web/src/model/room.ts`. Every size is typed in, so the result is marked manual.
struct DrawnRoom: Hashable {
    enum Shape: String, CaseIterable, Identifiable {
        case box, l
        var id: String { rawValue }
        var label: String { self == .box ? "Box" : "L shape" }
    }

    static let scanName = "Drawn by hand"
    static let sizeRange: ClosedRange<Double> = 1.5...60
    static let ceilingRange: ClosedRange<Double> = 1.8...20

    var shape: Shape = .box
    /// Longer side, along x (m).
    var length: Double = 6
    /// Shorter side, along z (m).
    var width: Double = 4.5
    var ceiling: Double = 2.7
    /// Windows spread along the top wall.
    var windows: Int = 1
    var door: Bool = true

    private static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
        v.isFinite ? min(r.upperBound, max(r.lowerBound, v)) : r.lowerBound
    }

    var normalised: DrawnRoom {
        var r = self
        r.length = Self.clamp(length, Self.sizeRange)
        r.width = Self.clamp(width, Self.sizeRange)
        r.ceiling = Self.clamp(ceiling, Self.ceilingRange)
        r.windows = min(4, max(0, windows))
        return r
    }

    /// Corners, clockwise from the top-left, centred on the origin. The L loses its bottom-right quarter.
    var outline: [PlanPoint] {
        let s = normalised
        let hx = s.length / 2, hz = s.width / 2
        if s.shape == .l {
            return [PlanPoint(x: -hx, z: -hz), PlanPoint(x: hx, z: -hz), PlanPoint(x: hx, z: 0),
                    PlanPoint(x: 0, z: 0), PlanPoint(x: 0, z: hz), PlanPoint(x: -hx, z: hz)]
        }
        return [PlanPoint(x: -hx, z: -hz), PlanPoint(x: hx, z: -hz), PlanPoint(x: hx, z: hz), PlanPoint(x: -hx, z: hz)]
    }

    var floorArea: Double {
        let s = normalised
        return s.length * s.width * (s.shape == .l ? 0.75 : 1)
    }

    var plan: FloorPlan {
        let s = normalised
        let corners = s.outline
        let hx = s.length / 2, hz = s.width / 2
        var plan = FloorPlan()
        plan.walls = corners.indices.map { i in
            PlanSegment(kind: .wall, a: corners[i], b: corners[(i + 1) % corners.count], height: s.ceiling, bottom: 0)
        }
        if s.windows > 0 {
            // Evenly spaced along the top wall, never wider than 1.4 m or 60% of their slot.
            let slot = s.length / Double(s.windows)
            let w = min(1.4, slot * 0.6)
            let top = min(s.ceiling - 0.2, 2.3), sill = min(0.8, top - 0.5)
            plan.windows = (0..<s.windows).map { i in
                let cx = -hx + slot * (Double(i) + 0.5)
                return PlanSegment(kind: .window, a: PlanPoint(x: cx - w / 2, z: -hz), b: PlanPoint(x: cx + w / 2, z: -hz),
                                   height: top - sill, bottom: sill)
            }
        }
        if s.door {
            // On the left wall, half a metre from the bottom corner when the wall is long enough.
            let dw = min(0.9, s.width * 0.5)
            let inset = min(0.5, (s.width - dw) / 2)
            plan.doors = [PlanSegment(kind: .door, a: PlanPoint(x: -hx, z: hz - inset), b: PlanPoint(x: -hx, z: hz - inset - dw),
                                      height: min(2.05, s.ceiling), bottom: 0)]
        }
        plan.floorPolygons = [corners]
        plan.bounds = PlanRect(minX: -hx, minZ: -hz, maxX: hx, maxZ: hz)
        return plan
    }

    var stats: ScanStats {
        let s = normalised
        let p = plan
        var st = ScanStats()
        st.floorArea = (floorArea * 100).rounded() / 100
        st.width = min(s.width, s.length)
        st.length = max(s.width, s.length)
        st.ceilingHeight = s.ceiling
        st.wallCount = p.walls.count
        st.doorCount = p.doors.count
        st.windowCount = p.windows.count
        st.floorCount = 1
        st.doors = p.doors.map { OpeningSize(width: $0.length, height: $0.height, sillHeight: 0) }
        st.windows = p.windows.map { OpeningSize(width: $0.length, height: $0.height, sillHeight: $0.bottom) }
        st.enteredByHand = true
        return st
    }

    /// The scan record that stands in for a capture. There is no mesh, only the plan.
    var scanRecord: ScanRecord {
        var record = ScanRecord(name: Self.scanName, kind: .room, stats: stats)
        record.notes = "Drawn by hand. Sizes were typed in, not measured."
        return record
    }
}
