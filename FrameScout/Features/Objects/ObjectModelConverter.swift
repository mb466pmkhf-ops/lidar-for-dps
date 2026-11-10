import Foundation
import ImageIO
import ModelIO
import simd
import UniformTypeIdentifiers

/// Turns Object Capture's USDZ into a `TexturedModel` for the GLB / OBJ writers.
///
/// Geometry comes through ModelIO. Textures are taken byte-for-byte from inside the USDZ
/// (it is an uncompressed ZIP) whenever the material property can be traced to a file, so
/// nothing is re-encoded or flipped; ModelIO's decoded pixels are only a fallback.
enum ObjectModelConverter {
    struct Summary {
        var triangles: Int
        var vertices: Int
        var dimensions: Vec3
    }

    enum ConversionError: LocalizedError {
        case noGeometry
        var errorDescription: String? { "The reconstructed model has no readable geometry." }
    }

    static func load(usdz: URL, name: String) throws -> TexturedModel {
        let asset = MDLAsset(url: usdz)
        let archive = try? ZipReader(url: usdz)
        let images = (archive?.entries ?? []).filter { entry in
            !entry.isDirectory && ["png", "jpg", "jpeg"].contains((entry.path as NSString).pathExtension.lowercased())
        }
        let resolver = TextureResolver(archive: archive, images: images)

        var meshes: [TexturedMesh] = []
        for case let mesh as MDLMesh in asset.childObjects(of: MDLMesh.self) {
            meshes += convert(mesh, resolver: resolver)
        }
        // Properties that were not traceable to a file need decoded pixels.
        if meshes.contains(where: { $0.material.baseColor == nil }) {
            asset.loadTextures()
            meshes = []
            for case let mesh as MDLMesh in asset.childObjects(of: MDLMesh.self) {
                meshes += convert(mesh, resolver: resolver)
            }
        }
        guard !meshes.isEmpty else { throw ConversionError.noGeometry }

        var model = TexturedModel(name: name, meshes: meshes,
                                  metadata: ["source": "Apple Object Capture (on device)",
                                             "units": "metres", "upAxis": "Y", "pivot": "base centre"])
        // Object Capture writes metres; guard against a centimetre stage just in case.
        let dims = model.dimensions
        if max(dims.x, dims.y, dims.z) > 20 {
            for i in model.meshes.indices { model.meshes[i].positions = model.meshes[i].positions.map { $0 * 0.01 } }
        }
        return model.pivotAtBase()
    }

    @discardableResult
    static func writeGLB(usdz: URL, to glb: URL, name: String) throws -> Summary {
        let model = try load(usdz: usdz, name: name)
        try TexturedGLBWriter.data(for: model).write(to: glb, options: .atomic)
        return Summary(triangles: model.triangleCount, vertices: model.vertexCount, dimensions: model.dimensions)
    }

    // MARK: Geometry

    private static func convert(_ mesh: MDLMesh, resolver: TextureResolver) -> [TexturedMesh] {
        let count = mesh.vertexCount
        guard count > 0,
              let posData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { return [] }
        let transform = MDLTransform.globalTransform(with: mesh, atTime: 0)

        func readFloats(_ data: MDLVertexAttributeData, components: Int, at i: Int) -> [Float] {
            let p = data.dataStart.advanced(by: i * data.stride).assumingMemoryBound(to: Float.self)
            return (0..<components).map { p[$0] }
        }

        var positions: [Vec3] = []
        positions.reserveCapacity(count)
        for i in 0..<count {
            let f = readFloats(posData, components: 3, at: i)
            let w = transform * SIMD4<Float>(f[0], f[1], f[2], 1)
            positions.append(Vec3(w.x, w.y, w.z))
        }
        var normals: [Vec3] = []
        if let nData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3) {
            normals.reserveCapacity(count)
            for i in 0..<count {
                let f = readFloats(nData, components: 3, at: i)
                let w = transform * SIMD4<Float>(f[0], f[1], f[2], 0)
                normals.append(V3.normalized(Vec3(w.x, w.y, w.z)))
            }
        }
        var uvs: [SIMD2<Float>] = []
        if let tData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2) {
            uvs.reserveCapacity(count)
            for i in 0..<count {
                let f = readFloats(tData, components: 2, at: i)
                // USD's st origin is bottom-left; glTF's is top-left.
                uvs.append(SIMD2(f[0], 1 - f[1]))
            }
        }

        var out: [TexturedMesh] = []
        let submeshes = (mesh.submeshes as? [MDLSubmesh]) ?? []
        for (index, sub) in submeshes.enumerated() where sub.geometryType == .triangles && sub.indexCount > 0 {
            let buffer = sub.indexBuffer(asIndexType: .uInt32)
            let map = buffer.map()
            let ptr = map.bytes.assumingMemoryBound(to: UInt32.self)
            let indices = Array(UnsafeBufferPointer(start: ptr, count: sub.indexCount))
            let materialName = sub.material?.name.isEmpty == false ? sub.material!.name : "Material_\(index)"
            let material = TexturedMaterial(
                name: materialName,
                baseColor: resolver.texture(.baseColor, in: sub.material),
                normal: resolver.texture(.tangentSpaceNormal, in: sub.material),
                roughness: resolver.texture(.roughness, in: sub.material),
                occlusion: resolver.texture(.ambientOcclusion, in: sub.material))
            let meshName = mesh.name.isEmpty ? "Object" : mesh.name
            out.append(TexturedMesh(name: submeshes.count > 1 ? "\(meshName)_\(index)" : meshName,
                                    positions: positions, normals: normals, uvs: uvs,
                                    indices: indices, material: material))
        }
        return out
    }
}

/// Finds the image for a material channel: first the file inside the USDZ the property names,
/// then Object Capture's own file naming, then ModelIO's decoded pixels.
private struct TextureResolver {
    let archive: ZipReader?
    let images: [ZipReader.Entry]

    func texture(_ semantic: MDLMaterialSemantic, in material: MDLMaterial?) -> ModelTexture? {
        let property = material?.property(with: semantic)
        if let property, let entry = entry(named: references(of: property)), let t = raw(entry) { return t }
        if let entry = entryByConvention(semantic), let t = raw(entry) { return t }
        if let property, let t = decoded(property, semantic: semantic) { return t }
        return nil
    }

    private func references(of property: MDLMaterialProperty) -> [String] {
        var names: [String] = []
        if let s = property.stringValue { names.append(s) }
        if let u = property.urlValue { names.append(u.absoluteString) }
        if let tex = property.textureSamplerValue?.texture {
            names.append(tex.name)
            if let u = (tex as? MDLURLTexture)?.url { names.append(u.absoluteString) }
        }
        return names.filter { !$0.isEmpty }
    }

    /// "…/model.usdz[0/baked_mesh_tex0.png]" → "baked_mesh_tex0.png".
    private func entry(named references: [String]) -> ZipReader.Entry? {
        for ref in references {
            var inner = ref
            if let open = inner.lastIndex(of: "["), let close = inner.lastIndex(of: "]"), open < close {
                inner = String(inner[inner.index(after: open)..<close])
            }
            inner = inner.removingPercentEncoding ?? inner
            let file = (inner as NSString).lastPathComponent.lowercased()
            guard !file.isEmpty else { continue }
            if let hit = images.first(where: { ($0.path as NSString).lastPathComponent.lowercased() == file }) { return hit }
        }
        return nil
    }

    private func entryByConvention(_ semantic: MDLMaterialSemantic) -> ZipReader.Entry? {
        func name(_ e: ZipReader.Entry) -> String { (e.path as NSString).lastPathComponent.lowercased() }
        let isNormal = { (e: ZipReader.Entry) in name(e).contains("norm") }
        let isAO = { (e: ZipReader.Entry) in name(e).contains("_ao") || name(e).contains("occlusion") }
        let isRough = { (e: ZipReader.Entry) in name(e).contains("rough") }
        switch semantic {
        case .tangentSpaceNormal: return images.first(where: isNormal)
        case .ambientOcclusion: return images.first(where: isAO)
        case .roughness: return images.first(where: isRough)
        case .baseColor:
            let colour = images.filter { !isNormal($0) && !isAO($0) && !isRough($0) && !name($0).contains("metal") }
            return colour.count == 1 ? colour[0] : colour.first(where: { name($0).contains("tex") || name($0).contains("color") || name($0).contains("diffuse") })
        default: return nil
        }
    }

    private func raw(_ entry: ZipReader.Entry) -> ModelTexture? {
        guard let data = try? archive?.data(for: entry), data.count > 8 else { return nil }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ModelTexture(data: data, mimeType: "image/png") }
        if data.starts(with: [0xFF, 0xD8]) { return ModelTexture(data: data, mimeType: "image/jpeg") }
        return reencode(data)
    }

    private func decoded(_ property: MDLMaterialProperty, semantic: MDLMaterialSemantic) -> ModelTexture? {
        if let tex = property.textureSamplerValue?.texture, let image = tex.imageFromTexture()?.takeUnretainedValue() {
            return encode(image, jpeg: semantic == .baseColor)
        }
        if property.type == .URL, let url = property.urlValue, let data = try? Data(contentsOf: url) {
            return reencode(data)
        }
        return nil
    }

    private func reencode(_ data: Data) -> ModelTexture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return encode(image, jpeg: false)
    }

    private func encode(_ image: CGImage, jpeg: Bool) -> ModelTexture? {
        let out = NSMutableData()
        let type = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        let options: [CFString: Any] = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return ModelTexture(data: out as Data, mimeType: jpeg ? "image/jpeg" : "image/png")
    }
}
