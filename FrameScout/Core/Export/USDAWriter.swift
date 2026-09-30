import Foundation

/// Writes a `SceneGeometry` as a USD ASCII layer (and packages it as USDZ).
///
/// Metres, Y-up (`metersPerUnit = 1`, `upAxis = "Y"`) — Unreal's USD importer and USD Stage
/// convert to centimetres / Z-up automatically from this layer metadata.
enum USDAWriter {
    static func string(for scene: SceneGeometry) -> String {
        scene.sanitizeNames()
        let rootName = scene.root.name
        var out = """
        #usda 1.0
        (
            defaultPrim = "\(rootName)"
            metersPerUnit = 1
            upAxis = "Y"
            doc = "Exported by FrameScout — LiDAR location scout for cinematographers"
            customLayerData = {
        \(scene.metadata.sorted { $0.key < $1.key }.map { "        string \(identifier($0.key)) = \"\(escape($0.value))\"" }.joined(separator: "\n"))
            }
        )

        """
        out += "def Xform \"\(rootName)\" (\n    kind = \"assembly\"\n)\n{\n"
        writeMaterials(scene.materials, rootName: rootName, into: &out, indent: 1)
        for child in scene.root.children {
            writeNode(child, path: "/\(rootName)", rootName: rootName, into: &out, indent: 1)
        }
        out += "}\n"
        return out
    }

    static func write(_ scene: SceneGeometry, to url: URL) throws {
        try string(for: scene).write(to: url, atomically: true, encoding: .utf8)
    }

    /// USDZ = uncompressed ZIP whose first entry is the USD layer, data aligned to 64 bytes.
    static func writeUSDZ(_ scene: SceneGeometry, to url: URL, layerName: String = "scene.usda") throws {
        let layer = Data(string(for: scene).utf8)
        let zip = try ZipWriter(url: url)
        try zip.add(path: layerName, data: layer, compress: false, alignment: 64)
        try zip.finish()
    }

    // MARK: -

    private static func pad(_ n: Int) -> String { String(repeating: "    ", count: n) }

    private static func identifier(_ s: String) -> String {
        let cleaned = s.map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "_" }.joined()
        return cleaned.first?.isNumber == true ? "_" + cleaned : cleaned
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func f(_ v: Float) -> String {
        let s = String(format: "%.5g", Double(v))
        return s == "-0" ? "0" : s
    }

    private static func tuple(_ v: Vec3) -> String { "(\(f(v.x)), \(f(v.y)), \(f(v.z)))" }

    private static func writeMaterials(_ materials: [SceneMaterial], rootName: String, into out: inout String, indent: Int) {
        let p = pad(indent)
        out += "\(p)def Scope \"Materials\"\n\(p){\n"
        for m in materials {
            let name = identifier(m.name)
            let path = "/\(rootName)/Materials/\(name)"
            out += """
            \(p)    def Material "\(name)"
            \(p)    {
            \(p)        token outputs:surface.connect = <\(path)/PreviewSurface.outputs:surface>

            \(p)        def Shader "PreviewSurface"
            \(p)        {
            \(p)            uniform token info:id = "UsdPreviewSurface"
            \(p)            color3f inputs:diffuseColor = (\(f(m.color.x)), \(f(m.color.y)), \(f(m.color.z)))
            \(p)            float inputs:opacity = \(f(m.color.w))
            \(p)            float inputs:roughness = \(f(m.roughness))
            \(p)            float inputs:metallic = \(f(m.metallic))
            \(p)            token outputs:surface
            \(p)        }
            \(p)    }

            """
        }
        out += "\(p)}\n"
    }

    private static func writeNode(_ node: SceneNode, path: String, rootName: String, into out: inout String, indent: Int) {
        // Cameras travel in the GLB and the CSV/JSON files (USD camera units vary between DCCs).
        if node.camera != nil { return }
        let p = pad(indent)
        let nodePath = "\(path)/\(node.name)"
        let infoLines = node.info.sorted { $0.key < $1.key }
            .map { "\(p)        string \(identifier($0.key)) = \"\(escape($0.value))\"" }
            .joined(separator: "\n")
        let customData = node.info.isEmpty ? "" : "\(p)    customData = {\n\(infoLines)\n\(p)    }\n"

        if let mesh = node.mesh, !mesh.isEmpty {
            // A mesh node becomes an Xform (pivot) holding a Mesh prim, so children can nest.
            out += "\(p)def Xform \"\(node.name)\" (\n\(customData)\(p))\n\(p){\n"
            writeTranslate(node.translation, into: &out, indent: indent + 1)
            writeMesh(mesh, name: "Geom", rootName: rootName, into: &out, indent: indent + 1)
        } else {
            out += "\(p)def Xform \"\(node.name)\" (\n\(customData)\(p))\n\(p){\n"
            writeTranslate(node.translation, into: &out, indent: indent + 1)
        }
        for child in node.children {
            writeNode(child, path: nodePath, rootName: rootName, into: &out, indent: indent + 1)
        }
        out += "\(p)}\n"
    }

    private static func writeTranslate(_ t: Vec3, into out: inout String, indent: Int) {
        guard t != .zero else { return }
        let p = pad(indent)
        out += "\(p)double3 xformOp:translate = \(tuple(t))\n"
        out += "\(p)uniform token[] xformOpOrder = [\"xformOp:translate\"]\n"
    }

    private static func writeMesh(_ mesh: SceneMesh, name: String, rootName: String, into out: inout String, indent: Int) {
        let p = pad(indent)
        let material = identifier(mesh.material.name)
        var lo = Vec3(repeating: .greatestFiniteMagnitude), hi = Vec3(repeating: -.greatestFiniteMagnitude)
        for v in mesh.positions {
            lo = Vec3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
            hi = Vec3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
        }
        out += "\(p)def Mesh \"\(name)\" (\n\(p)    prepend apiSchemas = [\"MaterialBindingAPI\"]\n\(p))\n\(p){\n"
        out += "\(p)    float3[] extent = [\(tuple(lo)), \(tuple(hi))]\n"
        out += "\(p)    int[] faceVertexCounts = [\(Array(repeating: "3", count: mesh.triangleCount).joined(separator: ", "))]\n"
        out += "\(p)    int[] faceVertexIndices = [\(mesh.indices.map { String($0) }.joined(separator: ", "))]\n"
        out += "\(p)    point3f[] points = [\(mesh.positions.map(tuple).joined(separator: ", "))]\n"
        if mesh.normals.count == mesh.positions.count {
            out += "\(p)    normal3f[] normals = [\(mesh.normals.map(tuple).joined(separator: ", "))] (\n\(p)        interpolation = \"vertex\"\n\(p)    )\n"
        }
        out += "\(p)    uniform token orientation = \"rightHanded\"\n"
        out += "\(p)    uniform token subdivisionScheme = \"none\"\n"
        out += "\(p)    uniform bool doubleSided = \(mesh.material.isTranslucent ? "1" : "0")\n"
        out += "\(p)    rel material:binding = </\(rootName)/Materials/\(material)>\n"
        out += "\(p)}\n"
    }
}
