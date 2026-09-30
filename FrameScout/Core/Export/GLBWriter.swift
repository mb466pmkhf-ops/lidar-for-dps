import Foundation

/// Binary glTF 2.0 (.glb). glTF is metres / Y-up by specification, so Unreal's built-in
/// glTF importer (Interchange, UE 5.1+) brings it in at correct scale and orientation with
/// the node hierarchy and PBR base colours intact.
enum GLBWriter {
    enum GLBError: Error { case encoding }

    static func data(for scene: SceneGeometry) throws -> Data {
        scene.sanitizeNames()
        var bin = Data()
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var meshes: [[String: Any]] = []
        var nodes: [[String: Any]] = []
        var cameras: [[String: Any]] = []

        let materials = scene.materials
        let materialIndex = Dictionary(uniqueKeysWithValues: materials.enumerated().map { ($1.name, $0) })

        func align4() { while bin.count % 4 != 0 { bin.append(0) } }

        func addView<T>(_ values: [T], target: Int) -> Int {
            align4()
            let offset = bin.count
            values.withUnsafeBytes { bin.append(contentsOf: $0) }
            bufferViews.append(["buffer": 0, "byteOffset": offset, "byteLength": bin.count - offset, "target": target])
            return bufferViews.count - 1
        }

        func addMesh(_ mesh: SceneMesh, name: String) -> Int {
            // Pack as tightly laid out Float triples (SIMD3<Float> has 16-byte stride).
            var flatPositions: [Float] = []
            flatPositions.reserveCapacity(mesh.positions.count * 3)
            var lo = Vec3(repeating: .greatestFiniteMagnitude), hi = Vec3(repeating: -.greatestFiniteMagnitude)
            for p in mesh.positions {
                flatPositions += [p.x, p.y, p.z]
                lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            let posView = addView(flatPositions, target: 34962)
            accessors.append([
                "bufferView": posView, "componentType": 5126, "count": mesh.positions.count, "type": "VEC3",
                "min": [Double(lo.x), Double(lo.y), Double(lo.z)], "max": [Double(hi.x), Double(hi.y), Double(hi.z)],
            ])
            let posAccessor = accessors.count - 1

            var attributes: [String: Any] = ["POSITION": posAccessor]
            if mesh.normals.count == mesh.positions.count {
                var flat: [Float] = []
                flat.reserveCapacity(mesh.normals.count * 3)
                for n in mesh.normals { flat += [n.x, n.y, n.z] }
                let nView = addView(flat, target: 34962)
                accessors.append(["bufferView": nView, "componentType": 5126, "count": mesh.normals.count, "type": "VEC3"])
                attributes["NORMAL"] = accessors.count - 1
            }

            let iView = addView(mesh.indices, target: 34963)
            accessors.append(["bufferView": iView, "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"])

            var primitive: [String: Any] = ["attributes": attributes, "indices": accessors.count - 1, "mode": 4]
            if let mi = materialIndex[mesh.material.name] { primitive["material"] = mi }
            meshes.append(["name": name, "primitives": [primitive]])
            return meshes.count - 1
        }

        @discardableResult
        func addNode(_ node: SceneNode) -> Int {
            let index = nodes.count
            nodes.append([:])
            var entry: [String: Any] = ["name": node.name]
            if node.translation != .zero {
                entry["translation"] = [Double(node.translation.x), Double(node.translation.y), Double(node.translation.z)]
            }
            if let r = node.rotation {
                entry["rotation"] = [Double(r.x), Double(r.y), Double(r.z), Double(r.w)]
            }
            if let cam = node.camera {
                cameras.append([
                    "name": node.name,
                    "type": "perspective",
                    "perspective": ["yfov": Double(cam.yfov), "aspectRatio": Double(cam.aspectRatio),
                                    "znear": 0.05, "zfar": 1000.0],
                    "extras": ["focalLength_mm": Double(cam.focalLength),
                               "sensorWidth_mm": Double(cam.sensorWidth),
                               "sensorHeight_mm": Double(cam.sensorHeight)],
                ])
                entry["camera"] = cameras.count - 1
            }
            if let mesh = node.mesh, !mesh.isEmpty { entry["mesh"] = addMesh(mesh, name: node.name) }
            if !node.info.isEmpty { entry["extras"] = node.info }
            let children = node.children.map { addNode($0) }
            if !children.isEmpty { entry["children"] = children }
            nodes[index] = entry
            return index
        }

        let rootIndex = addNode(scene.root)
        align4()

        let materialJSON: [[String: Any]] = materials.map { m in
            var mat: [String: Any] = [
                "name": m.name,
                "pbrMetallicRoughness": [
                    "baseColorFactor": [Double(m.color.x), Double(m.color.y), Double(m.color.z), Double(m.color.w)],
                    "metallicFactor": Double(m.metallic),
                    "roughnessFactor": Double(m.roughness),
                ],
            ]
            if m.isTranslucent {
                mat["alphaMode"] = "BLEND"
                mat["doubleSided"] = true
            }
            return mat
        }

        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "FrameScout", "extras": scene.metadata],
            "scene": 0,
            "scenes": [["name": scene.root.name, "nodes": [rootIndex]]],
            "nodes": nodes,
            "buffers": [["byteLength": bin.count]],
        ]
        if !meshes.isEmpty {
            json["meshes"] = meshes
            json["accessors"] = accessors
            json["bufferViews"] = bufferViews
        }
        if !materialJSON.isEmpty { json["materials"] = materialJSON }
        if !cameras.isEmpty { json["cameras"] = cameras }

        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }

        var out = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        let total = 12 + 8 + jsonData.count + 8 + bin.count
        le32(0x46546C67) // "glTF"
        le32(2)
        le32(UInt32(total))
        le32(UInt32(jsonData.count))
        le32(0x4E4F534A) // "JSON"
        out.append(jsonData)
        le32(UInt32(bin.count))
        le32(0x004E4942) // "BIN\0"
        out.append(bin)
        return out
    }

    static func write(_ scene: SceneGeometry, to url: URL) throws {
        try data(for: scene).write(to: url, options: .atomic)
    }
}
