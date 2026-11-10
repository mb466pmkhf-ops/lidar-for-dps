import Foundation

/// A photo-textured object (Object Capture output) in a format-neutral form, so the GLB and
/// OBJ writers can be tested off-device. Units: metres, +Y up. UVs use glTF's convention
/// (origin at the image's top-left), which is also how image files store their rows.
struct ModelTexture: Hashable {
    var data: Data
    /// "image/png" or "image/jpeg".
    var mimeType: String

    var fileExtension: String { mimeType == "image/jpeg" ? "jpg" : "png" }
}

struct TexturedMaterial: Hashable {
    var name: String
    var baseColor: ModelTexture? = nil
    var normal: ModelTexture? = nil
    /// Greyscale roughness. Used directly as glTF's metallic-roughness texture (roughness is
    /// read from G) with metallicFactor 0, so metallic stays zero whatever B holds.
    var roughness: ModelTexture? = nil
    /// Greyscale ambient occlusion (read from R).
    var occlusion: ModelTexture? = nil
    var baseColorFactor: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    var roughnessFactor: Float = 1
}

struct TexturedMesh {
    var name: String
    var positions: [Vec3] = []
    var normals: [Vec3] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    var material: TexturedMaterial

    var triangleCount: Int { indices.count / 3 }
}

struct TexturedModel {
    var name: String
    var meshes: [TexturedMesh]
    var metadata: [String: String] = [:]

    var triangleCount: Int { meshes.reduce(0) { $0 + $1.triangleCount } }
    var vertexCount: Int { meshes.reduce(0) { $0 + $1.positions.count } }

    func bounds() -> (min: Vec3, max: Vec3)? {
        var lo = Vec3(repeating: .greatestFiniteMagnitude), hi = Vec3(repeating: -.greatestFiniteMagnitude)
        var any = false
        for m in meshes {
            for p in m.positions {
                any = true
                lo = Vec3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                hi = Vec3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
            }
        }
        return any ? (lo, hi) : nil
    }

    /// Size of the bounding box in metres (width x, height y, depth z).
    var dimensions: Vec3 {
        guard let b = bounds() else { return .zero }
        return b.max - b.min
    }

    /// Moves the pivot to the centre of the object's footprint, resting on y = 0, which is
    /// where you want it when dropping the asset onto a floor in Unreal.
    func pivotAtBase() -> TexturedModel {
        guard let b = bounds() else { return self }
        let offset = Vec3((b.min.x + b.max.x) / 2, b.min.y, (b.min.z + b.max.z) / 2)
        var copy = self
        for i in copy.meshes.indices {
            copy.meshes[i].positions = copy.meshes[i].positions.map { $0 - offset }
        }
        return copy
    }

    /// Distinct textures in first-use order (shared between the writers).
    var textures: [ModelTexture] {
        var seen: [ModelTexture] = []
        for m in meshes {
            for t in [m.material.baseColor, m.material.normal, m.material.roughness, m.material.occlusion].compactMap({ $0 })
            where !seen.contains(t) {
                seen.append(t)
            }
        }
        return seen
    }
}

// MARK: - GLB

/// Binary glTF 2.0 with embedded textures. Unreal (Interchange, UE 5.1+), Blender, Maya and
/// most engines import it with materials wired up.
enum TexturedGLBWriter {
    static func data(for model: TexturedModel) throws -> Data {
        var bin = Data()
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []

        func align4() { while bin.count % 4 != 0 { bin.append(0) } }

        func addView(_ bytes: Data, target: Int?) -> Int {
            align4()
            let offset = bin.count
            bin.append(bytes)
            var view: [String: Any] = ["buffer": 0, "byteOffset": offset, "byteLength": bytes.count]
            if let target { view["target"] = target }
            bufferViews.append(view)
            return bufferViews.count - 1
        }

        func floats(_ values: [Float]) -> Data { values.withUnsafeBytes { Data($0) } }

        // Images → textures.
        let textures = model.textures
        var images: [[String: Any]] = []
        for t in textures {
            images.append(["bufferView": addView(t.data, target: nil), "mimeType": t.mimeType])
        }
        func textureIndex(_ t: ModelTexture?) -> Int? { t.flatMap { textures.firstIndex(of: $0) } }

        var materials: [[String: Any]] = []
        var materialIndex: [TexturedMaterial: Int] = [:]
        func material(_ m: TexturedMaterial) -> Int {
            if let i = materialIndex[m] { return i }
            var pbr: [String: Any] = [
                "baseColorFactor": [Double(m.baseColorFactor.x), Double(m.baseColorFactor.y),
                                    Double(m.baseColorFactor.z), Double(m.baseColorFactor.w)],
                "metallicFactor": 0.0,
                "roughnessFactor": Double(m.roughnessFactor),
            ]
            if let i = textureIndex(m.baseColor) { pbr["baseColorTexture"] = ["index": i] }
            if let i = textureIndex(m.roughness) { pbr["metallicRoughnessTexture"] = ["index": i] }
            var entry: [String: Any] = ["name": m.name, "pbrMetallicRoughness": pbr]
            if let i = textureIndex(m.normal) { entry["normalTexture"] = ["index": i] }
            if let i = textureIndex(m.occlusion) { entry["occlusionTexture"] = ["index": i] }
            materials.append(entry)
            materialIndex[m] = materials.count - 1
            return materials.count - 1
        }

        var meshes: [[String: Any]] = []
        var nodes: [[String: Any]] = []
        for mesh in model.meshes where !mesh.indices.isEmpty {
            var flat: [Float] = []
            flat.reserveCapacity(mesh.positions.count * 3)
            var lo = Vec3(repeating: .greatestFiniteMagnitude), hi = Vec3(repeating: -.greatestFiniteMagnitude)
            for p in mesh.positions {
                flat += [p.x, p.y, p.z]
                lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            accessors.append(["bufferView": addView(floats(flat), target: 34962), "componentType": 5126,
                              "count": mesh.positions.count, "type": "VEC3",
                              "min": [Double(lo.x), Double(lo.y), Double(lo.z)],
                              "max": [Double(hi.x), Double(hi.y), Double(hi.z)]])
            var attributes: [String: Any] = ["POSITION": accessors.count - 1]

            if mesh.normals.count == mesh.positions.count {
                var n: [Float] = []
                n.reserveCapacity(mesh.normals.count * 3)
                for v in mesh.normals { let u = V3.normalized(v); n += [u.x, u.y, u.z] }
                accessors.append(["bufferView": addView(floats(n), target: 34962), "componentType": 5126,
                                  "count": mesh.normals.count, "type": "VEC3"])
                attributes["NORMAL"] = accessors.count - 1
            }
            if mesh.uvs.count == mesh.positions.count {
                var uv: [Float] = []
                uv.reserveCapacity(mesh.uvs.count * 2)
                for t in mesh.uvs { uv += [t.x, t.y] }
                accessors.append(["bufferView": addView(floats(uv), target: 34962), "componentType": 5126,
                                  "count": mesh.uvs.count, "type": "VEC2"])
                attributes["TEXCOORD_0"] = accessors.count - 1
            }
            let indexData = mesh.indices.withUnsafeBytes { Data($0) }
            accessors.append(["bufferView": addView(indexData, target: 34963), "componentType": 5125,
                              "count": mesh.indices.count, "type": "SCALAR"])
            let primitive: [String: Any] = ["attributes": attributes, "indices": accessors.count - 1,
                                            "mode": 4, "material": material(mesh.material)]
            meshes.append(["name": mesh.name, "primitives": [primitive]])
            nodes.append(["name": mesh.name, "mesh": meshes.count - 1])
        }
        align4()

        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "FrameScout Object Capture", "extras": model.metadata],
            "scene": 0,
            "scenes": [["name": model.name, "nodes": Array(nodes.indices)]],
            "nodes": nodes,
            "buffers": [["byteLength": bin.count]],
        ]
        if !meshes.isEmpty {
            json["meshes"] = meshes
            json["accessors"] = accessors
            json["materials"] = materials
        }
        if !bufferViews.isEmpty { json["bufferViews"] = bufferViews }
        if !images.isEmpty {
            json["images"] = images
            json["samplers"] = [["magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497]]
            json["textures"] = images.indices.map { ["sampler": 0, "source": $0] }
        }

        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }

        var out = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        le32(0x46546C67) // "glTF"
        le32(2)
        le32(UInt32(12 + 8 + jsonData.count + 8 + bin.count))
        le32(UInt32(jsonData.count))
        le32(0x4E4F534A) // "JSON"
        out.append(jsonData)
        le32(UInt32(bin.count))
        le32(0x004E4942) // "BIN\0"
        out.append(bin)
        return out
    }
}

// MARK: - OBJ

/// OBJ + MTL + texture files. `unrealUnits` writes centimetres, Z up, X forward (Unreal's own
/// space, import at scale 1.0); otherwise metres, Y up.
enum TexturedOBJWriter {
    struct Output {
        var obj: String
        var mtl: String
        /// File name → bytes, written next to the OBJ.
        var textures: [String: Data]
    }

    static func make(_ model: TexturedModel, baseName: String, unrealUnits: Bool) -> Output {
        var fileNames: [ModelTexture: String] = [:]
        var files: [String: Data] = [:]
        func file(_ t: ModelTexture?, role: String, material: String) -> String? {
            guard let t else { return nil }
            if let existing = fileNames[t] { return existing }
            let name = "\(baseName)_\(material)_\(role).\(t.fileExtension)"
            fileNames[t] = name
            files[name] = t.data
            return name
        }

        var obj = "# FrameScout Object Capture OBJ\n"
        obj += unrealUnits
            ? "# Units: centimetres. Axes: Z up, X forward (Unreal Engine space). Import with Uniform Scale 1.0.\n"
            : "# Units: metres. Axes: Y up, -Z forward.\n"
        for (k, v) in model.metadata.sorted(by: { $0.key < $1.key }) { obj += "# \(k): \(v)\n" }
        obj += "mtllib \(baseName).mtl\n"

        var lines: [String] = []
        var mtl = "# FrameScout materials\n"
        var writtenMaterials = Set<String>()
        var base = 1
        for (index, mesh) in model.meshes.enumerated() where !mesh.indices.isEmpty {
            let matName = StoragePaths.safeName(mesh.material.name, fallback: "Material_\(index)")
            lines.append("o \(StoragePaths.safeName(mesh.name, fallback: "Mesh_\(index)"))")
            for p in mesh.positions {
                let v = OBJWriter.convert(p, unreal: unrealUnits)
                lines.append(String(format: "v %.5f %.5f %.5f", v.x, v.y, v.z))
            }
            let hasUV = mesh.uvs.count == mesh.positions.count
            if hasUV {
                // OBJ texture space has its origin bottom-left.
                for t in mesh.uvs { lines.append(String(format: "vt %.6f %.6f", t.x, 1 - t.y)) }
            }
            let hasNormals = mesh.normals.count == mesh.positions.count
            if hasNormals {
                for n in mesh.normals {
                    let c = OBJWriter.convertDirection(V3.normalized(n), unreal: unrealUnits)
                    lines.append(String(format: "vn %.4f %.4f %.4f", c.x, c.y, c.z))
                }
            }
            lines.append("usemtl \(matName)")
            var i = 0
            while i + 2 < mesh.indices.count {
                let a = Int(mesh.indices[i]) + base
                var b = Int(mesh.indices[i + 1]) + base
                var c = Int(mesh.indices[i + 2]) + base
                if unrealUnits { swap(&b, &c) }
                func ref(_ v: Int) -> String {
                    switch (hasUV, hasNormals) {
                    case (true, true): return "\(v)/\(v)/\(v)"
                    case (true, false): return "\(v)/\(v)"
                    case (false, true): return "\(v)//\(v)"
                    case (false, false): return "\(v)"
                    }
                }
                lines.append("f \(ref(a)) \(ref(b)) \(ref(c))")
                i += 3
            }
            base += mesh.positions.count

            guard !writtenMaterials.contains(matName) else { continue }
            writtenMaterials.insert(matName)
            let m = mesh.material
            let c = m.baseColorFactor
            mtl += "newmtl \(matName)\n"
            mtl += String(format: "Kd %.4f %.4f %.4f\nKa 0 0 0\nKs 0 0 0\nNs 10\nd 1\nillum 1\n", c.x, c.y, c.z)
            if let f = file(m.baseColor, role: "BaseColor", material: matName) { mtl += "map_Kd \(f)\n" }
            if let f = file(m.normal, role: "Normal", material: matName) { mtl += "norm \(f)\nmap_Bump \(f)\n" }
            if let f = file(m.roughness, role: "Roughness", material: matName) { mtl += "map_Pr \(f)\n" }
            if let f = file(m.occlusion, role: "AO", material: matName) { mtl += "map_Ka \(f)\n" }
            mtl += "\n"
        }
        obj += lines.joined(separator: "\n") + "\n"
        return Output(obj: obj, mtl: mtl, textures: files)
    }

    /// Writes `<baseName>.obj`, `<baseName>.mtl` and the textures into `directory`.
    @discardableResult
    static func write(_ model: TexturedModel, to directory: URL, baseName: String, unrealUnits: Bool) throws -> [URL] {
        let out = make(model, baseName: baseName, unrealUnits: unrealUnits)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        let objURL = directory.appendingPathComponent("\(baseName).obj")
        try out.obj.write(to: objURL, atomically: true, encoding: .utf8)
        urls.append(objURL)
        let mtlURL = directory.appendingPathComponent("\(baseName).mtl")
        try out.mtl.write(to: mtlURL, atomically: true, encoding: .utf8)
        urls.append(mtlURL)
        for (name, data) in out.textures.sorted(by: { $0.key < $1.key }) {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}
