import Foundation

/// A door, window or opening to put in a wall: width along the wall, height of the hole and the
/// sill above the floor (m).
struct OpeningPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let kind: PlanSegmentKind
    let width: Double
    let height: Double
    let sill: Double
}

/// A piece of furniture at a typical size. `category` is what the 3D views draw it as (RoomPlan's names).
struct FurniturePreset: Identifiable, Hashable {
    let id: String
    let label: String
    let category: String
    let width: Double
    let depth: Double
    let height: Double
}

/// Adding and changing the set by hand: doors, windows and openings that sit in a wall, and
/// furniture that stands on the floor. Mirrors `web/src/model/setPieces.ts`; keep the sizes and the
/// snapping rules identical (tests on both sides check the same cases).
///
/// Every size here is a typical one picked from a list or typed in, never a measurement, so
/// everything placed or changed here carries `byHand = true` and the panels say so.
enum SetPieces {
    static let openings: [OpeningPreset] = [
        OpeningPreset(id: "door", label: "Door", kind: .door, width: 0.9, height: 2.05, sill: 0),
        OpeningPreset(id: "double-door", label: "Double door", kind: .door, width: 1.6, height: 2.1, sill: 0),
        OpeningPreset(id: "window", label: "Window", kind: .window, width: 1.2, height: 1.4, sill: 0.85),
        OpeningPreset(id: "tall-window", label: "Tall window", kind: .window, width: 1.4, height: 2.2, sill: 0.1),
        OpeningPreset(id: "opening", label: "Opening", kind: .opening, width: 1.0, height: 2.1, sill: 0),
    ]

    static let furniture: [FurniturePreset] = [
        FurniturePreset(id: "sofa", label: "Sofa", category: "Sofa", width: 2.0, depth: 0.9, height: 0.85),
        FurniturePreset(id: "armchair", label: "Armchair", category: "Chair", width: 0.85, depth: 0.85, height: 0.9),
        FurniturePreset(id: "chair", label: "Chair", category: "Chair", width: 0.48, depth: 0.5, height: 0.9),
        FurniturePreset(id: "dining-table", label: "Dining table", category: "Table", width: 1.6, depth: 0.9, height: 0.75),
        FurniturePreset(id: "coffee-table", label: "Coffee table", category: "Table", width: 1.1, depth: 0.6, height: 0.45),
        FurniturePreset(id: "desk", label: "Desk", category: "Desk", width: 1.4, depth: 0.7, height: 0.75),
        FurniturePreset(id: "bed", label: "Double bed", category: "Bed", width: 2.0, depth: 1.5, height: 0.55),
        FurniturePreset(id: "wardrobe", label: "Wardrobe", category: "Storage", width: 1.2, depth: 0.6, height: 2.0),
        FurniturePreset(id: "sideboard", label: "Sideboard", category: "Storage", width: 1.6, depth: 0.45, height: 0.8),
        FurniturePreset(id: "shelves", label: "Shelves", category: "Shelf", width: 0.9, depth: 0.35, height: 1.8),
        FurniturePreset(id: "fridge", label: "Fridge", category: "Refrigerator", width: 0.6, depth: 0.65, height: 1.8),
        FurniturePreset(id: "cooker", label: "Cooker", category: "Stove", width: 0.6, depth: 0.6, height: 0.9),
        FurniturePreset(id: "sink", label: "Sink unit", category: "Sink", width: 0.8, depth: 0.6, height: 0.9),
        FurniturePreset(id: "bath", label: "Bath", category: "Bathtub", width: 1.7, depth: 0.75, height: 0.55),
        FurniturePreset(id: "toilet", label: "Toilet", category: "Toilet", width: 0.4, depth: 0.65, height: 0.8),
        FurniturePreset(id: "fireplace", label: "Fireplace", category: "Fireplace", width: 1.4, depth: 0.4, height: 1.1),
        FurniturePreset(id: "box", label: "Box", category: "Box", width: 0.6, depth: 0.6, height: 0.6),
    ]

    static func opening(_ id: String) -> OpeningPreset? { openings.first { $0.id == id } }
    static func furniturePreset(_ id: String) -> FurniturePreset? { furniture.first { $0.id == id } }

    /// How far from a wall a tap may be and still put a door or window in it (m).
    static let wallReach = 1.0
    /// Furniture dropped this close to a wall (beyond its own half depth) turns and backs onto it.
    static let furnitureWallSnap = 0.5
    static let minOpening = 0.3
    static let sizeRange: ClosedRange<Double> = 0.1...12
    static let heightMax = 6.0

    private static func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
    /// Angles keep more places, so four quarter turns come back to where they started.
    private static func r6(_ v: Double) -> Double { (v * 1e6).rounded() / 1e6 }
    private static func P(_ x: Double, _ z: Double) -> PlanPoint { PlanPoint(x: r3(x), z: r3(z)) }
    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    struct WallHit {
        var wall: PlanSegment
        var t: Double
        var point: PlanPoint
        var distance: Double
    }

    /// The wall closest to `p`, with the closest point on it (t from a to b).
    static func nearestWall(_ plan: FloorPlan?, to p: PlanPoint) -> WallHit? {
        var best: WallHit?
        for wall in plan?.walls ?? [] {
            let dx = wall.b.x - wall.a.x, dz = wall.b.z - wall.a.z, l2 = dx * dx + dz * dz
            guard l2 >= 1e-6 else { continue }
            let t = clamp(((p.x - wall.a.x) * dx + (p.z - wall.a.z) * dz) / l2, 0, 1)
            let point = PlanPoint(x: wall.a.x + dx * t, z: wall.a.z + dz * t)
            let d = point.distance(to: p)
            if best == nil || d < best!.distance { best = WallHit(wall: wall, t: t, point: point, distance: d) }
        }
        return best
    }

    /// A segment `width` wide centred on the wall at `centre`, kept inside the wall's ends.
    private static func onWall(_ wall: PlanSegment, centre: PlanPoint, width: Double) -> (a: PlanPoint, b: PlanPoint) {
        let L = wall.length
        let lo = min(minOpening, L)
        let w = clamp(width, lo, max(lo, L - 0.1))
        let ux = (wall.b.x - wall.a.x) / L, uz = (wall.b.z - wall.a.z) / L
        let along = clamp((centre.x - wall.a.x) * ux + (centre.z - wall.a.z) * uz, w / 2, L - w / 2)
        return (P(wall.a.x + ux * (along - w / 2), wall.a.z + uz * (along - w / 2)),
                P(wall.a.x + ux * (along + w / 2), wall.a.z + uz * (along + w / 2)))
    }

    /// Keeps the hole inside the wall's height: the sill first, then the height.
    private static func fitHeight(_ wall: PlanSegment, height: Double, sill: Double) -> (height: Double, bottom: Double) {
        let top = wall.bottom + wall.height - 0.05
        let bottom = r3(clamp(sill, 0, max(0, top - 0.3)))
        return (r3(clamp(height, 0.3, max(0.3, top - bottom))), bottom)
    }

    /// A door, window or opening in the wall nearest `p`, or nil when no wall is within reach.
    static func placeOpening(_ plan: FloorPlan?, at p: PlanPoint, preset: OpeningPreset, reach: Double = wallReach) -> PlanSegment? {
        guard let hit = nearestWall(plan, to: p), hit.distance <= reach else { return nil }
        let ends = onWall(hit.wall, centre: hit.point, width: preset.width)
        let size = fitHeight(hit.wall, height: preset.height, sill: preset.sill)
        return PlanSegment(kind: preset.kind, a: ends.a, b: ends.b, height: size.height, bottom: size.bottom, isOpen: false, byHand: true)
    }

    /// Slides an opening to the point on the nearest wall under `p` (it can change walls). Same size.
    static func slide(_ seg: PlanSegment, to p: PlanPoint, in plan: FloorPlan) -> PlanSegment {
        guard let hit = nearestWall(plan, to: p) else { return seg }
        var s = seg
        let ends = onWall(hit.wall, centre: hit.point, width: seg.length)
        let size = fitHeight(hit.wall, height: seg.height, sill: seg.bottom)
        s.a = ends.a; s.b = ends.b; s.height = size.height; s.bottom = size.bottom; s.byHand = true
        return s
    }

    /// New width, same centre, on the same wall.
    static func resize(_ seg: PlanSegment, width: Double, in plan: FloorPlan) -> PlanSegment {
        guard let hit = nearestWall(plan, to: seg.midpoint) else { return seg }
        var s = seg
        let ends = onWall(hit.wall, centre: seg.midpoint, width: width)
        s.a = ends.a; s.b = ends.b; s.byHand = true
        return s
    }

    /// Height and sill, kept inside the wall.
    static func setHeight(_ seg: PlanSegment, height: Double, sill: Double, in plan: FloorPlan) -> PlanSegment {
        var s = seg
        if let hit = nearestWall(plan, to: seg.midpoint) {
            let size = fitHeight(hit.wall, height: height, sill: sill)
            s.height = size.height; s.bottom = size.bottom
        } else {
            s.height = r3(max(0.3, height)); s.bottom = r3(max(0, sill))
        }
        s.byHand = true
        return s
    }

    /// Rotation (radians, plan screen space) and centre that put the box's back flat against the wall.
    static func backOntoWall(_ plan: FloorPlan?, center: PlanPoint, depth: Double,
                             snap: Double = furnitureWallSnap) -> (center: PlanPoint, rotation: Double)? {
        guard let plan, let hit = nearestWall(plan, to: center),
              hit.distance <= depth / 2 + snap, hit.t > 0, hit.t < 1 else { return nil }
        let wall = hit.wall, L = wall.length
        let ux = (wall.b.x - wall.a.x) / L, uz = (wall.b.z - wall.a.z) / L
        // Normal pointing into the room (towards the floor's middle).
        var nx = -uz, nz = ux
        let c = plan.interiorCentroid
        if (c.x - hit.point.x) * nx + (c.z - hit.point.z) * nz < 0 { nx = -nx; nz = -nz }
        let off = depth / 2 + 0.02
        return (P(hit.point.x + nx * off, hit.point.z + nz * off), r6(atan2(uz, ux)))
    }

    /// A piece of furniture at `p`; near a wall it turns to back onto it.
    static func placeFurniture(_ plan: FloorPlan?, at p: PlanPoint, preset: FurniturePreset) -> PlanObject {
        let snapped = backOntoWall(plan, center: p, depth: preset.depth)
        return PlanObject(category: preset.category, center: snapped?.center ?? P(p.x, p.z),
                          width: preset.width, depth: preset.depth, height: preset.height,
                          rotation: snapped?.rotation ?? 0, byHand: true)
    }

    /// Turns a piece about its centre, keeping rotation in (−π, π].
    static func turned(_ o: PlanObject, by radians: Double) -> PlanObject {
        var r = o.rotation + radians
        while r > .pi { r -= 2 * .pi }
        while r <= -.pi { r += 2 * .pi }
        var out = o
        out.rotation = r6(r)
        out.byHand = true
        return out
    }

    static func clampSize(_ v: Double, max upper: Double = sizeRange.upperBound) -> Double {
        r3(clamp(v.isFinite ? v : sizeRange.lowerBound, sizeRange.lowerBound, upper))
    }

    /// A display name for a set piece: the preset it matches, else its category.
    static func name(of o: PlanObject) -> String {
        furniture.first { $0.category == o.category && abs($0.width - o.width) < 1e-6 && abs($0.depth - o.depth) < 1e-6 }?.label ?? o.category
    }

    static func label(of kind: PlanSegmentKind) -> String {
        switch kind {
        case .door: return "Door"
        case .window: return "Window"
        case .opening: return "Opening"
        case .wall: return "Wall"
        }
    }
}

// MARK: Editing a plan

extension FloorPlan {
    /// A door, window or opening by id.
    func segment(_ id: UUID) -> PlanSegment? {
        (doors + windows + openings).first { $0.id == id }
    }

    mutating func add(_ seg: PlanSegment) {
        switch seg.kind {
        case .door: doors.append(seg)
        case .window: windows.append(seg)
        case .opening: openings.append(seg)
        case .wall: walls.append(seg)
        }
    }

    /// Replaces a door, window or opening; a changed kind moves it to the matching list.
    mutating func replace(_ seg: PlanSegment) {
        if let old = segment(seg.id), old.kind == seg.kind {
            switch seg.kind {
            case .door: if let i = doors.firstIndex(where: { $0.id == seg.id }) { doors[i] = seg }
            case .window: if let i = windows.firstIndex(where: { $0.id == seg.id }) { windows[i] = seg }
            case .opening: if let i = openings.firstIndex(where: { $0.id == seg.id }) { openings[i] = seg }
            case .wall: if let i = walls.firstIndex(where: { $0.id == seg.id }) { walls[i] = seg }
            }
            return
        }
        removeSegment(seg.id)
        add(seg)
    }

    mutating func removeSegment(_ id: UUID) {
        doors.removeAll { $0.id == id }
        windows.removeAll { $0.id == id }
        openings.removeAll { $0.id == id }
    }

    mutating func replace(_ object: PlanObject) {
        if let i = objects.firstIndex(where: { $0.id == object.id }) { objects[i] = object }
    }

    mutating func removeObject(_ id: UUID) {
        objects.removeAll { $0.id == id }
    }
}
