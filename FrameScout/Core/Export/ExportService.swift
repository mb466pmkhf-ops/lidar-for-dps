import Foundation

struct ExportOptions: Codable, Hashable {
    var usdz = true
    var usda = false
    var obj = true
    var glb = true
    /// Adds an Unreal folder: centimetre/Z-up OBJ, camera CSV for CineCameraActors and a README.
    var unrealPreset = true
    /// Include Apple's own RoomPlan USDZ (room scans) alongside FrameScout's geometry.
    var includeRoomPlanNative = true
    var includeCeiling = false
    var includeFurniture = true
    var includeCameras = true
    var includePhotos = true
}

/// Builds exports on a background thread from value copies of the project data.
enum ExportService {
    enum ExportError: LocalizedError {
        case noScan
        var errorDescription: String? { "This location has no scan to export." }
    }

    static let geometryBaseName = "location"

    // MARK: Scan files

    /// Writes the chosen 3D formats for `scan` into `folder`. Returns the written files.
    @discardableResult
    static func writeScanFiles(scan: ScanRecord, location: Location, ref: LocationRef,
                               options: ExportOptions, to folder: URL) throws -> [URL] {
        StoragePaths.ensureDirectory(folder)
        let geometryOptions = RoomPlanConverter.GeometryOptions(includeCeiling: options.includeCeiling,
                                                                includeObjects: options.includeFurniture)
        var scene = try ScanAssets.geometry(for: scan, ref: ref, options: geometryOptions)
        scene.metadata["location"] = location.name
        let floorY = floorHeight(scan: scan, ref: ref)

        var written: [URL] = []
        if options.usdz {
            let url = folder.appendingPathComponent("\(geometryBaseName).usdz")
            try USDAWriter.writeUSDZ(scene, to: url, layerName: "\(geometryBaseName).usda")
            written.append(url)
        }
        if options.usda {
            let url = folder.appendingPathComponent("\(geometryBaseName).usda")
            try USDAWriter.write(scene, to: url)
            written.append(url)
        }
        if options.obj {
            let url = folder.appendingPathComponent("\(geometryBaseName).obj")
            try OBJWriter.write(scene, to: url, unrealUnits: false)
            written += [url, url.deletingPathExtension().appendingPathExtension("mtl")]
        }
        if options.glb {
            let url = folder.appendingPathComponent("\(geometryBaseName).glb")
            if options.includeCameras {
                let cams = scene.root.addChild(SceneNode(name: "Cameras"))
                for cam in location.cameraPositions where cam.scanID == nil || cam.scanID == scan.id {
                    cams.addChild(.camera(named: "CAM_" + cam.name, rig: cam.rig, floorY: floorY))
                }
                for shot in location.shots where shot.scanID == nil || shot.scanID == scan.id {
                    cams.addChild(.camera(named: String(format: "SHOT_%02d", shot.number), rig: shot.rig, floorY: floorY))
                }
                if cams.children.isEmpty { scene.root.children.removeAll { $0 === cams } }
            }
            try GLBWriter.write(scene, to: url)
            written.append(url)
        }
        if options.includeRoomPlanNative, scan.kind == .room {
            let native = StoragePaths.scanFile(ref, scanID: scan.id, .roomPlanUSDZ)
            if FileManager.default.fileExists(atPath: native.path) {
                let url = folder.appendingPathComponent("\(geometryBaseName)_roomplan_apple.usdz")
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.copyItem(at: native, to: url)
                written.append(url)
            }
        }
        if options.unrealPreset {
            let unreal = folder.appendingPathComponent("Unreal", isDirectory: true)
            StoragePaths.ensureDirectory(unreal)
            let objURL = unreal.appendingPathComponent("\(geometryBaseName)_unreal_cm_zup.obj")
            try OBJWriter.write(scene, to: objURL, unrealUnits: true)
            written.append(objURL)
            let csv = unrealCameraCSV(location: location, scanID: scan.id, floorY: floorY)
            let csvURL = unreal.appendingPathComponent("cameras_unreal.csv")
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
            written.append(csvURL)
            let readme = unreal.appendingPathComponent("README_UNREAL.md")
            try unrealReadme(scan: scan).write(to: readme, atomically: true, encoding: .utf8)
            written.append(readme)
        }
        return written
    }

    static func floorHeight(scan: ScanRecord, ref: LocationRef) -> Double {
        let url = StoragePaths.scanFile(ref, scanID: scan.id, .plan)
        guard let data = try? Data(contentsOf: url),
              let plan = try? JSONCoding.decoder.decode(FloorPlan.self, from: data) else { return 0 }
        return plan.floorY
    }

    // MARK: Location package

    /// LOCATION_NAME/{Scan, Photos, Measurements, Camera_Positions, Notes, Metadata} zipped.
    static func buildLocationPackage(project: Project, location: Location, ref: LocationRef,
                                     options: ExportOptions) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameScoutExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let folderName = StoragePaths.safeName(location.name, fallback: "LOCATION").uppercased()
        let root = staging.appendingPathComponent(folderName, isDirectory: true)
        try writeLocationFolder(project: project, location: location, ref: ref, options: options, into: root)

        StoragePaths.ensureDirectory(StoragePaths.exportsRoot)
        let stamp = exportStamp()
        let zipURL = StoragePaths.exportsRoot.appendingPathComponent("\(folderName)_\(stamp).zip")
        let zip = try ZipWriter(url: zipURL)
        try zip.addDirectory(root, prefix: folderName)
        try zip.finish()
        return zipURL
    }

    /// Every location in the project, each in its own package folder, plus a project summary.
    static func buildProjectPackage(project: Project, options: ExportOptions) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameScoutExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let projectName = StoragePaths.safeName(project.name, fallback: "PROJECT").uppercased()
        let root = staging.appendingPathComponent(projectName, isDirectory: true)
        StoragePaths.ensureDirectory(root)
        var used: Set<String> = []
        for (index, location) in project.locations.enumerated() {
            var name = String(format: "LOCATION_%03d_", index + 1) + StoragePaths.safeName(location.name).uppercased()
            while used.contains(name) { name += "_" }
            used.insert(name)
            let ref = LocationRef(projectID: project.id, locationID: location.id)
            try writeLocationFolder(project: project, location: location, ref: ref, options: options,
                                    into: root.appendingPathComponent(name, isDirectory: true))
        }
        try projectSummary(project).write(to: root.appendingPathComponent("PROJECT_SUMMARY.txt"),
                                          atomically: true, encoding: .utf8)

        StoragePaths.ensureDirectory(StoragePaths.exportsRoot)
        let zipURL = StoragePaths.exportsRoot.appendingPathComponent("\(projectName)_\(exportStamp()).zip")
        let zip = try ZipWriter(url: zipURL)
        try zip.addDirectory(root, prefix: projectName)
        try zip.finish()
        return zipURL
    }

    /// Raw project folder for moving between devices (re-importable via Import Project).
    static func buildProjectBackup(project: Project) throws -> URL {
        StoragePaths.ensureDirectory(StoragePaths.exportsRoot)
        let name = StoragePaths.safeName(project.name, fallback: "Project")
        let zipURL = StoragePaths.exportsRoot.appendingPathComponent("\(name)_\(exportStamp()).framescout.zip")
        let zip = try ZipWriter(url: zipURL)
        try zip.addDirectory(StoragePaths.projectDir(project.id), prefix: "\(name).framescout")
        try zip.finish()
        return zipURL
    }

    private static func writeLocationFolder(project: Project, location: Location, ref: LocationRef,
                                            options: ExportOptions, into root: URL) throws {
        let fm = FileManager.default
        let dirs = ["Scan", "Photos", "Measurements", "Camera_Positions", "Notes", "Metadata"]
        for d in dirs { StoragePaths.ensureDirectory(root.appendingPathComponent(d, isDirectory: true)) }

        // Scan
        var scanFiles: [String] = []
        if let scan = location.primaryScan {
            let files = try writeScanFiles(scan: scan, location: location, ref: ref, options: options,
                                           to: root.appendingPathComponent("Scan", isDirectory: true))
            scanFiles = files.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
            let plan = StoragePaths.scanFile(ref, scanID: scan.id, .plan)
            if fm.fileExists(atPath: plan.path) {
                try? fm.copyItem(at: plan, to: root.appendingPathComponent("Metadata/floor_plan.json"))
            }
            if scan.kind == .room {
                let rooms = StoragePaths.scanFile(ref, scanID: scan.id, .rooms)
                if fm.fileExists(atPath: rooms.path) {
                    try? fm.copyItem(at: rooms, to: root.appendingPathComponent("Metadata/roomplan_captured_rooms.json"))
                }
            }
        }

        // Photos
        var photoIndex: [[String: Any]] = []
        if options.includePhotos {
            for (i, photo) in location.photos.enumerated() {
                let caption = photo.caption.isEmpty ? photo.source.rawValue : StoragePaths.safeName(photo.caption)
                let name = String(format: "%03d_", i + 1) + caption + ".jpg"
                let src = StoragePaths.photoURL(ref, photo)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: root.appendingPathComponent("Photos/\(name)"))
                var entry: [String: Any] = ["file": "Photos/\(name)", "caption": photo.caption,
                                            "source": photo.source.rawValue,
                                            "created": iso(photo.createdAt)]
                if let lens = photo.lensDescription { entry["lens"] = lens }
                if let pose = photo.pose {
                    entry["pose"] = ["x_m": pose.position.x, "z_m": pose.position.z,
                                     "height_m": pose.height, "bearing_deg": pose.bearing]
                }
                photoIndex.append(entry)
            }
        }

        // Measurements
        try write(json: location.measurements, to: root.appendingPathComponent("Measurements/measurements.json"))
        var csv = "kind,label,value_m,horizontal_m,vertical_m,source,notes\n"
        for m in location.measurements {
            csv += [m.kind.label, m.label, String(format: "%.3f", m.value),
                    m.horizontal.map { String(format: "%.3f", $0) } ?? "",
                    m.vertical.map { String(format: "%.3f", $0) } ?? "",
                    m.source.label, m.notes].map(csvField).joined(separator: ",") + "\n"
        }
        try csv.write(to: root.appendingPathComponent("Measurements/measurements.csv"), atomically: true, encoding: .utf8)

        // Cameras & shots
        try write(json: location.cameraPositions.map(CameraExport.init), to: root.appendingPathComponent("Camera_Positions/camera_positions.json"))
        try write(json: location.shots.map(ShotExport.init), to: root.appendingPathComponent("Camera_Positions/shots.json"))

        // Notes
        try notesText(project: project, location: location)
            .write(to: root.appendingPathComponent("Notes/notes.txt"), atomically: true, encoding: .utf8)

        // Metadata
        try write(json: location, to: root.appendingPathComponent("Metadata/location.json"))
        var meta: [String: Any] = [
            "format": "FrameScout Location Package",
            "format_version": 1,
            "exported": iso(Date()),
            "project": project.name,
            "location": location.name,
            "address": location.address,
            "tags": location.sortedTags.map(\.label),
            "coordinate_system": [
                "units": "metres",
                "up_axis": "+Y",
                "forward_axis": "-Z",
                "handedness": "right",
                "origin": "Where the scan session started (floor level is floor_plan.json › floorY)",
                "unreal_obj": "Scan/Unreal/*.obj is centimetres, Z up, X forward",
            ],
            "scan_files": scanFiles,
            "photos": photoIndex,
        ]
        if let c = location.coordinate {
            var gps: [String: Any] = ["latitude": c.latitude, "longitude": c.longitude]
            if let alt = c.altitude { gps["altitude_m"] = alt }
            meta["gps"] = gps
        }
        if let scan = location.primaryScan {
            var scanMeta: [String: Any] = [
                "id": scan.id.uuidString, "name": scan.name, "type": scan.kind.rawValue,
                "captured": iso(scan.createdAt), "device": scan.deviceModel, "segments": scan.segmentCount,
                "stats": dictionary(scan.stats),
            ]
            if let n = scan.northOffset {
                scanMeta["true_north_bearing_of_minus_z_deg"] = n
                scanMeta["north_note"] = "Compass-derived, approximate. Rotate the scan by this angle about +Y to align -Z with true north."
            }
            meta["scan"] = scanMeta
        }
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("Metadata/metadata.json"))
    }

    // MARK: Text builders

    static func notesText(project: Project, location: Location) -> String {
        var t = "FRAMESCOUT LOCATION NOTES\n=========================\n\n"
        t += "Project:   \(project.name)\n"
        t += "Location:  \(location.name)\n"
        if !location.address.isEmpty { t += "Address:   \(location.address)\n" }
        if let c = location.coordinate { t += String(format: "GPS:       %.6f, %.6f\n", c.latitude, c.longitude) }
        t += "Scanned:   \(UnitsFormatter.shortDate(location.dateScanned))\n"
        if !location.tags.isEmpty { t += "Tags:      \(location.sortedTags.map(\.label).joined(separator: " · "))\n" }
        if let s = location.primaryScan?.stats {
            t += "\nKEY FIGURES\n"
            t += "Room:      \(UnitsFormatter.dimensions(s.width, s.length))\n"
            t += "Floor:     \(UnitsFormatter.area(s.floorArea))\(s.floorAreaIsEstimate ? " (est.)" : "")\n"
            t += "Ceiling:   \(UnitsFormatter.distance(s.ceilingHeight))\n"
            t += "Doors: \(s.doorCount)   Windows: \(s.windowCount)   Openings: \(s.openingCount)\n"
        }
        func section(_ title: String, _ body: String) {
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            t += "\n\(title.uppercased())\n\(body)\n"
        }
        section("General notes", location.notes)
        section("Lighting notes", location.lightingNotes)
        section("Production notes", location.productionNotes)
        if !location.quickNotes.isEmpty {
            t += "\nSCOUT NOTES\n"
            for n in location.quickNotes { t += "• [\(n.category.label)] \(n.text)\n" }
        }
        if !location.cameraPositions.isEmpty {
            t += "\nCAMERA POSITIONS\n"
            for c in location.cameraPositions {
                t += "• \(c.name): \(c.rig.lensSummary), height \(UnitsFormatter.distance(c.rig.height))"
                t += String(format: ", pan %.0f°, tilt %.0f°", c.rig.pan, c.rig.tilt)
                if !c.notes.isEmpty { t += " — \(c.notes)" }
                t += "\n"
            }
        }
        if !location.shots.isEmpty {
            t += "\nSHOTS\n"
            for s in location.shots.sorted(by: { $0.number < $1.number }) {
                t += "• \(s.code) \(s.title): \(s.rig.lensSummary)"
                if let d = s.subjectDistance { t += ", subject at \(UnitsFormatter.distance(d))" }
                if !s.notes.isEmpty { t += " — \(s.notes)" }
                t += "\n"
            }
        }
        return t
    }

    static func projectSummary(_ project: Project) -> String {
        var t = "PROJECT: \(project.name)\n"
        if !project.client.isEmpty { t += "Client: \(project.client)\n" }
        t += "Exported: \(Date().formatted())\n\n"
        for (i, l) in project.locations.enumerated() {
            let s = l.primaryScan?.stats
            t += String(format: "%03d  ", i + 1) + "\(l.name) — \(UnitsFormatter.dimensions(s?.width, s?.length)), "
            t += "ceiling \(UnitsFormatter.distance(s?.ceilingHeight)), \(l.cameraPositions.count) cameras, \(l.shots.count) shots\n"
        }
        return t
    }

    /// One row per camera/shot in Unreal coordinates (cm; X forward, Y right, Z up).
    /// Paste into a Data Table or use the values on CineCameraActors (Filmback = sensor mm).
    static func unrealCameraCSV(location: Location, scanID: UUID, floorY: Double) -> String {
        var csv = "Name,X_cm,Y_cm,Z_cm,Pitch_deg,Yaw_deg,Roll_deg,FocalLength_mm,SensorWidth_mm,SensorHeight_mm,Notes\n"
        func row(_ name: String, _ rig: CameraRig, _ notes: String) {
            let x = -rig.position.z * 100
            let y = rig.position.x * 100
            let z = (floorY + rig.height) * 100
            let area = rig.imageArea
            csv += [name, String(format: "%.1f", x), String(format: "%.1f", y), String(format: "%.1f", z),
                    String(format: "%.1f", rig.tilt), String(format: "%.1f", rig.pan), "0",
                    String(format: "%.1f", rig.focalLength), String(format: "%.2f", area.width),
                    String(format: "%.2f", area.height), notes].map(csvField).joined(separator: ",") + "\n"
        }
        for c in location.cameraPositions where c.scanID == nil || c.scanID == scanID { row("CAM_" + c.name, c.rig, c.notes) }
        for s in location.shots where s.scanID == nil || s.scanID == scanID { row(s.code.replacingOccurrences(of: " ", with: "_"), s.rig, s.notes) }
        return csv
    }

    static func unrealReadme(scan: ScanRecord) -> String {
        """
        # Bringing this location into Unreal Engine

        Files (all generated on-device by FrameScout from the LiDAR scan):

        | File | Units / axes | Use |
        |---|---|---|
        | `../location.glb` | metres, Y-up (glTF standard) | **Recommended.** Drag into the Content Browser (UE 5.1+ Interchange glTF importer). Hierarchy, materials and cameras import at correct scale. |
        | `../location.usdz` / `.usda` | metres, Y-up (`metersPerUnit = 1`) | Enable the *USD Importer* plugin, then File › Import Into Level, or open with a USD Stage actor. |
        | `location_unreal_cm_zup.obj` | centimetres, Z-up, X forward | Static Mesh import with *Import Uniform Scale* 1.0 and no extra rotation. Groups become separate objects when "Combine Meshes" is off. |
        | `../location.obj` | metres, Y-up | Generic DCC use (Blender, Maya, C4D). In Unreal set Import Uniform Scale to 100. |
        | `cameras_unreal.csv` | cm, degrees | Place CineCameraActors: Location = X/Y/Z, Rotation = Pitch/Yaw, Filmback = sensor width/height, Current Focal Length. |

        Scan type: \(scan.kind.label). \(scan.kind == .room
            ? "Geometry is RoomPlan's parametric reconstruction (clean boxes for walls, openings cut for doors and windows, boxes for furniture). It is untextured by design."
            : "Geometry is the raw LiDAR surface mesh split by ARKit classification (walls, floor, ceiling, seats…). ARKit does not provide textures for this mesh.")

        Tips
        - Set wall/floor materials to a neutral grey to judge light fall-off; glass panes are separate so you can hide them.
        - The world origin is where the scan started. True north: \(scan.northOffset.map { String(format: "Unreal +X points %.1f° clockwise from true north (approximate compass reading); yaw the level by -%.1f° to put north on +X", $0, $0) } ?? "not recorded").
        - For daylight studies use a Directional Light and the Sun Position Calculator plugin with the GPS in metadata.json.
        """
    }

    // MARK: Helpers

    struct CameraExport: Codable {
        var name: String
        var position_m: [Double]
        var height_m: Double
        var pan_deg: Double
        var tilt_deg: Double
        var focal_length_mm: Double
        var sensor: String
        var sensor_mm: [Double]
        var aspect: String
        var horizontal_fov_deg: Double
        var vertical_fov_deg: Double
        var notes: String

        init(_ c: CameraPosition) {
            name = c.name
            position_m = [c.rig.position.x, c.rig.position.z]
            height_m = c.rig.height
            pan_deg = c.rig.pan
            tilt_deg = c.rig.tilt
            focal_length_mm = c.rig.focalLength
            sensor = c.rig.sensor.displayName
            let area = c.rig.imageArea
            sensor_mm = [area.width, area.height]
            aspect = c.rig.aspect.label
            horizontal_fov_deg = c.rig.horizontalFOV
            vertical_fov_deg = c.rig.verticalFOV
            notes = c.notes
        }
    }

    struct ShotExport: Codable {
        var shot: String
        var title: String
        var camera: CameraExport
        var subject_position_m: [Double]?
        var subject_distance_m: Double?
        var notes: String

        init(_ s: Shot) {
            shot = s.code
            title = s.title
            camera = CameraExport(CameraPosition(name: s.code, rig: s.rig, notes: ""))
            subject_position_m = s.subject.map { [$0.x, $0.z] }
            subject_distance_m = s.subjectDistance
            notes = s.notes
        }
    }

    private static func write<T: Encodable>(json value: T, to url: URL) throws {
        try JSONCoding.encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func dictionary<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONCoding.encoder.encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return obj
    }

    private static func csvField(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private static func exportStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }
}
