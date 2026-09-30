import Foundation

/// Wavefront OBJ + MTL. Each scene node becomes an OBJ group (`g Walls/Wall_01`) so the
/// hierarchy survives as separate objects in Blender, Maya, C4D and Unreal.
///
/// OBJ has no unit or axis metadata. `unrealUnits` writes centimetres with Z up and X forward,
/// matching Unreal Engine's native space; otherwise metres, Y up (ARKit/glTF convention).
enum OBJWriter {
    struct Output {
        var obj: String
        var mtl: String
    }

    static func make(_ scene: SceneGeometry, mtlFileName: String, unrealUnits: Bool) -> Output {
        scene.sanitizeNames()
        var obj = "# FrameScout OBJ export\n"
        obj += unrealUnits
            ? "# Units: centimetres. Axes: Z up, X forward (Unreal Engine space). Import with Uniform Scale 1.0.\n"
            : "# Units: metres. Axes: Y up, -Z forward (ARKit / glTF space).\n"
        for (k, v) in scene.metadata.sorted(by: { $0.key < $1.key }) { obj += "# \(k): \(v)\n" }
        obj += "mtllib \(mtlFileName)\n"

        var vertexBase = 1
        var lines: [String] = []
        scene.root.walk { node, offset, _ in
            guard let mesh = node.mesh, !mesh.isEmpty else { return }
            let groupPath = path(of: node, in: scene.root) ?? node.name
            lines.append("o \(node.name)")
            lines.append("g \(groupPath)")
            for p in mesh.positions {
                let v = convert(p + offset, unreal: unrealUnits)
                lines.append(String(format: "v %.5f %.5f %.5f", v.x, v.y, v.z))
            }
            let hasNormals = mesh.normals.count == mesh.positions.count
            if hasNormals {
                for n in mesh.normals {
                    let c = convertDirection(n, unreal: unrealUnits)
                    lines.append(String(format: "vn %.4f %.4f %.4f", c.x, c.y, c.z))
                }
            }
            lines.append("usemtl \(mesh.material.name)")
            var i = 0
            while i + 2 < mesh.indices.count {
                // Unreal space is left-handed, so winding flips to keep faces pointing outward.
                let a = Int(mesh.indices[i]) + vertexBase
                var b = Int(mesh.indices[i + 1]) + vertexBase
                var c = Int(mesh.indices[i + 2]) + vertexBase
                if unrealUnits { swap(&b, &c) }
                lines.append(hasNormals ? "f \(a)//\(a) \(b)//\(b) \(c)//\(c)" : "f \(a) \(b) \(c)")
                i += 3
            }
            vertexBase += mesh.positions.count
        }
        obj += lines.joined(separator: "\n")
        obj += "\n"

        var mtl = "# FrameScout materials\n"
        for m in scene.materials {
            mtl += """
            newmtl \(m.name)
            Kd \(String(format: "%.4f %.4f %.4f", m.color.x, m.color.y, m.color.z))
            Ka 0 0 0
            Ks 0.05 0.05 0.05
            Ns 10
            d \(String(format: "%.3f", m.color.w))
            illum 2

            """
        }
        return Output(obj: obj, mtl: mtl)
    }

    static func write(_ scene: SceneGeometry, to objURL: URL, unrealUnits: Bool) throws {
        let mtlURL = objURL.deletingPathExtension().appendingPathExtension("mtl")
        let out = make(scene, mtlFileName: mtlURL.lastPathComponent, unrealUnits: unrealUnits)
        try out.obj.write(to: objURL, atomically: true, encoding: .utf8)
        try out.mtl.write(to: mtlURL, atomically: true, encoding: .utf8)
    }

    /// ARKit (x right, y up, -z forward, metres) → Unreal (x forward, y right, z up, centimetres).
    static func convert(_ p: Vec3, unreal: Bool) -> Vec3 {
        guard unreal else { return p }
        return Vec3(-p.z, p.x, p.y) * 100
    }

    static func convertDirection(_ n: Vec3, unreal: Bool) -> Vec3 {
        guard unreal else { return n }
        return Vec3(-n.z, n.x, n.y)
    }

    private static func path(of target: SceneNode, in root: SceneNode) -> String? {
        func search(_ node: SceneNode, _ trail: [String]) -> [String]? {
            if node === target { return trail + [node.name] }
            for c in node.children {
                if let found = search(c, trail + [node.name]) { return found }
            }
            return nil
        }
        return search(root, [])?.dropFirst().joined(separator: "/")
    }
}
