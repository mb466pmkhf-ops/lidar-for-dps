import Foundation

/// Keeps stand-in people out of the furniture: a standing person is moved to the nearest free
/// floor beside a piece, and a sitting person dropped on a sofa, chair or bed sits on its seat at
/// the seat's height. Mirrors web/src/model/placement.ts; keep the numbers identical (tests on
/// both sides check the same cases).
///
/// Seat heights and sitting lines follow the furniture the 3D views draw (`PlanSceneBuilder`,
/// web room.ts), so a seated figure rests on the cushion rather than inside it. They are drawing
/// sizes, not measurements: nothing here is shown as a figure.
enum Placement {
    /// How close (m) to a seat a sitting person may be dropped and still sit on it.
    static let seatReach = 0.15
    /// Switching a person to Sitting finds a seat this close (m).
    static let sitDownReach = 0.6
    /// A seated person may turn this far (°) from straight ahead on the seat before they are squared up.
    static let seatTurn = 45.0
    /// Gap (m) left between a person and the furniture they are moved away from.
    static let gap = 0.02

    private static func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    static func distToWalls(_ p: PlanPoint, _ walls: [PlanSegment]) -> Double {
        var best = Double.infinity
        for w in walls {
            let dx = w.b.x - w.a.x, dz = w.b.z - w.a.z
            let l2 = dx * dx + dz * dz > 0 ? dx * dx + dz * dz : 1e-6
            let t = clamp(((p.x - w.a.x) * dx + (p.z - w.a.z) * dz) / l2, 0, 1)
            best = min(best, ((p.x - (w.a.x + dx * t)) * (p.x - (w.a.x + dx * t)) + (p.z - (w.a.z + dz * t)) * (p.z - (w.a.z + dz * t))).squareRoot())
        }
        return best
    }

    /// Local axes of a piece: X along its width, Z along its depth.
    static func widthAxis(_ o: PlanObject) -> PlanPoint { PlanPoint(x: cos(o.rotation), z: sin(o.rotation)) }
    static func depthAxis(_ o: PlanObject) -> PlanPoint { PlanPoint(x: -sin(o.rotation), z: cos(o.rotation)) }

    /// Which long side (+1 or −1 along local Z) backs onto the nearest wall.
    static func backSide(_ o: PlanObject, walls: [PlanSegment]) -> Double {
        let ax = depthAxis(o)
        func at(_ s: Double) -> Double {
            distToWalls(PlanPoint(x: o.center.x + ax.x * s * o.depth / 2, z: o.center.z + ax.z * s * o.depth / 2), walls)
        }
        return at(1) <= at(-1) ? 1 : -1
    }

    enum SeatKind { case sofa, chair, bed }

    static func seatKind(_ category: String) -> SeatKind? {
        let k = category.lowercased()
        if k.contains("sofa") || k.contains("couch") { return .sofa }
        if k.contains("chair") || k.contains("stool") { return .chair }
        if k.contains("bed") { return .bed }
        return nil
    }

    /// Shapes the 3D views draw for seats (m).
    static func sofaShape(_ o: PlanObject) -> (seat: Double, arm: Double, back: Double) {
        (min(0.44, o.height * 0.55), min(0.2, o.width * 0.12), min(0.24, o.depth * 0.3))
    }
    static func chairSeat(_ o: PlanObject) -> Double { min(0.46, o.height * 0.55) }
    static func bedBase(_ o: PlanObject) -> Double { min(0.3, o.height * 0.5) }

    /// Pieces a person can't stand in. Stairs and anything flat on the floor are walked on.
    static func isSolid(_ o: PlanObject) -> Bool {
        o.height >= 0.05 && !o.category.lowercased().contains("stair")
    }

    struct Seat {
        var object: PlanObject
        var kind: SeatKind
        /// Top of the cushion or mattress above the floor (m).
        var height: Double
        /// Middle of the line a person's hips sit on, the direction along it, and how far either way they can slide.
        var centre: PlanPoint
        var along: PlanPoint
        var reach: Double
        /// The way a seated person faces.
        var front: PlanPoint
    }

    /// Where a person sits on a piece. A bed is sat on along the long side nearest `near`.
    static func seat(of o: PlanObject, plan: FloorPlan, near: PlanPoint? = nil) -> Seat? {
        guard let kind = seatKind(o.category), isSolid(o) else { return nil }
        let ax = widthAxis(o), az = depthAxis(o), d = o.depth
        if kind == .bed {
            let lz = near.map { ($0.x - o.center.x) * az.x + ($0.z - o.center.z) * az.z } ?? 1
            let side: Double = lz >= 0 ? 1 : -1
            let z = side * (d / 2 - min(d / 2, 0.2))
            return Seat(object: o, kind: kind, height: r3(bedBase(o) + 0.22),
                        centre: PlanPoint(x: o.center.x + az.x * z, z: o.center.z + az.z * z), along: ax,
                        reach: max(0, o.width / 2 - 0.45), front: PlanPoint(x: az.x * side, z: az.z * side))
        }
        let back = backSide(o, walls: plan.walls)
        let inset: Double, height: Double, reach: Double
        if kind == .sofa {
            let s = sofaShape(o)
            // Hips sit a body's half depth in front of the back cushions.
            inset = min(d / 2, s.back + 0.25)
            height = s.seat
            reach = max(0, o.width / 2 - s.arm - 0.25)
        } else {
            inset = min(d / 2, 0.16)
            height = chairSeat(o) + 0.025
            reach = max(0, o.width / 2 - 0.3)
        }
        let z = back * (d / 2 - inset)
        return Seat(object: o, kind: kind, height: r3(height),
                    centre: PlanPoint(x: o.center.x + az.x * z, z: o.center.z + az.z * z), along: ax,
                    reach: reach, front: PlanPoint(x: -az.x * back, z: -az.z * back))
    }

    private static func local(_ o: PlanObject, _ p: PlanPoint) -> PlanPoint {
        let ax = widthAxis(o), az = depthAxis(o), dx = p.x - o.center.x, dz = p.z - o.center.z
        return PlanPoint(x: dx * ax.x + dz * ax.z, z: dx * az.x + dz * az.z)
    }

    private static func world(_ o: PlanObject, _ q: PlanPoint) -> PlanPoint {
        let ax = widthAxis(o), az = depthAxis(o)
        return PlanPoint(x: o.center.x + ax.x * q.x + az.x * q.z, z: o.center.z + ax.z * q.x + az.z * q.z)
    }

    /// The seat whose footprint (grown by `margin`) holds `p`, the closest to its middle first.
    static func seat(at p: PlanPoint, plan: FloorPlan, margin: Double = seatReach) -> Seat? {
        var best: (seat: Seat, d: Double)?
        for o in plan.objects where seatKind(o.category) != nil && isSolid(o) {
            let q = local(o, p)
            guard abs(q.x) <= o.width / 2 + margin, abs(q.z) <= o.depth / 2 + margin else { continue }
            let ox = max(0, abs(q.x) - o.width / 2), oz = max(0, abs(q.z) - o.depth / 2)
            let d = (ox * ox + oz * oz).squareRoot() + (q.x * q.x + q.z * q.z).squareRoot() * 1e-3
            if let s = seat(of: o, plan: plan, near: p), best == nil || d < best!.d { best = (s, d) }
        }
        return best?.seat
    }

    /// How much floor a person takes up, as a circle round their position (m).
    static func bodyRadius(_ c: PrevisCharacter) -> Double { max(0.15, c.height * 0.12) }

    private static func bearing(of dir: PlanPoint) -> Double { atan2(dir.x, -dir.z) * 180 / .pi }
    private static func wrap180(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x <= -180 { x += 360 }
        return x
    }
    private static func wrap360(_ a: Double) -> Double {
        let x = a.truncatingRemainder(dividingBy: 360)
        return x < 0 ? x + 360 : x
    }

    /// Seats a person on a seat: hips on its sitting line, facing out (or turned a little), at its height.
    static func sit(_ c: PrevisCharacter, on seat: Seat) -> PrevisCharacter {
        var out = c
        let t = clamp((c.position.x - seat.centre.x) * seat.along.x + (c.position.z - seat.centre.z) * seat.along.z, -seat.reach, seat.reach)
        out.position = PlanPoint(x: r3(seat.centre.x + seat.along.x * t), z: r3(seat.centre.z + seat.along.z * t))
        let ahead = bearing(of: seat.front)
        if abs(wrap180(c.facing - ahead)) > seatTurn { out.facing = wrap360(ahead).rounded() }
        out.posture = .sitting
        out.seatHeight = seat.height
        return out
    }

    /// How far `p` is inside a piece grown by `r`, or 0 when it is clear.
    private static func overlap(_ o: PlanObject, _ p: PlanPoint, _ r: Double) -> Double {
        let q = local(o, p)
        let ox = abs(q.x) - o.width / 2, oz = abs(q.z) - o.depth / 2
        if ox <= 0 && oz <= 0 { return r - max(ox, oz) }
        let out = (max(0, ox) * max(0, ox) + max(0, oz) * max(0, oz)).squareRoot()
        return out < r - 1e-6 ? r - out : 0
    }

    /// Places to step to that clear piece `o`: straight out from its nearest point, and out past each side.
    private static func exits(_ o: PlanObject, _ p: PlanPoint, _ r: Double) -> [PlanPoint] {
        let q = local(o, p), hw = o.width / 2, hd = o.depth / 2, g = r + gap
        var out: [PlanPoint] = []
        let cx = clamp(q.x, -hw, hw), cz = clamp(q.z, -hd, hd), dx = q.x - cx, dz = q.z - cz
        let d = (dx * dx + dz * dz).squareRoot()
        if d > 1e-6 { out.append(PlanPoint(x: cx + dx / d * g, z: cz + dz / d * g)) }
        out += [PlanPoint(x: q.x, z: hd + g), PlanPoint(x: q.x, z: -hd - g), PlanPoint(x: hw + g, z: q.z), PlanPoint(x: -hw - g, z: q.z)]
        return out.map { world(o, $0) }
    }

    /// The nearest point to `p` where a body of radius `r` stands clear of every solid piece and on the floor.
    static func clearOfFurniture(_ p: PlanPoint, radius r: Double, plan: FloorPlan) -> PlanPoint {
        let solids = plan.objects.filter(isSolid)
        func hits(_ x: PlanPoint) -> Bool { solids.contains { overlap($0, x, r) > 1e-4 } }
        let hasRoom = !plan.walls.isEmpty || !plan.floorPolygons.isEmpty
        func onFloor(_ x: PlanPoint) -> Bool {
            !hasRoom || (Stage.insideRoom(x, plan: plan) && distToWalls(x, plan.walls) >= min(r, 0.1))
        }
        var at = p
        for _ in 0..<4 {
            guard let blocker = solids.first(where: { overlap($0, at, r) > 1e-4 }) else { return at }
            let from = at
            let options = exits(blocker, at, r).sorted { $0.distance(to: from) < $1.distance(to: from) }
            if let free = options.first(where: { onFloor($0) && !hits($0) }) { return PlanPoint(x: r3(free.x), z: r3(free.z)) }
            // Boxed in: step out of this piece and try the next one in the way.
            guard let next = options.first(where: onFloor) else { return p }
            at = next
        }
        return p
    }

    /// Settles one person against the plan's furniture after an edit. `before` is the same person
    /// before the edit (nil for a new one): it tells a sitting-down or standing-up from a move.
    static func settle(_ c: PrevisCharacter, plan: FloorPlan?, before: PrevisCharacter? = nil) -> PrevisCharacter {
        guard let plan else { return c }
        if c.posture == .sitting {
            let sittingDown = before.map { $0.posture != .sitting } ?? false
            if let s = seat(at: c.position, plan: plan, margin: sittingDown ? sitDownReach : seatReach) { return sit(c, on: s) }
        }
        var position = c.position
        if c.posture == .standing, let before, before.posture == .sitting, before.seatHeight != nil,
           let s = seat(at: before.position, plan: plan) {
            // Out past the front edge, level with where they sat.
            let t = clamp((before.position.x - s.centre.x) * s.along.x + (before.position.z - s.centre.z) * s.along.z, -s.reach, s.reach)
            let step = s.object.depth / 2 + bodyRadius(c) + 0.05
            position = PlanPoint(x: s.object.center.x + s.along.x * t + s.front.x * step,
                                 z: s.object.center.z + s.along.z * t + s.front.z * step)
        }
        var next = c
        next.position = clearOfFurniture(position, radius: bodyRadius(c), plan: plan)
        next.seatHeight = nil
        return next
    }

    private static func same(_ a: PrevisCharacter, _ b: PrevisCharacter) -> Bool {
        abs(a.position.x - b.position.x) < 0.005 && abs(a.position.z - b.position.z) < 0.005
            && abs(wrap180(a.facing - b.facing)) < 0.5 && a.posture == b.posture
            && abs((a.seatHeight ?? -1) - (b.seatHeight ?? -1)) < 0.005
    }

    /// Settles the people in `scanID` that an edit changed (or all of them when `all`).
    /// Returns nil when nothing moved, so callers can skip a write.
    static func settle(_ people: [PrevisCharacter], plan: FloorPlan?, scanID: UUID?,
                       before: [PrevisCharacter] = [], all: Bool = false) -> [PrevisCharacter]? {
        guard let plan else { return nil }
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        let out = people.map { c -> PrevisCharacter in
            if let scanID, let own = c.scanID, own != scanID { return c }
            let prev = old[c.id]
            if !all, prev == c { return c }
            let next = settle(c, plan: plan, before: prev)
            if same(next, c) { return c }
            changed = true
            return next
        }
        return changed ? out : nil
    }

    /// After set pieces move, turn or change size: people seated on a piece go with it, then
    /// everyone in the scan is settled again (a piece moved onto a standing person pushes them aside).
    static func carry(_ people: [PrevisCharacter], from oldPlan: FloorPlan, to plan: FloorPlan, scanID: UUID?) -> [PrevisCharacter]? {
        var anyCarried = false
        let moved = people.map { c -> PrevisCharacter in
            guard c.posture == .sitting, c.seatHeight != nil else { return c }
            if let scanID, let own = c.scanID, own != scanID { return c }
            guard let s = seat(at: c.position, plan: oldPlan),
                  let now = plan.objects.first(where: { $0.id == s.object.id }), now != s.object else { return c }
            let was = s.object
            let q = local(was, c.position)
            // Keep the same place on the piece, scaled to its new size.
            let p = world(now, PlanPoint(x: q.x * now.width / (was.width > 0 ? was.width : 1), z: q.z * now.depth / (was.depth > 0 ? was.depth : 1)))
            var out = c
            out.position = PlanPoint(x: r3(p.x), z: r3(p.z))
            out.facing = wrap360(c.facing + (now.rotation - was.rotation) * 180 / .pi).rounded()
            anyCarried = true
            return out
        }
        let settled = settle(moved, plan: plan, scanID: scanID, before: moved, all: true)
        return settled ?? (anyCarried ? moved : nil)
    }
}
