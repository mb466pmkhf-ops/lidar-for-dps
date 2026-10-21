// Platform-independent tests for FrameScout's core logic (optics, sun, geometry, exporters, ZIP).
// Run with Tests/run_core_tests.sh — works on macOS and Linux (no iOS SDK needed).
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "PASS" : "FAIL", message)
    if !condition { failures += 1 }
}

let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("framescout-core-tests", isDirectory: true)
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let P = { (x: Double, z: Double) in PlanPoint(x: x, z: z) }

// MARK: Optics
check(abs(Optics.fieldOfView(size: 36, focalLength: 50) - 39.598) < 0.01, "50mm full-frame horizontal FOV")
check(abs(Optics.frameSize(atDistance: 5, size: 36, focalLength: 50) - 3.6) < 1e-9, "frame width at 5 m")
check(abs(Optics.distance(toCover: 3.6, size: 36, focalLength: 50) - 5) < 1e-9, "distance for coverage")
let scope = Optics.imageArea(sensor: SensorLibrary.format(id: "generic-ff"), aspect: .r239)
check(abs(scope.width - 36) < 1e-9 && abs(scope.height - 36 / 2.39) < 1e-9, "2.39 frame lines fit sensor width")

// MARK: Viewfinder
let ff = SensorLibrary.format(id: "generic-ff")
let vfTarget = ViewfinderMath.targetFOV(focalLength: 50, sensor: ff, aspect: .sensor, squeeze: 1)
// A phone image whose long side spans exactly the target's horizontal FOV: frame = full width.
let vfImage = ViewfinderMath.Size(width: 1600, height: 1200)
let vfFrame = ViewfinderMath.frameSize(target: vfTarget, image: vfImage, phoneFOV: vfTarget.width)
check(abs(vfFrame.width - 1600) < 1e-6 && abs(vfFrame.width / vfFrame.height - 1.5) < 1e-6, "frame spans image when FOVs match, keeps 3:2")
let vfZoomed = ViewfinderMath.effectiveFOV(baseFOV: 100, zoom: 2)
check(abs(tan(vfZoomed * .pi / 360) - tan(50 * .pi / 180) / 2) < 1e-9, "zoom halves tan(fov/2)")
// Frame width doubles when zoom doubles.
let w1 = ViewfinderMath.frameSize(target: vfTarget, image: vfImage, phoneFOV: ViewfinderMath.effectiveFOV(baseFOV: 110, zoom: 1)).width
let w2 = ViewfinderMath.frameSize(target: vfTarget, image: vfImage, phoneFOV: ViewfinderMath.effectiveFOV(baseFOV: 110, zoom: 2)).width
check(abs(w2 / w1 - 2) < 1e-9, "frame scales linearly with zoom")
let vfFill = ViewfinderMath.fillZoom(target: vfTarget, image: vfImage, baseFOV: 110, fill: 0.9)
let filled = ViewfinderMath.frameSize(target: vfTarget, image: vfImage, phoneFOV: ViewfinderMath.effectiveFOV(baseFOV: 110, zoom: vfFill))
check(abs(max(filled.width / 1600, filled.height / 1200) - 0.9) < 1e-9, "fill zoom fills 90% of the tighter axis")
let wide14 = ViewfinderMath.targetFOV(focalLength: 14, sensor: ff, aspect: .sensor, squeeze: 1)
check(ViewfinderMath.exceedsImage(target: wide14, image: vfImage, baseFOV: 100, minZoom: 1), "14mm FF is wider than a 100° phone image")
check(!ViewfinderMath.exceedsImage(target: vfTarget, image: vfImage, baseFOV: 100, minZoom: 1), "50mm FF fits a 100° phone image")
let ana = ViewfinderMath.imageArea(sensor: SensorLibrary.format(id: "generic-s35-4perf"), aspect: .r239, squeeze: 2)
check(abs(ana.height - 18.66) < 1e-6 && abs(ana.width - 18.66 * 2.39) < 1e-6, "2× anamorphic 4-perf desqueezes to 2.67:1, 2.39 fits the height")
check(ViewfinderMath.prefersWidescreenFormat(target: ViewfinderMath.targetFOV(focalLength: 32, sensor: ff, aspect: .r239, squeeze: 1))
      && !ViewfinderMath.prefersWidescreenFormat(target: ViewfinderMath.targetFOV(focalLength: 32, sensor: ff, aspect: .sensor, squeeze: 1)),
      "16:9 phone format for 2.39, 4:3 for 3:2")
let upright = ViewfinderMath.attitude(gravityX: 0, gravityY: -1, gravityZ: 0)
check(abs(upright.roll) < 1e-9 && abs(upright.tilt) < 1e-9, "portrait upright is level")
let rot = 5 * Double.pi / 180
let cw = ViewfinderMath.attitude(gravityX: sin(rot), gravityY: -cos(rot), gravityZ: 0)
check(abs(cw.roll - 5) < 1e-9, "5° clockwise roll in portrait")
let land = ViewfinderMath.attitude(gravityX: -cos(rot), gravityY: -sin(rot), gravityZ: 0)
check(abs(abs(land.roll) - 5) < 1e-9, "5° roll in landscape")
check(abs(ViewfinderMath.attitude(gravityX: 0, gravityY: 0, gravityZ: -1).tilt + 90) < 1e-9, "flat on a table looks straight down")
check(ViewfinderMath.steppedFocalLength(from: 32, by: 1) == 35 && ViewfinderMath.steppedFocalLength(from: 33, by: -1) == 32
      && ViewfinderMath.steppedFocalLength(from: 135, by: 1) == 135, "focal length stepping")

// MARK: Provenance
var provStats = ScanStats()
check(provStats.provenance(of: .ceilingHeight, kind: .room) == .estimated, "RoomPlan ceiling (tallest wall) is estimated")
check(provStats.provenance(of: .ceilingHeight, kind: .mesh) == .measured, "mesh ceiling (classified triangles) is measured")
check(provStats.provenance(of: .roomSize, kind: .mesh) == .estimated, "mesh room size (bounding box) is estimated")
check(provStats.provenance(of: .floorArea, kind: .room) == .measured, "floor polygon area is measured")
provStats.floorAreaIsEstimate = true
check(provStats.provenance(of: .floorArea, kind: .room) == .estimated, "bounding-box floor area is estimated")
check(provStats.marked("2.74 m", .ceilingHeight, kind: .room) == "≈ 2.74 m"
      && provStats.marked("2.74 m", .ceilingHeight, kind: .mesh) == "2.74 m"
      && provStats.marked("—", .ceilingHeight, kind: .room) == "—", "plain-text estimate marker")
var manualM = DistanceMeasurement(kind: .custom, label: "", value: 2, source: .manual)
check(manualM.provenance == .manual, "manual entry is manual")
manualM.source = .ar
manualM.provenanceOverride = .estimated
check(manualM.provenance == .estimated, "override wins (plane-based AR without LiDAR)")
let legacyJSON = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","kind":"door","label":"Door","value":0.9,"source":"scanAuto","notes":"","createdAt":0}"#
let legacy = try JSONDecoder().decode(DistanceMeasurement.self, from: Data(legacyJSON.utf8))
check(legacy.provenance == .measured && legacy.provenanceOverride == nil, "older project files without provenance still decode")
var provScan = ScanRecord(name: "s", kind: .room, stats: ScanStats(), northOffset: 120, measuredNorthOffset: 120)
check(provScan.northProvenance == .estimated, "compass north is estimated")
provScan.northOffset = 131
check(provScan.northProvenance == .manual, "calibrated north is manual")
provScan.northOffset = nil
check(provScan.northProvenance == nil, "no north, no provenance")

// MARK: Sun (NOAA) — London midsummer: sunrise 04:43, sunset 21:21 BST
let iso = ISO8601DateFormatter()
let noon = iso.date(from: "2024-06-21T12:00:00Z")!
let pos = SolarCalculator.position(date: noon, latitude: 51.5074, longitude: -0.1278)
check(abs(pos.elevation - 62) < 1 && abs(pos.azimuth - 179) < 3, "London solstice noon position")
let london = TimeZone(identifier: "Europe/London")!
let ev = SolarCalculator.events(on: noon, latitude: 51.5074, longitude: -0.1278, timeZone: london)
check(UnitsFormatter.time(ev.sunrise, in: london) == "04:43", "London sunrise \(UnitsFormatter.time(ev.sunrise, in: london))")
check(UnitsFormatter.time(ev.sunset, in: london) == "21:21", "London sunset \(UnitsFormatter.time(ev.sunset, in: london))")
let syd = SolarCalculator.position(date: iso.date(from: "2024-01-15T05:00:00Z")!, latitude: -33.87, longitude: 151.21)
check(syd.azimuth > 250 && syd.azimuth < 290 && syd.elevation > 47 && syd.elevation < 51, "Sydney 4pm summer sun in the west")
check(WindowLight.evaluate(facing: 180, sun: SolarPosition(azimuth: 180, elevation: 30)) > 0.8, "south window lit by southern sun")
check(WindowLight.evaluate(facing: 0, sun: SolarPosition(azimuth: 180, elevation: 30)) == 0, "north window in shade")

// MARK: Plan geometry
check(abs(P(1, 0).worldBearing - 90) < 1e-9 && abs(P(0, 1).worldBearing - 180) < 1e-9, "world bearings")
var plan = FloorPlan()
plan.walls = [PlanSegment(kind: .wall, a: P(-3, -2), b: P(3, -2), height: 2.6, bottom: 0),
              PlanSegment(kind: .wall, a: P(3, -2), b: P(3, 2), height: 2.6, bottom: 0),
              PlanSegment(kind: .wall, a: P(3, 2), b: P(-3, 2), height: 2.6, bottom: 0),
              PlanSegment(kind: .wall, a: P(-3, 2), b: P(-3, -2), height: 2.6, bottom: 0)]
plan.floorPolygons = [[P(-3, -2), P(3, -2), P(3, 2), P(-3, 2)]]
var rig = CameraRig()
rig.position = P(0, 1)
let clear = PlanGeometry.clearances(for: rig, plan: plan)
check(abs(clear.front! - 3) < 1e-9 && abs(clear.behind! - 1) < 1e-9, "clearance in front / behind camera")
check(PlanGeometry.snap(P(2.9, 0.5), plan: plan, tolerance: 0.3).point.x == 3, "snap to wall")
let north = PlanSegment(kind: .window, a: P(-1, -2), b: P(1, -2), height: 1, bottom: 1)
check(plan.outwardBearing(of: north).truncatingRemainder(dividingBy: 360) == 0, "window on -Z wall faces world 0°")

// MARK: Camera orientation (glTF quaternion)
func act(_ q: SIMD4<Float>, _ v: Vec3) -> Vec3 {
    let u = Vec3(q.x, q.y, q.z), s = q.w
    return u * (2 * V3.dot(u, v)) + v * (s * s - V3.dot(u, u)) + V3.cross(u, v) * (2 * s)
}
rig.pan = 90; rig.tilt = 30
let look = act(SceneNode.camera(named: "A", rig: rig, floorY: 0).rotation!, Vec3(0, 0, -1))
check(look.x > 0.86 && abs(look.y - 0.5) < 1e-4, "pan 90° / tilt 30° camera looks east and up")

// MARK: Geometry primitives
let box = SceneMesh.box(center: .zero, axes: (Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)), size: Vec3(2, 2, 2), material: .wall)
var outward = true
for t in stride(from: 0, to: box.indices.count, by: 3) {
    let a = box.positions[Int(box.indices[t])], b = box.positions[Int(box.indices[t + 1])], c = box.positions[Int(box.indices[t + 2])]
    if V3.dot(V3.cross(b - a, c - a), (a + b + c) / 3) <= 0 { outward = false }
}
check(outward && box.triangleCount == 12, "box faces wind outward")
let floor = SceneMesh.horizontalPolygon([(0, 0), (4, 0), (4, 1), (1, 1), (1, 4), (0, 4)], y: 0, facingUp: true, material: .floor)
var area: Float = 0
for t in stride(from: 0, to: floor.indices.count, by: 3) {
    let a = floor.positions[Int(floor.indices[t])], b = floor.positions[Int(floor.indices[t + 1])], c = floor.positions[Int(floor.indices[t + 2])]
    area += V3.length(V3.cross(b - a, c - a)) / 2
}
check(abs(area - 7) < 1e-4, "L-shaped floor triangulates to 7 m²")
let pieces = WallBuilder.solidPieces(width: 4, height: 2.6, holes: [.init(u0: -1.5, u1: -0.6, v0: -1.3, v1: 0.8),
                                                                    .init(u0: 0.5, u1: 1.7, v0: -0.4, v1: 0.8)])
let solid = pieces.reduce(Float(0)) { $0 + $1.width * $1.height }
check(abs(solid - (4 * 2.6 - 0.9 * 2.1 - 1.2 * 1.2)) < 1e-4, "wall minus door and window openings")

// MARK: LiDAR mesh storage + analysis
var mesh = MeshScanData()
func quad(_ y: Float, _ cls: UInt8) {
    let b = UInt32(mesh.positions.count)
    mesh.positions += [Vec3(0, y, 0), Vec3(4, y, 0), Vec3(4, y, 3), Vec3(0, y, 3)]
    mesh.normals += Array(repeating: Vec3(0, 1, 0), count: 4)
    mesh.indices += [b, b + 2, b + 1, b, b + 3, b + 2]
    mesh.faceClasses += [cls, cls]
}
for _ in 0..<12 { quad(0, 2); quad(2.7, 3) }
let decoded = try MeshScanData(data: mesh.encoded())
check(decoded.positions == mesh.positions && decoded.indices == mesh.indices && decoded.faceClasses == mesh.faceClasses, "mesh binary round trip")
check(abs((decoded.analyse().stats.ceilingHeight ?? 0) - 2.7) < 1e-4, "mesh ceiling height")

// MARK: Exporters
let root = SceneNode(name: "FrameScout Location")
root.addChild(SceneNode(name: "Walls")).addChild(SceneNode(name: "Wall 1", mesh: box))
root.addChild(SceneNode(name: "Floors")).addChild(SceneNode(name: "Floor", mesh: floor))
root.addChild(SceneNode(name: "Cameras")).addChild(.camera(named: "CAM A", rig: rig, floorY: 0))
let scene = SceneGeometry(root: root, metadata: ["units": "metres"])
try GLBWriter.write(scene, to: outDir.appendingPathComponent("test.glb"))
try USDAWriter.write(scene, to: outDir.appendingPathComponent("test.usda"))
try USDAWriter.writeUSDZ(scene, to: outDir.appendingPathComponent("test.usdz"))
try OBJWriter.write(scene, to: outDir.appendingPathComponent("test.obj"), unrealUnits: true)
let usda = try String(contentsOf: outDir.appendingPathComponent("test.usda"), encoding: .utf8)
check(usda.contains("metersPerUnit = 1") && usda.contains("upAxis = \"Y\"") && !usda.contains("CAM_A"), "USDA stage metadata, cameras excluded")
let zip = try ZipReader(url: outDir.appendingPathComponent("test.usdz"))
let header = zip.entries[0].localHeaderOffset
let raw = try Data(contentsOf: outDir.appendingPathComponent("test.usdz"))
let dataStart = header + 30 + (Int(raw[header + 26]) | Int(raw[header + 27]) << 8) + (Int(raw[header + 28]) | Int(raw[header + 29]) << 8)
check(dataStart % 64 == 0, "USDZ payload is 64-byte aligned")
check(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926, "CRC-32 check value")

print("Artifacts in \(outDir.path)")
// MARK: Persistence compatibility
let legacyProject = Data(#"{"id":"7D1E3C55-5B55-4C4B-9E3B-0B4E3B6B8C11","name":"Old Job","client":"","notes":"","createdAt":"2025-01-01T10:00:00Z","modifiedAt":"2025-01-02T10:00:00Z","locations":[]}"#.utf8)
let decodedLegacy = try? JSONCoding.decoder.decode(Project.self, from: legacyProject)
check(decodedLegacy?.name == "Old Job" && decodedLegacy?.objects.isEmpty == true, "project saved before objects existed still loads")
var withObject = decodedLegacy ?? Project(name: "x")
withObject.objects = [CapturedObject(name: "Plush", status: .ready, width: 0.2, height: 0.3, depth: 0.1)]
let roundTrip = try? JSONCoding.decoder.decode(Project.self, from: JSONCoding.encoder.encode(withObject))
check(roundTrip?.objects.first?.name == "Plush" && roundTrip?.id == decodedLegacy?.id, "objects round-trip with the project")

// MARK: Object capture (textured GLB / OBJ)
let png1x1 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
let tex = ModelTexture(data: png1x1, mimeType: "image/png")
var plush = TexturedMesh(name: "Plush", material: TexturedMaterial(name: "Plush Mat", baseColor: tex, normal: tex, roughness: tex))
let cube = SceneMesh.box(center: Vec3(0.3, 0.5, -0.2), axes: (Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)), size: Vec3(0.2, 0.3, 0.1), material: .object)
plush.positions = cube.positions
plush.normals = cube.normals
plush.uvs = cube.positions.map { SIMD2(($0.x + 1) / 2, ($0.y + 1) / 2) }
plush.indices = cube.indices
let objModel = TexturedModel(name: "Plush", meshes: [plush], metadata: ["source": "test"]).pivotAtBase()
let ob = objModel.bounds()!
check(abs(ob.min.y) < 1e-6 && abs(ob.min.x + ob.max.x) < 1e-6 && abs(ob.min.z + ob.max.z) < 1e-6, "object pivot moved to base centre")
check(abs(objModel.dimensions.y - 0.3) < 1e-6, "object dimensions")
check(objModel.textures.count == 1, "shared texture stored once")
let objGLB = try TexturedGLBWriter.data(for: objModel)
try objGLB.write(to: outDir.appendingPathComponent("object.glb"))
let objJSONLen = Int(objGLB.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) })
let objJSON = try JSONSerialization.jsonObject(with: objGLB.subdata(in: 20..<(20 + objJSONLen))) as! [String: Any]
let objMat = (objJSON["materials"] as! [[String: Any]])[0]
check((objJSON["images"] as! [Any]).count == 1 && objMat["normalTexture"] != nil
      && (objMat["pbrMetallicRoughness"] as! [String: Any])["metallicFactor"] as! Double == 0, "GLB embeds texture and wires material")
let objOut = TexturedOBJWriter.make(objModel, baseName: "Plush", unrealUnits: true)
check(objOut.obj.contains("vt ") && objOut.mtl.contains("map_Kd Plush_Plush_Mat_BaseColor.png")
      && objOut.textures.count == 1, "OBJ has UVs, MTL references texture files")
let firstFace = objOut.obj.split(separator: "\n").first { $0.hasPrefix("f ") }!
check(firstFace.split(separator: " ").dropFirst().allSatisfy { $0.split(separator: "/").count == 3 }, "OBJ faces carry v/vt/vn")
check(objOut.obj.contains("centimetres"), "OBJ Unreal units header")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
