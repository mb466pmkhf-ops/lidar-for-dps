import Foundation

/// Packages a scanned object for Unreal (and anything else that reads GLB, OBJ or USD).
enum ObjectExport {
    /// OBJECT_NAME/
    ///   OBJECT_NAME.glb                 ← recommended: drag into the Content Browser (UE 5.1+)
    ///   OBJECT_NAME.usdz                ← Apple original (UE USD Importer, Reality Composer)
    ///   Unreal_OBJ/OBJECT_NAME.obj/.mtl + textures   (centimetres, Z up)
    ///   README_UNREAL.txt   object.json   [Capture_Images/]
    static func buildUnrealPack(object: CapturedObject, projectID: UUID, includeImages: Bool) throws -> URL {
        let usdz = StoragePaths.objectFile(projectID, objectID: object.id, .usdz)
        let glb = StoragePaths.objectFile(projectID, objectID: object.id, .glb)
        let base = StoragePaths.safeName(object.name, fallback: "Object")
        let folder = base.uppercased()

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameScoutObject-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let root = staging.appendingPathComponent(folder, isDirectory: true)
        StoragePaths.ensureDirectory(root)

        let model = try ObjectModelConverter.load(usdz: usdz, name: object.name)
        if FileManager.default.fileExists(atPath: glb.path) {
            try FileManager.default.copyItem(at: glb, to: root.appendingPathComponent("\(base).glb"))
        } else {
            try TexturedGLBWriter.data(for: model).write(to: root.appendingPathComponent("\(base).glb"))
        }
        try FileManager.default.copyItem(at: usdz, to: root.appendingPathComponent("\(base).usdz"))
        try TexturedOBJWriter.write(model, to: root.appendingPathComponent("Unreal_OBJ", isDirectory: true),
                                    baseName: base, unrealUnits: true)
        try readme(object: object, base: base).write(to: root.appendingPathComponent("README_UNREAL.txt"),
                                                     atomically: true, encoding: .utf8)
        try metadata(object: object, model: model).write(to: root.appendingPathComponent("object.json"))

        StoragePaths.ensureDirectory(StoragePaths.exportsRoot)
        let zipURL = StoragePaths.exportsRoot.appendingPathComponent("\(folder)_\(stamp()).zip")
        let zip = try ZipWriter(url: zipURL)
        try zip.addDirectory(root, prefix: folder)
        if includeImages {
            try zip.addDirectory(StoragePaths.objectFile(projectID, objectID: object.id, .images),
                                 prefix: "\(folder)/Capture_Images")
        }
        try zip.finish()
        return zipURL
    }

    /// Just the Object Capture images, for building at full detail on a Mac.
    static func buildImagesArchive(object: CapturedObject, projectID: UUID) throws -> URL {
        let folder = StoragePaths.safeName(object.name, fallback: "Object").uppercased() + "_Capture_Images"
        StoragePaths.ensureDirectory(StoragePaths.exportsRoot)
        let zipURL = StoragePaths.exportsRoot.appendingPathComponent("\(folder)_\(stamp()).zip")
        let zip = try ZipWriter(url: zipURL)
        try zip.addDirectory(StoragePaths.objectFile(projectID, objectID: object.id, .images), prefix: folder)
        try zip.add(path: "\(folder)/README.txt", data: Data("""
        Object Capture images for \(object.name), taken with FrameScout.

        Build a full-detail model on a Mac (Apple silicon or AMD GPU):
          • Reality Composer Pro → File › New Object Capture Model → choose this folder, or
          • Apple's "Creating a photogrammetry command-line app" sample, detail level "full" or "raw".
        The HEIC files carry depth and gravity data, which improves scale and orientation.

        """.utf8))
        try zip.finish()
        return zipURL
    }

    /// Copies a file into Exports/ under a readable name so the share sheet shows it nicely.
    static func copyForSharing(_ url: URL, named name: String) throws -> URL {
        StoragePaths.ensureDirectory(StoragePaths.exportsRoot)
        let target = StoragePaths.exportsRoot.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    static func readme(object: CapturedObject, base: String) -> String {
        """
        \(object.name) — FrameScout object scan
        ======================================

        Size (w × h × d): \(object.dimensionsSummary ?? "—")
        Triangles: \(object.triangleCount)
        Pivot: centre of the base, so the object sits on the floor at 0.

        Getting it into Unreal Engine 5
        -------------------------------
        1. Recommended — \(base).glb
           Drag the file into the Content Browser (UE 5.1+, Interchange glTF importer).
           Units and axes are converted for you (glTF is metres, Y up). Base colour, normal,
           roughness and ambient occlusion textures are wired into the material.

        2. Unreal_OBJ/\(base).obj
           Already in Unreal space: centimetres, Z up, X forward. Import with
           Uniform Scale 1.0 and no rotation. Textures sit next to the OBJ.

        3. \(base).usdz
           Apple's original Object Capture output. Open with the USD Importer plugin
           (Edit › Plugins › USD Importer), or in Reality Composer / Blender 4.

        Tips
        ----
        • Enable Nanite on the static mesh for dense scans; set Collision to "Use Complex As Simple"
          if you need precise contact, or add a simple box collision for props.
        • If the object looks too shiny, raise the material's roughness — phone scans can't
          measure specular response.
        • For a hero asset, rebuild from the capture images on a Mac at "full" or "raw" detail.

        """
    }

    private static func metadata(object: CapturedObject, model: TexturedModel) throws -> Data {
        let d = model.dimensions
        let info: [String: Any] = [
            "name": object.name,
            "captured": ISO8601DateFormatter().string(from: object.createdAt),
            "device": object.deviceModel,
            "units": "metres",
            "upAxis": "Y",
            "pivot": "base centre",
            "dimensions_m": ["width": Double(d.x), "height": Double(d.y), "depth": Double(d.z)],
            "triangles": model.triangleCount,
            "vertices": model.vertexCount,
            "captureImages": object.imageCount,
            "scanPasses": object.scanPasses,
            "notes": object.notes,
        ]
        return try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }
}
