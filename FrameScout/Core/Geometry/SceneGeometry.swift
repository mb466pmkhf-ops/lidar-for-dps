import Foundation

/// Format-neutral scene description that every exporter (USDA/USDZ, OBJ, GLB) and the
/// SceneKit previews consume. Units: metres. Axes: ARKit world (right-handed, +Y up, -Z forward).
typealias Vec3 = SIMD3<Float>

/// Small vector helpers (named to avoid clashing with the `simd` module's free functions).
enum V3 {
    static func dot(_ a: Vec3, _ b: Vec3) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }

    static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
        Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ a: Vec3) -> Float { dot(a, a).squareRoot() }

    static func normalized(_ a: Vec3) -> Vec3 {
        let l = length(a)
        return l > 1e-9 ? a / l : Vec3(0, 1, 0)
    }
}

struct SceneMaterial: Hashable {
    var name: String
    /// Linear RGBA, 0...1.
    var color: SIMD4<Float>
    var roughness: Float = 0.85
    var metallic: Float = 0

    var isTranslucent: Bool { color.w < 0.999 }

    static let wall = SceneMaterial(name: "Wall", color: SIMD4(0.82, 0.82, 0.80, 1))
    static let floor = SceneMaterial(name: "Floor", color: SIMD4(0.45, 0.42, 0.38, 1))
    static let ceiling = SceneMaterial(name: "Ceiling", color: SIMD4(0.90, 0.90, 0.90, 1))
    static let door = SceneMaterial(name: "Door", color: SIMD4(0.42, 0.28, 0.16, 1))
    static let window = SceneMaterial(name: "Window", color: SIMD4(0.55, 0.75, 0.95, 0.35), roughness: 0.1)
    static let opening = SceneMaterial(name: "Opening", color: SIMD4(0.30, 0.30, 0.30, 0.25))
    static let object = SceneMaterial(name: "Furniture", color: SIMD4(0.55, 0.55, 0.60, 1))
    static let mesh = SceneMaterial(name: "ScanMesh", color: SIMD4(0.70, 0.70, 0.70, 1))
}

struct SceneMesh {
    var positions: [Vec3] = []
    var normals: [Vec3] = []
    var indices: [UInt32] = []
    var material: SceneMaterial

    var triangleCount: Int { indices.count / 3 }
    var isEmpty: Bool { indices.isEmpty }

    func bounds() -> (min: Vec3, max: Vec3)? {
        guard var lo = positions.first else { return nil }
        var hi = lo
        for p in positions {
            lo = Vec3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Vec3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }

    mutating func append(_ other: SceneMesh) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        indices += other.indices.map { $0 + base }
    }

    // MARK: Primitive builders

    /// Oriented box. `axes` are unit vectors (right-handed); `size` is full extent along each axis.
    static func box(center: Vec3, axes: (Vec3, Vec3, Vec3), size: Vec3, material: SceneMaterial) -> SceneMesh {
        var mesh = SceneMesh(material: material)
        let (ux, uy, uz) = axes
        let h = size / 2
        // (normal, a, b, half-normal, half-a, half-b) with a × b = normal so faces wind CCW.
        let faces: [(Vec3, Vec3, Vec3, Float, Float, Float)] = [
            (ux, uy, uz, h.x, h.y, h.z),
            (-ux, uz, uy, h.x, h.z, h.y),
            (uy, uz, ux, h.y, h.z, h.x),
            (-uy, ux, uz, h.y, h.x, h.z),
            (uz, ux, uy, h.z, h.x, h.y),
            (-uz, uy, ux, h.z, h.y, h.x),
        ]
        for (n, a, b, hn, ha, hb) in faces {
            let c: Vec3 = center + n * hn
            let da: Vec3 = a * ha
            let db: Vec3 = b * hb
            let base = UInt32(mesh.positions.count)
            let p0: Vec3 = c - da - db
            let p1: Vec3 = c + da - db
            let p2: Vec3 = c + da + db
            let p3: Vec3 = c - da + db
            mesh.positions += [p0, p1, p2, p3]
            mesh.normals += [n, n, n, n]
            mesh.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return mesh
    }

    /// Flat horizontal polygon at height `y`, facing up (or down when `facingUp` is false).
    static func horizontalPolygon(_ outline: [(x: Float, z: Float)], y: Float, facingUp: Bool,
                                  material: SceneMaterial) -> SceneMesh {
        var mesh = SceneMesh(material: material)
        let triangles = Triangulator.triangulate(outline.map { SIMD2<Float>($0.x, $0.z) })
        guard !triangles.isEmpty else { return mesh }
        let normal = Vec3(0, facingUp ? 1 : -1, 0)
        mesh.positions = outline.map { Vec3($0.x, y, $0.z) }
        mesh.normals = Array(repeating: normal, count: outline.count)
        for t in triangles {
            let p0 = mesh.positions[t.0], p1 = mesh.positions[t.1], p2 = mesh.positions[t.2]
            let n = V3.cross(p1 - p0, p2 - p0)
            if (n.y > 0) == facingUp {
                mesh.indices += [UInt32(t.0), UInt32(t.1), UInt32(t.2)]
            } else {
                mesh.indices += [UInt32(t.0), UInt32(t.2), UInt32(t.1)]
            }
        }
        return mesh
    }
}

/// Perspective camera (written to glTF; also exported as CSV/JSON for Unreal CineCameraActors).
struct SceneCamera {
    /// Vertical field of view in radians.
    var yfov: Float
    var aspectRatio: Float
    var focalLength: Float
    var sensorWidth: Float
    var sensorHeight: Float
}

final class SceneNode {
    var name: String
    /// Local translation relative to the parent (mesh positions are relative to this pivot).
    var translation: Vec3 = .zero
    /// Optional rotation quaternion (x, y, z, w). Only used by camera nodes.
    var rotation: SIMD4<Float>?
    var camera: SceneCamera?
    var mesh: SceneMesh?
    var children: [SceneNode] = []
    /// Free-form metadata written to formats that support it (glTF extras, USD customData).
    var info: [String: String] = [:]

    init(name: String, mesh: SceneMesh? = nil, translation: Vec3 = .zero) {
        self.name = name
        self.mesh = mesh
        self.translation = translation
    }

    @discardableResult
    func addChild(_ node: SceneNode) -> SceneNode {
        children.append(node)
        return node
    }

    /// Depth-first walk with accumulated world translation.
    func walk(_ parentOffset: Vec3 = .zero, depth: Int = 0, _ visit: (SceneNode, Vec3, Int) -> Void) {
        let offset = parentOffset + translation
        visit(self, offset, depth)
        for c in children { c.walk(offset, depth: depth + 1, visit) }
    }

    /// Moves the node pivot to its mesh's bounding-box centre (nicer pivots in Unreal/DCCs).
    func recentreOnMesh() {
        guard var m = mesh, let b = m.bounds() else { return }
        let c = (b.min + b.max) / 2
        m.positions = m.positions.map { $0 - c }
        mesh = m
        translation += c
    }

    /// Removes empty groups.
    func pruned() -> SceneNode? {
        children = children.compactMap { $0.pruned() }
        if mesh?.isEmpty ?? true, children.isEmpty, camera == nil { return nil }
        return self
    }
}

struct SceneGeometry {
    var root: SceneNode
    var metadata: [String: String] = [:]

    var materials: [SceneMaterial] {
        var seen: [String: SceneMaterial] = [:]
        var order: [String] = []
        root.walk { node, _, _ in
            if let m = node.mesh?.material, seen[m.name] == nil {
                seen[m.name] = m
                order.append(m.name)
            }
        }
        return order.compactMap { seen[$0] }
    }

    var triangleCount: Int {
        var total = 0
        root.walk { node, _, _ in total += node.mesh?.triangleCount ?? 0 }
        return total
    }

    /// Unique, identifier-safe names (required by USD, helpful for Unreal outliner).
    func sanitizeNames() {
        func clean(_ s: String) -> String {
            var out = s.map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined()
            if out.isEmpty || out.first!.isNumber { out = "N_" + out }
            return out
        }
        func visit(_ node: SceneNode) {
            node.name = clean(node.name)
            var used: [String: Int] = [:]
            for child in node.children {
                child.name = clean(child.name)
                let count = used[child.name, default: 0]
                used[child.name] = count + 1
                if count > 0 { child.name += "_\(count + 1)" }
                visit(child)
            }
        }
        visit(root)
    }
}

extension SceneNode {
    /// Camera node from a rig: yaw = -pan about +Y, then tilt about local +X (camera looks down -Z).
    static func camera(named name: String, rig: CameraRig, floorY: Double) -> SceneNode {
        let node = SceneNode(name: name)
        node.translation = Vec3(Float(rig.position.x), Float(floorY + rig.height), Float(rig.position.z))
        let yaw = Float(-rig.pan * .pi / 180) / 2
        let pitch = Float(rig.tilt * .pi / 180) / 2
        let (sy, cy, sp, cp) = (sin(yaw), cos(yaw), sin(pitch), cos(pitch))
        node.rotation = SIMD4(cy * sp, sy * cp, -sy * sp, cy * cp)
        let area = rig.imageArea
        node.camera = SceneCamera(yfov: Float(rig.verticalFOV * .pi / 180),
                                  aspectRatio: Float(area.width / area.height),
                                  focalLength: Float(rig.focalLength),
                                  sensorWidth: Float(area.width), sensorHeight: Float(area.height))
        node.info = ["focal_length_mm": String(format: "%.1f", rig.focalLength),
                     "sensor": rig.sensor.displayName,
                     "height_m": String(format: "%.2f", rig.height)]
        return node
    }
}

/// Ear-clipping triangulation for simple polygons (floor outlines).
enum Triangulator {
    static func triangulate(_ points: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        let n = points.count
        guard n >= 3 else { return [] }
        var area: Float = 0
        for i in 0..<n {
            let a = points[i], b = points[(i + 1) % n]
            area += a.x * b.y - b.x * a.y
        }
        var remaining = Array(0..<n)
        if area < 0 { remaining.reverse() }

        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func inside(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0
        }

        var result: [(Int, Int, Int)] = []
        var guardCount = 0
        while remaining.count > 3 && guardCount < n * n {
            guardCount += 1
            var clipped = false
            for i in 0..<remaining.count {
                let ip = remaining[(i + remaining.count - 1) % remaining.count]
                let ic = remaining[i]
                let inx = remaining[(i + 1) % remaining.count]
                let a = points[ip], b = points[ic], c = points[inx]
                if cross(a, b, c) <= 1e-9 { continue }
                var ear = true
                for j in remaining where j != ip && j != ic && j != inx {
                    if inside(points[j], a, b, c) { ear = false; break }
                }
                if ear {
                    result.append((ip, ic, inx))
                    remaining.remove(at: i)
                    clipped = true
                    break
                }
            }
            if !clipped { break }
        }
        if remaining.count == 3 {
            result.append((remaining[0], remaining[1], remaining[2]))
        } else if remaining.count > 3 {
            // Degenerate / self-intersecting outline: fall back to a fan.
            for i in 1..<(remaining.count - 1) { result.append((remaining[0], remaining[i], remaining[i + 1])) }
        }
        return result
    }
}
