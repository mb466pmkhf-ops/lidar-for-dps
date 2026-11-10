import Foundation

/// Builds simple 3D geometry from a floor plan: walls extruded with real window and door holes,
/// window panes, closed door leaves, floors and set pieces as boxes. Used when a scan's own
/// geometry files aren't available (and for the sample project), so the 3D lighting view still
/// shows the room in the same coordinates as the plan.
enum PlanSceneBuilder {
    static func sceneGeometry(_ plan: FloorPlan, wallThickness: Float = 0.1) -> SceneGeometry {
        let root = SceneNode(name: "FrameScout_Location")
        let wallsNode = root.addChild(SceneNode(name: "Walls"))
        let doorsNode = root.addChild(SceneNode(name: "Doors"))
        let windowsNode = root.addChild(SceneNode(name: "Windows"))
        let floorsNode = root.addChild(SceneNode(name: "Floors"))
        let objectsNode = root.addChild(SceneNode(name: "Furniture"))
        let floorY = Float(plan.floorY)
        let up = Vec3(0, 1, 0)

        func axes(_ a: PlanPoint, _ b: PlanPoint) -> (Vec3, Vec3, Vec3)? {
            let dx = Float(b.x - a.x), dz = Float(b.z - a.z)
            let len = (dx * dx + dz * dz).squareRoot()
            guard len > 0.01 else { return nil }
            let ux = Vec3(dx / len, 0, dz / len)
            return (ux, up, V3.cross(ux, up))
        }

        let apertures = plan.windows + plan.doors + plan.openings
        for (i, wall) in plan.walls.enumerated() {
            guard let frame = axes(wall.a, wall.b) else { continue }
            let (ux, uy, uz) = frame
            let w = Float(wall.length), h = Float(wall.height)
            let mid = wall.midpoint
            let centre = Vec3(Float(mid.x), floorY + Float(wall.bottom) + h / 2, Float(mid.z))
            var holes: [WallBuilder.Rect] = []
            for ap in apertures where LightingCalculator.distance(ap.midpoint, toSegment: wall.a, wall.b) < 0.2 {
                // Aperture extent along the wall, in the wall's centred coordinates.
                func along(_ p: PlanPoint) -> Float {
                    Float((p.x - mid.x)) * ux.x + Float((p.z - mid.z)) * ux.z
                }
                let u0 = min(along(ap.a), along(ap.b)), u1 = max(along(ap.a), along(ap.b))
                let v0 = Float(ap.bottom - wall.bottom) - h / 2
                holes.append(WallBuilder.Rect(u0: u0, u1: u1, v0: v0, v1: v0 + Float(ap.height)))
            }
            var mesh = SceneMesh(material: .wall)
            for piece in WallBuilder.solidPieces(width: w, height: h, holes: holes) {
                let c = centre + ux * ((piece.u0 + piece.u1) / 2) + uy * ((piece.v0 + piece.v1) / 2)
                mesh.append(.box(center: c, axes: (ux, uy, uz), size: Vec3(piece.width, piece.height, wallThickness), material: .wall))
            }
            let node = SceneNode(name: String(format: "Wall_%02d", i + 1), mesh: mesh)
            node.info = ["category": "wall", "id": wall.id.uuidString]
            node.recentreOnMesh()
            wallsNode.addChild(node)
        }

        for (i, window) in plan.windows.enumerated() {
            guard let frame = axes(window.a, window.b) else { continue }
            let (ux, uy, uz) = frame
            let m = window.midpoint
            let c = Vec3(Float(m.x), floorY + Float(window.bottom + window.height / 2), Float(m.z))
            let mesh = SceneMesh.box(center: c, axes: (ux, uy, uz), size: Vec3(Float(window.length), Float(window.height), 0.02), material: .window)
            let node = SceneNode(name: String(format: "Window_%02d", i + 1), mesh: mesh)
            node.info = ["category": "window", "id": window.id.uuidString]
            node.recentreOnMesh()
            windowsNode.addChild(node)
        }

        for (i, door) in plan.doors.enumerated() where !door.isOpen {
            guard let frame = axes(door.a, door.b) else { continue }
            let (ux, uy, uz) = frame
            let m = door.midpoint
            let c = Vec3(Float(m.x), floorY + Float(door.bottom + door.height / 2), Float(m.z))
            let mesh = SceneMesh.box(center: c, axes: (ux, uy, uz), size: Vec3(Float(door.length), Float(door.height), 0.04), material: .door)
            let node = SceneNode(name: String(format: "Door_%02d", i + 1), mesh: mesh)
            node.info = ["category": "door", "id": door.id.uuidString]
            node.recentreOnMesh()
            doorsNode.addChild(node)
        }

        for (i, poly) in plan.floorPolygons.enumerated() where poly.count >= 3 {
            let outline = poly.map { (x: Float($0.x), z: Float($0.z)) }
            var mesh = SceneMesh.horizontalPolygon(outline, y: floorY, facingUp: true, material: .floor)
            mesh.append(.horizontalPolygon(outline, y: floorY - 0.02, facingUp: false, material: .floor))
            let node = SceneNode(name: String(format: "Floor_%02d", i + 1), mesh: mesh)
            node.info = ["category": "floor"]
            floorsNode.addChild(node)
        }

        var counters: [String: Int] = [:]
        for object in plan.objects {
            let name = object.category.replacingOccurrences(of: " ", with: "")
            counters[name, default: 0] += 1
            // Plan rotation is screen-space (x right, z down) about +Y; build the box in local axes.
            let r = Float(object.rotation)
            let ux = Vec3(cos(r), 0, sin(r))
            let uz = V3.cross(ux, up)
            let size = Vec3(Float(object.width), Float(object.height), Float(object.depth))
            let mesh = SceneMesh.box(center: .zero, axes: (ux, up, uz), size: size, material: .object)
            let node = SceneNode(name: "\(name)_\(String(format: "%02d", counters[name] ?? 1))", mesh: mesh,
                                 translation: Vec3(Float(object.center.x), floorY + Float(object.height) / 2, Float(object.center.z)))
            node.info = ["category": object.category.lowercased(), "id": object.id.uuidString]
            objectsNode.addChild(node)
        }

        let pruned = root.pruned() ?? SceneNode(name: "FrameScout_Location")
        return SceneGeometry(root: pruned, metadata: ["source": "Built from the floor plan"])
    }
}

extension SceneGeometry {
    /// Area-weighted normal and median height of the floor, from nodes tagged as floor
    /// (RoomPlan floors, or LiDAR mesh triangles classified as floor). Used to level a scan.
    func floorEstimate() -> (normal: (x: Double, y: Double, z: Double), height: Double)? {
        var n = Vec3(0, 0, 0)
        var heights: [Float] = []
        root.walk { node, offset, _ in
            let category = (node.info["category"] ?? node.name).lowercased()
            guard category.hasPrefix("floor"), let mesh = node.mesh else { return }
            for t in 0..<mesh.triangleCount {
                let p0 = mesh.positions[Int(mesh.indices[t * 3])] + offset
                let p1 = mesh.positions[Int(mesh.indices[t * 3 + 1])] + offset
                let p2 = mesh.positions[Int(mesh.indices[t * 3 + 2])] + offset
                var c = V3.cross(p1 - p0, p2 - p0)       // length = 2 × area
                if c.y < 0 { c = -c }                     // undersides count the same way up
                n += c
                if heights.count < 50_000 { heights.append((p0.y + p1.y + p2.y) / 3) }
            }
        }
        guard V3.length(n) > 1e-6, !heights.isEmpty else { return nil }
        heights.sort()
        let unit = V3.normalized(n)
        return ((Double(unit.x), Double(unit.y), Double(unit.z)), Double(heights[heights.count / 2]))
    }
}
