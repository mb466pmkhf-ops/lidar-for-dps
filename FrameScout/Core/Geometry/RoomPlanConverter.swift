import Foundation
import RoomPlan
import simd

extension simd_float4x4 {
    var position: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
    var xAxis: SIMD3<Float> { simd_normalize(SIMD3(columns.0.x, columns.0.y, columns.0.z)) }
    var yAxis: SIMD3<Float> { simd_normalize(SIMD3(columns.1.x, columns.1.y, columns.1.z)) }
    var zAxis: SIMD3<Float> { simd_normalize(SIMD3(columns.2.x, columns.2.y, columns.2.z)) }

    func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = self * SIMD4<Float>(p, 1)
        return SIMD3(r.x, r.y, r.z)
    }
}

/// Flattened RoomPlan elements from a single room, several rooms, or a merged structure.
struct RoomElements {
    var walls: [CapturedRoom.Surface] = []
    var doors: [CapturedRoom.Surface] = []
    var windows: [CapturedRoom.Surface] = []
    var openings: [CapturedRoom.Surface] = []
    var floors: [CapturedRoom.Surface] = []
    var objects: [CapturedRoom.Object] = []

    init(room: CapturedRoom) {
        walls = room.walls
        doors = room.doors
        windows = room.windows
        openings = room.openings
        floors = room.floors
        objects = room.objects
    }

    init(rooms: [CapturedRoom]) {
        for r in rooms {
            let e = RoomElements(room: r)
            walls += e.walls; doors += e.doors; windows += e.windows
            openings += e.openings; floors += e.floors; objects += e.objects
        }
    }

    init(structure: CapturedStructure) {
        walls = structure.walls
        doors = structure.doors
        windows = structure.windows
        openings = structure.openings
        floors = structure.floors
        objects = structure.objects
    }

    var floorY: Float {
        if let y = floors.map({ $0.transform.position.y }).min() { return y }
        if let y = walls.map({ $0.transform.position.y - $0.dimensions.y / 2 }).min() { return y }
        return 0
    }
}

enum RoomPlanConverter {
    // MARK: Plan

    static func floorPlan(_ e: RoomElements) -> FloorPlan {
        let floorY = e.floorY
        var plan = FloorPlan()
        plan.floorY = Double(floorY)

        func segment(_ s: CapturedRoom.Surface, kind: PlanSegmentKind) -> PlanSegment {
            let hx = s.dimensions.x / 2
            let a = s.transform.apply(SIMD3(-hx, 0, 0))
            let b = s.transform.apply(SIMD3(hx, 0, 0))
            var isOpen = false
            if case .door(let open) = s.category { isOpen = open }
            return PlanSegment(id: s.identifier, kind: kind,
                               a: PlanPoint(x: Double(a.x), z: Double(a.z)),
                               b: PlanPoint(x: Double(b.x), z: Double(b.z)),
                               height: Double(s.dimensions.y),
                               bottom: Double(s.transform.position.y - s.dimensions.y / 2 - floorY),
                               isOpen: isOpen)
        }

        plan.walls = e.walls.map { segment($0, kind: .wall) }
        plan.doors = e.doors.map { segment($0, kind: .door) }
        plan.windows = e.windows.map { segment($0, kind: .window) }
        plan.openings = e.openings.map { segment($0, kind: .opening) }
        plan.floorPolygons = e.floors.map { floorOutline($0).map { PlanPoint(x: Double($0.x), z: Double($0.z)) } }
        plan.objects = e.objects.map { o in
            let x = o.transform.xAxis
            return PlanObject(id: o.identifier, category: categoryName(o.category),
                              center: PlanPoint(x: Double(o.transform.position.x), z: Double(o.transform.position.z)),
                              width: Double(o.dimensions.x), depth: Double(o.dimensions.z),
                              height: Double(o.dimensions.y), rotation: Double(atan2(x.z, x.x)))
        }

        var pts = plan.walls.flatMap { [$0.a, $0.b] } + plan.floorPolygons.flatMap { $0 }
        pts += plan.objects.map(\.center)
        if var bounds = PlanRect.enclosing(pts) {
            bounds = bounds.union(PlanRect(minX: bounds.center.x - 1, minZ: bounds.center.z - 1,
                                           maxX: bounds.center.x + 1, maxZ: bounds.center.z + 1))
            plan.bounds = bounds
        }
        return plan
    }

    static func floorOutline(_ s: CapturedRoom.Surface) -> [SIMD3<Float>] {
        if !s.polygonCorners.isEmpty {
            return s.polygonCorners.map { s.transform.apply($0) }
        }
        let hx = s.dimensions.x / 2, hy = s.dimensions.y / 2
        return [SIMD3(-hx, -hy, 0), SIMD3(hx, -hy, 0), SIMD3(hx, hy, 0), SIMD3(-hx, hy, 0)]
            .map { s.transform.apply($0) }
    }

    static func categoryName(_ c: CapturedRoom.Object.Category) -> String {
        let raw = String(describing: c)
        // "washerDryer" → "Washer Dryer"
        var out = ""
        for ch in raw {
            if ch.isUppercase && !out.isEmpty { out.append(" ") }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: Stats

    static func stats(_ e: RoomElements, plan: FloorPlan) -> ScanStats {
        var s = ScanStats()
        s.wallCount = e.walls.count
        s.doorCount = e.doors.count
        s.windowCount = e.windows.count
        s.openingCount = e.openings.count
        s.floorCount = e.floors.count
        s.objectCount = e.objects.count
        for o in plan.objects { s.objectCategories[o.category, default: 0] += 1 }

        let fullWalls = e.walls.filter { $0.dimensions.x > 0.5 }
        if let maxH = fullWalls.map({ Double($0.dimensions.y) }).max() {
            s.ceilingHeight = maxH
            s.minCeilingHeight = fullWalls.map { Double($0.dimensions.y) }.min()
        }

        let (w, l) = alignedExtents(plan.walls.isEmpty ? [] : plan.walls.map { ($0.a, $0.b) })
        s.width = w
        s.length = l

        let polygonArea = plan.floorPolygons.reduce(0.0) { $0 + shoelace($1) }
        if polygonArea > 0.1 {
            s.floorArea = polygonArea
        } else if let w, let l {
            s.floorArea = w * l
            s.floorAreaIsEstimate = true
        }

        s.doors = plan.doors.map { OpeningSize(width: $0.length, height: $0.height, sillHeight: max(0, $0.bottom)) }
        s.windows = plan.windows.map { OpeningSize(width: $0.length, height: $0.height, sillHeight: max(0, $0.bottom)) }
        s.completeness = completeness(e, plan: plan)
        return s
    }

    /// Room width/length measured along the dominant wall direction (not world axes).
    static func alignedExtents(_ segments: [(PlanPoint, PlanPoint)]) -> (Double?, Double?) {
        guard !segments.isEmpty else { return (nil, nil) }
        var c = 0.0, s = 0.0
        for (a, b) in segments {
            let len = a.distance(to: b)
            let angle = atan2(b.z - a.z, b.x - a.x)
            c += len * cos(4 * angle)
            s += len * sin(4 * angle)
        }
        let theta = atan2(s, c) / 4
        let ct = cos(-theta), st = sin(-theta)
        var minU = Double.infinity, maxU = -Double.infinity, minV = Double.infinity, maxV = -Double.infinity
        for (a, b) in segments {
            for p in [a, b] {
                let u = p.x * ct - p.z * st
                let v = p.x * st + p.z * ct
                minU = min(minU, u); maxU = max(maxU, u)
                minV = min(minV, v); maxV = max(maxV, v)
            }
        }
        let d1 = maxU - minU, d2 = maxV - minV
        return (min(d1, d2), max(d1, d2))
    }

    static func shoelace(_ poly: [PlanPoint]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            sum += a.x * b.z - b.x * a.z
        }
        return abs(sum) / 2
    }

    /// Heuristic, clearly labelled "estimated" in the UI: RoomPlan does not report coverage.
    /// Combines wall-loop closure, detection confidence and whether a floor was found.
    static func completeness(_ e: RoomElements, plan: FloorPlan) -> Double {
        guard !plan.walls.isEmpty else { return 0 }
        let endpoints = plan.walls.flatMap { [$0.a, $0.b] }
        var joined = 0
        for (i, p) in endpoints.enumerated() {
            let partner = i % 2 == 0 ? i + 1 : i - 1
            if endpoints.enumerated().contains(where: { $0.offset != i && $0.offset != partner && $0.element.distance(to: p) < 0.35 }) {
                joined += 1
            }
        }
        let closure = Double(joined) / Double(endpoints.count)
        let confidence = e.walls.map { w -> Double in
            switch w.confidence {
            case .high: return 1
            case .medium: return 0.65
            case .low: return 0.3
            @unknown default: return 0.5
            }
        }.reduce(0, +) / Double(e.walls.count)
        let floor = e.floors.isEmpty ? 0.0 : 1.0
        return min(1, 0.5 * closure + 0.35 * confidence + 0.15 * floor)
    }

    // MARK: 3D geometry for export / previews

    struct GeometryOptions {
        var wallThickness: Float = 0.10
        var includeCeiling: Bool = false
        var includeObjects: Bool = true
    }

    static func sceneGeometry(_ e: RoomElements, options: GeometryOptions = .init()) -> SceneGeometry {
        let root = SceneNode(name: "FrameScout_Location")
        let wallsNode = root.addChild(SceneNode(name: "Walls"))
        let doorsNode = root.addChild(SceneNode(name: "Doors"))
        let windowsNode = root.addChild(SceneNode(name: "Windows"))
        let floorsNode = root.addChild(SceneNode(name: "Floors"))
        let objectsNode = root.addChild(SceneNode(name: "Furniture"))

        let apertures = e.doors + e.windows + e.openings

        for (i, wall) in e.walls.enumerated() {
            let t = wall.transform
            let w = wall.dimensions.x, h = wall.dimensions.y
            let inverse = t.inverse
            var holes: [WallBuilder.Rect] = []
            for ap in apertures {
                let local = inverse.apply(ap.transform.position)
                guard abs(local.z) < 0.3,
                      abs(local.x) < w / 2 + 0.05,
                      abs(local.y) < h / 2 + 0.05,
                      abs(simd_dot(ap.transform.xAxis, t.xAxis)) > 0.9 else { continue }
                let hx = ap.dimensions.x / 2, hy = ap.dimensions.y / 2
                holes.append(WallBuilder.Rect(u0: local.x - hx, u1: local.x + hx, v0: local.y - hy, v1: local.y + hy))
            }
            var mesh = SceneMesh(material: .wall)
            for piece in WallBuilder.solidPieces(width: w, height: h, holes: holes) {
                let centre = t.apply(SIMD3((piece.u0 + piece.u1) / 2, (piece.v0 + piece.v1) / 2, 0))
                mesh.append(.box(center: centre, axes: (t.xAxis, t.yAxis, t.zAxis),
                                 size: Vec3(piece.width, piece.height, options.wallThickness), material: .wall))
            }
            let node = SceneNode(name: String(format: "Wall_%02d", i + 1), mesh: mesh)
            node.info = ["category": "wall", "width_m": fmt(w), "height_m": fmt(h)]
            node.recentreOnMesh()
            wallsNode.addChild(node)
        }

        for (i, door) in e.doors.enumerated() {
            var isOpen = false
            if case .door(let open) = door.category { isOpen = open }
            let t = door.transform
            // Door leaf sits inside the aperture; open doors are exported as an empty frame marker.
            let mesh = SceneMesh.box(center: t.position, axes: (t.xAxis, t.yAxis, t.zAxis),
                                     size: Vec3(door.dimensions.x, door.dimensions.y, isOpen ? 0.005 : 0.04),
                                     material: isOpen ? .opening : .door)
            let node = SceneNode(name: String(format: "Door_%02d", i + 1), mesh: mesh)
            node.info = ["category": "door", "open": isOpen ? "true" : "false",
                         "width_m": fmt(door.dimensions.x), "height_m": fmt(door.dimensions.y)]
            node.recentreOnMesh()
            doorsNode.addChild(node)
        }

        for (i, window) in e.windows.enumerated() {
            let t = window.transform
            let mesh = SceneMesh.box(center: t.position, axes: (t.xAxis, t.yAxis, t.zAxis),
                                     size: Vec3(window.dimensions.x, window.dimensions.y, 0.02), material: .window)
            let node = SceneNode(name: String(format: "Window_%02d", i + 1), mesh: mesh)
            node.info = ["category": "window", "width_m": fmt(window.dimensions.x), "height_m": fmt(window.dimensions.y),
                         "sill_m": fmt(t.position.y - window.dimensions.y / 2 - e.floorY)]
            node.recentreOnMesh()
            windowsNode.addChild(node)
        }

        let ceilingHeight: Float = e.walls.map { $0.dimensions.y }.max() ?? 0
        for (i, floor) in e.floors.enumerated() {
            let outline = floorOutline(floor).map { (x: $0.x, z: $0.z) }
            let y = floor.transform.position.y
            var mesh = SceneMesh.horizontalPolygon(outline, y: y, facingUp: true, material: .floor)
            mesh.append(.horizontalPolygon(outline, y: y - 0.02, facingUp: false, material: .floor))
            let node = SceneNode(name: String(format: "Floor_%02d", i + 1), mesh: mesh)
            node.info = ["category": "floor"]
            floorsNode.addChild(node)
        }

        if options.includeCeiling, ceilingHeight > 0 {
            let ceilingNode = root.addChild(SceneNode(name: "Ceiling_Estimated"))
            for (i, floor) in e.floors.enumerated() {
                let outline = floorOutline(floor).map { (x: $0.x, z: $0.z) }
                let mesh = SceneMesh.horizontalPolygon(outline, y: e.floorY + ceilingHeight, facingUp: false, material: .ceiling)
                let node = SceneNode(name: String(format: "Ceiling_%02d", i + 1), mesh: mesh)
                node.info = ["category": "ceiling", "note": "Estimated from wall height; RoomPlan does not detect ceilings"]
                ceilingNode.addChild(node)
            }
        }

        if options.includeObjects {
            var counters: [String: Int] = [:]
            for object in e.objects {
                let name = categoryName(object.category).replacingOccurrences(of: " ", with: "")
                counters[name, default: 0] += 1
                let t = object.transform
                let mesh = SceneMesh.box(center: .zero, axes: (t.xAxis, t.yAxis, t.zAxis),
                                         size: object.dimensions, material: .object)
                let index = counters[name] ?? 1
                let node = SceneNode(name: "\(name)_\(String(format: "%02d", index))", mesh: mesh,
                                     translation: t.position)
                node.info = ["category": name.lowercased(),
                             "size_m": "\(fmt(object.dimensions.x)) x \(fmt(object.dimensions.y)) x \(fmt(object.dimensions.z))"]
                objectsNode.addChild(node)
            }
        }

        let pruned = root.pruned() ?? SceneNode(name: "FrameScout_Location")
        return SceneGeometry(root: pruned, metadata: ["source": "Apple RoomPlan (parametric)"])
    }

    private static func fmt(_ v: Float) -> String { String(format: "%.3f", v) }
}
