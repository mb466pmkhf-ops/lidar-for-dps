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
// A central directory whose name runs past the end of the file is rejected, not read out of bounds.
var truncated = raw
let cdStart = (16..<20).reduce(0) { $0 | Int(raw[raw.count - 22 + $1]) << (8 * ($1 - 16)) }
truncated[cdStart + 28] = 0xFF; truncated[cdStart + 29] = 0xFF
check((try? ZipReader(data: truncated)) == nil, "ZIP with an overlong entry name is rejected")
check(StoragePaths.contained("../../Library/x.jpg") == "x.jpg" && StoragePaths.contained("..") == "_"
      && StoragePaths.contained("A.jpg") == "A.jpg", "photo file names stay inside their folder")

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

// MARK: Lighting diagram
let warm = Kelvin.rgb(2700), daylight = Kelvin.rgb(5600), cool = Kelvin.rgb(9000)
check(warm.r == 1 && warm.b < 0.7 && daylight.b > warm.b && cool.b == 1 && cool.r < 1, "Kelvin colours run warm to cool")
var lit = Location(name: "Lit room")
check(lit.lights == nil && lit.lightFixtures.isEmpty, "no lights by default, nothing stored")
var keyLight = LightFixture(name: "Key", kind: .fresnel, position: P(1, 2), pan: 90)
keyLight.power = "1.2K"; keyLight.colorTemperature = 3200; keyLight.dimmer = 0.5
lit.lightFixtures = [keyLight, LightFixture(name: "Neg", kind: .negative, position: P(0, 0))]
let litData = try JSONEncoder().encode(lit)
let litBack = try JSONDecoder().decode(Location.self, from: litData)
check(litBack.lightFixtures == lit.lightFixtures, "lights survive a save/load round trip")
check(keyLight.summary == "Fresnel 1.2K · 3200 K · 50 %", "light summary reads like a plot")
check(!LightKind.negative.emits && LightKind.negative.defaultBeamAngle == 0 && LightKind.fresnel.emits, "grip doesn't emit")
// A location saved before lights existed still loads.
var litJSON = try JSONSerialization.jsonObject(with: litData) as! [String: Any]
litJSON.removeValue(forKey: "lights")
let oldLoc = try JSONDecoder().decode(Location.self, from: JSONSerialization.data(withJSONObject: litJSON))
check(oldLoc.lightFixtures.isEmpty, "location without a lights key decodes")
lit.lightFixtures = []
check(lit.lights == nil, "removing all lights clears the stored list")


// MARK: Photometrics
check(abs(BeamDistribution.lambertian.solidAngleFactor(beamAngle: 0) - .pi) < 1e-12, "lambertian flux = π × peak")
let omega55 = BeamDistribution.beam.solidAngleFactor(beamAngle: 55)
check(omega55 > 0.6 && omega55 < 0.85, "55° beam solid angle ≈ 0.77 sr (\(omega55))")
check(abs(BeamDistribution.beam.relativeIntensity(offAxis: 27.5, beamAngle: 55) - 0.5) < 1e-9, "beam angle is the 50 % point")
check(abs(BeamDistribution.lambertian.relativeIntensity(offAxis: 60, beamAngle: 120) - 0.5) < 1e-9, "lambertian 50 % at 60° off axis")

var cob = LightFixture(name: "Key", kind: .fresnel, position: P(0, 0), pan: 0)
cob.profileID = "cob-300-d"
cob.height = 1.5; cob.tilt = 0
let cobPM = cob.photometrics
check(abs(cobPM.illuminanceOnAxis(at: 3) - 3500) < 3500 * 0.001, "reference reading round-trips (\(cobPM.illuminanceOnAxis(at: 3)) lx at 3 m)")
let ratio36 = cobPM.illuminanceOnAxis(at: 6) / cobPM.illuminanceOnAxis(at: 3)
check(abs(ratio36 - 0.25) < 0.002, "point source follows inverse square (\(ratio36))")
check(cobPM.provenance == .estimated, "library output is an estimate")
var halfCob = cob; halfCob.dimmer = 0.5
check(abs(halfCob.photometrics.illuminanceOnAxis(at: 3) / cobPM.illuminanceOnAxis(at: 3) - 0.5) < 1e-9, "50 % output gives half the lux")
check(halfCob.photometrics.drawWatts < 300 && halfCob.photometrics.drawWatts > 150, "LED draw falls with output")
var offCob = cob; offCob.isOn = false
check(offCob.photometrics.illuminanceOnAxis(at: 3) == 0 && offCob.photometrics.drawWatts == 0, "switched off: no light, no draw")
var soft = cob; soft.modifierID = "softbox-90"
let softPM = soft.photometrics
check(softPM.distribution == .lambertian && abs(softPM.flux / cobPM.flux - 0.5) < 1e-9, "softbox: diffuse, half the flux")
check(softPM.illuminanceOnAxis(at: 3) < cobPM.illuminanceOnAxis(at: 3) / 3, "softbox is far dimmer on axis than the reflector")
// A large soft source falls off slower than inverse square up close.
check(softPM.illuminanceOnAxis(at: 0.5) / softPM.illuminanceOnAxis(at: 1) < 4, "soft source near field is gentler than 1/d²")
var spot = LightFixture(name: "F", kind: .fresnel, position: P(0, 0)); spot.profileID = "fresnel-led-200-bi"
spot.beamAngle = 15
var flood = spot; flood.beamAngle = 50
let spotGain = spot.photometrics.illuminanceOnAxis(at: 5) / flood.photometrics.illuminanceOnAxis(at: 5)
check(spotGain > 3.5 && spotGain < 7, "spotting a fresnel gains about 5× on axis, like published fresnel tables (\(spotGain)×)")
check(abs(spot.photometrics.flux / flood.photometrics.flux - pow(15.0 / 50, 0.85)) < 1e-9, "spotting a fresnel lens loses flux")
var fresnel600 = LightFixture(name: "F6", kind: .fresnel, position: P(0, 0)); fresnel600.profileID = "fresnel-led-600-d"; fresnel600.beamAngle = 60
var cob600 = LightFixture(name: "C6", kind: .fresnel, position: P(0, 0)); cob600.profileID = "cob-600-d"
check(abs(fresnel600.photometrics.illuminanceOnAxis(at: 3) - cob600.photometrics.illuminanceOnAxis(at: 3)) > 500, "same watts, different output")
var tung = LightFixture(name: "T", kind: .fresnel, position: P(0, 0)); tung.profileID = "tungsten-1k"; tung.dimmer = 0.5
check(tung.photometrics.kelvin < 3000 && tung.photometrics.drawWatts > 650, "dimmed tungsten warms and still draws most of its power")
var gelled = cob; gelled.filterIDs = ["cto-full"]
check(gelled.photometrics.kelvin > 2900 && gelled.photometrics.kelvin < 3050
      && abs(gelled.photometrics.flux / cobPM.flux - 0.55) < 1e-9, "full CTO: 5600 K → ≈2960 K, 55 % transmission")
var rgbPanel = LightFixture(name: "R", kind: .ledPanel, position: P(0, 0)); rgbPanel.profileID = "panel-1x1-rgb"
rgbPanel.colorMode = .rgb; rgbPanel.hue = 240; rgbPanel.saturation = 1
var whitePanel = rgbPanel; whitePanel.colorMode = .cct
check(rgbPanel.photometrics.flux < whitePanel.photometrics.flux * 0.15, "saturated blue is much dimmer than white")
var custom = cob; custom.photometricOverride = PhotometricReference(lux: 3000, distance: 3, beamAngle: 55, provenance: .manual)
check(abs(custom.photometrics.illuminanceOnAxis(at: 3) - 3000) < 3, "user data replaces the estimate")
check(custom.photometrics.provenance == .manual, "user data is marked manual")
let oldLightJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LightFixture(name: "Old", kind: .ledPanel, position: P(0, 0)))) as! [String: Any]
check(oldLightJSON["profileID"] == nil, "unset fixture fields aren't written")
let oldLight = try JSONDecoder().decode(LightFixture.self, from: JSONSerialization.data(withJSONObject: oldLightJSON))
check(oldLight.profile.id == "panel-1x1-bi", "lights saved before the library get a default type")

// Library against published tables (see web/tests/photometry-audit.test.ts for the sources): within ⅓ stop.
func stopsOff(_ model: Double, _ published: Double) -> Double { abs(log2(model / published)) }
func fixtureUnit(_ id: String, beam: Double? = nil, modifier: String? = nil) -> ResolvedPhotometrics {
    var l = LightFixture(name: id, kind: FixtureLibrary.profile(id: id)!.kind, position: P(0, 0))
    l.apply(profile: FixtureLibrary.profile(id: id)!)
    if let beam { l.beamAngle = beam }
    l.modifierID = modifier
    return l.photometrics
}
check(stopsOff(fixtureUnit("tungsten-650", beam: 55).illuminanceOnAxis(at: 3), 1194) < 1.0 / 3
      && stopsOff(fixtureUnit("tungsten-650", beam: 30).illuminanceOnAxis(at: 3), 2528) < 1.0 / 3, "650 W fresnel vs published flood/medium")
check(stopsOff(fixtureUnit("tungsten-1k", beam: 55).illuminanceOnAxis(at: 4), 1267) < 1.0 / 3
      && stopsOff(fixtureUnit("tungsten-2k", beam: 55).illuminanceOnAxis(at: 6), 958) < 1.0 / 3, "1 kW / 2 kW fresnels vs published flood")
check(stopsOff(fixtureUnit("cob-600-d", modifier: "none").illuminanceOnAxis(at: 3), 2600) < 1.0 / 3
      && stopsOff(fixtureUnit("cob-1200-d", modifier: "none").illuminanceOnAxis(at: 3), 6380) < 1.0 / 3, "bare COBs vs published")
check(stopsOff(fixtureUnit("hmi-4000-par").illuminanceOnAxis(at: 10), 6500) < 1.0 / 3, "4 kW HMI at 30° vs published")
var refAtSpot = LightFixture(name: "T", kind: .fresnel, position: P(0, 0)); refAtSpot.apply(profile: FixtureLibrary.profile(id: "tungsten-1k")!)
refAtSpot.photometricOverride = PhotometricReference(lux: 5000, distance: 3, beamAngle: 20, provenance: .manual); refAtSpot.beamAngle = 20
check(abs(refAtSpot.photometrics.illuminanceOnAxis(at: 3) - 5000) < 1e-6, "a reading entered at spot on a fresnel round-trips")

// MARK: Lighting calculator
typealias C = LightingCalculator
let facingKey = LightingCalculator.Point(x: 0, y: 0, z: 1)   // receptor faces back towards the light (+Z)
let at3 = LightingCalculator.Point(x: 0, y: 1.5, z: -3)
let oneLight = C.Scene(lights: [cob])
let r3 = C.reading(at: at3, normal: facingKey, scene: oneLight)
check(abs(r3.lux - cobPM.illuminanceOnAxis(at: 3)) < 1, "calculator matches the on-axis figure")
let tilted = LightingCalculator.Point(x: 0, y: sin(30 * Double.pi / 180), z: cos(30 * Double.pi / 180))
let r60 = C.reading(at: at3, normal: LightingCalculator.Point(x: 0, y: sin(60 * Double.pi / 180), z: cos(60 * Double.pi / 180)), scene: oneLight)
check(abs(r60.lux / r3.lux - 0.5) < 1e-6, "cosine law at the receptor")
_ = tilted
let twoLights = C.Scene(lights: [cob, { var b = cob; b.id = UUID(); return b }()])
check(abs(C.reading(at: at3, normal: facingKey, scene: twoLights).lux - 2 * r3.lux) < 1e-6, "overlapping units add up")
// Barn doors: a point 30° right of the axis goes dark when the right door cuts at 10°.
var doored = LightFixture(name: "D", kind: .fresnel, position: P(0, 0)); doored.profileID = "fresnel-led-200-bi"
doored.beamAngle = 50; doored.height = 1.5; doored.tilt = 0
let right30 = LightingCalculator.Point(x: 3 * sin(30 * Double.pi / 180), y: 1.5, z: -3 * cos(30 * Double.pi / 180))
let left30 = LightingCalculator.Point(x: -right30.x, y: 1.5, z: right30.z)
let towardsLight = { (p: LightingCalculator.Point) in (LightingCalculator.Point(x: 0, y: 1.5, z: 0) - p).normalized }
let openRight = C.reading(at: right30, normal: towardsLight(right30), scene: C.Scene(lights: [doored])).lux
doored.barnDoors = BarnDoors(top: 90, bottom: 90, left: 90, right: 10)
let cutRight = C.reading(at: right30, normal: towardsLight(right30), scene: C.Scene(lights: [doored])).lux
let stillLeft = C.reading(at: left30, normal: towardsLight(left30), scene: C.Scene(lights: [doored])).lux
check(openRight > 50 && cutRight < 1e-6 && abs(stillLeft - openRight) < 1e-6, "barn door cuts one side only")
// Walls block; windows pass at the glass transmission.
var room = FloorPlan()
room.walls = [PlanSegment(kind: .wall, a: P(-5, -2), b: P(5, -2), height: 2.7, bottom: 0)]
room.windows = [PlanSegment(kind: .window, a: P(-1, -2), b: P(1, -2), height: 1.5, bottom: 0.8)]
let outside = LightingCalculator.Point(x: 0, y: 1.5, z: -4)
let throughGlass = C.reading(at: outside, normal: facingKey, scene: C.Scene(lights: [cob], plan: room, windowTransmission: 0.78)).lux
let open4 = C.reading(at: outside, normal: facingKey, scene: C.Scene(lights: [cob])).lux
check(abs(throughGlass / open4 - 0.78) < 1e-6, "window passes its transmission")
var lowLight = cob; lowLight.height = 0.3
let lowOutside = LightingCalculator.Point(x: 0, y: 0.3, z: -4)
check(C.reading(at: lowOutside, normal: facingKey, scene: C.Scene(lights: [lowLight], plan: room)).lux == 0, "wall below the sill blocks")
// A flag in the beam blocks; a bounce board sends light back.
var flag = LightFixture(name: "Flag", kind: .flag, position: P(0, -1.5)); flag.height = 1.5; flag.width = 0.6
check(C.reading(at: at3, normal: facingKey, scene: C.Scene(lights: [cob, flag])).lux == 0, "flag in the beam blocks it")
var bounceBoard = LightFixture(name: "Bounce", kind: .bounce, position: P(0, -3), pan: 180); bounceBoard.height = 1.5; bounceBoard.width = 1.2
let behind = LightingCalculator.Point(x: 0.5, y: 1.5, z: -1)
let bounceRead = C.reading(at: behind, normal: LightingCalculator.Point(x: 0, y: 0, z: -1), scene: C.Scene(lights: [cob, bounceBoard]))
check(bounceRead.lux > 1 && bounceRead.contributions.allSatisfy { $0.viaBounce != nil }, "bounce board relights the side facing it (\(Int(bounceRead.lux)) lx)")
// Grip as a second source (D-013). A narrow unit 3 m from a meter, a board half way.
do {
    var spot = LightFixture(name: "Spot", kind: .fresnel, position: P(0, 3)); spot.pan = 0; spot.tilt = 0; spot.height = 1.5; spot.beamAngle = 12
    func board(_ kind: LightKind) -> LightFixture { var b = LightFixture(name: "B", kind: kind, position: P(0, 1.5), pan: 180); b.height = 1.5; b.width = 1.2; b.boardHeight = 1.2; return b }
    let meter = LightingCalculator.Point(x: 0, y: 1.5, z: 0), facingLight = C.direction(bearing: 180, tilt: 0)
    check(C.reading(at: meter, normal: facingLight, scene: C.Scene(lights: [spot, board(.flag)])).lux == 0
          && C.reading(at: meter, normal: facingLight, scene: C.Scene(lights: [spot, board(.negative)])).lux == 0, "flag and neg cut the beam completely")
    let front = LightingCalculator.Point(x: 0.8, y: 1.5, z: 2.2), facingBoard = C.direction(bearing: 311, tilt: 0)
    let flagBack = C.reading(at: front, normal: facingBoard, scene: C.Scene(lights: [spot, board(.flag)]))
    let bounceBack = C.reading(at: front, normal: facingBoard, scene: C.Scene(lights: [spot, board(.bounce)]))
    check(flagBack.lux > 0 && flagBack.contributions.allSatisfy { $0.viaBounce != nil } && abs(flagBack.lux / bounceBack.lux - 0.04 / 0.8) < 1e-6,
          "a flag throws a little light back off its lit side")
    let open = C.reading(at: meter, normal: facingLight, scene: C.Scene(lights: [spot])).lux
    let diffused = C.reading(at: meter, normal: facingLight, scene: C.Scene(lights: [spot, board(.diffusion)]))
    check(diffused.lux > 0 && diffused.lux < open * 0.5 && diffused.contributions.allSatisfy { $0.viaBounce != nil }, "diffusion passes less, all of it scattered")
    let side = LightingCalculator.Point(x: 1.2, y: 1.5, z: 0.3), facingFrame = C.direction(bearing: 140, tilt: 0)
    let bare = C.reading(at: side, normal: facingFrame, scene: C.Scene(lights: [spot])).lux
    let soft = C.reading(at: side, normal: facingFrame, scene: C.Scene(lights: [spot, board(.diffusion)])).lux
    check(soft > bare * 4 + 1, "diffusion spreads the light past the bare beam's edge")
}
check(LightKind.renamed("Negative fill", from: .negative, to: .flag) == "Flag"
      && LightKind.renamed("Neg", from: .negative, to: .bounce) == "Bounce"
      && LightKind.renamed("Neg 2", from: .negative, to: .diffusion) == "Diffusion 2"
      && LightKind.renamed("Diffusion frame 3", from: .diffusion, to: .negative) == "Negative fill 3"
      && LightKind.renamed("Window cutter", from: .flag, to: .negative) == "Window cutter", "changing a grip kind renames its default name only")
// Solve the output for a target.
let solved = C.solveOutput(for: cob, target: 1000, at: at3, normal: facingKey, allLights: [cob], plan: nil)
if case .output(let o) = solved {
    var set = cob; set.dimmer = o
    check(abs(C.reading(at: at3, normal: facingKey, scene: C.Scene(lights: [set])).lux - 1000) < 1, "solved output hits the target")
} else { check(false, "target solve returns an output") }
if case .tooDim(_, let d?) = C.solveOutput(for: cob, target: 20000, at: at3, normal: facingKey, allLights: [cob], plan: nil) {
    check(d < 3, "too dim suggests moving closer (\(d) m)")
} else { check(false, "out-of-reach target reports too dim") }
var hmiKey = LightFixture(name: "H", kind: .hmi, position: P(0, 0)); hmiKey.apply(profile: FixtureLibrary.profile(id: "hmi-1800-par")!)
hmiKey.height = 1.5; hmiKey.tilt = 0
if case .atMinimum(let o, let lux) = C.solveOutput(for: hmiKey, target: 1000, at: at3, normal: facingKey, allLights: [hmiKey], plan: nil) {
    var half = hmiKey; half.dimmer = 0.5
    check(o == 0.5 && abs(lux - C.reading(at: at3, normal: facingKey, scene: C.Scene(lights: [half])).lux) < 1e-6,
          "an HMI that can't dim low enough says so (\(Int(lux)) lx at 50 %)")
} else { check(false, "an HMI that can't dim low enough says so") }
let grid = C.grid(bounds: PlanRect(minX: -2, minZ: -4, maxX: 2, maxZ: 0), columns: 8, rows: 8, height: 1.5,
                  scene: oneLight, normal: { towardsLight($0) })
check(grid.count == 64 && grid.max()! > grid.min()!, "lux map grid")

// MARK: Exposure
var exp = ExposureSettings()
check(abs(exp.exposureTime - 1.0 / 48) < 1e-12, "180° at 24 fps is 1/48 s")
check(abs(exp.keyLux - 250 * 2.8 * 2.8 * 48 / 800) < 1e-9, "key lux for ISO 800, 1/48, T2.8 (\(exp.keyLux))")
check(abs(exp.tStop(forLux: exp.keyLux) - 2.8) < 1e-9 && abs(exp.stops(forLux: exp.keyLux * 2) - 1) < 1e-9, "lux ↔ stop round trip")
check(abs(exp.fStop - 2.8 * 0.85.squareRoot()) < 1e-12, "f-stop from T-stop and transmission")
let key0 = exp.keyLux
exp.ndStops = 2
check(abs(exp.keyLux / key0 - 4) < 1e-9, "ND 0.6 needs four times the light")
exp.ndStops = 0; exp.shutterSeconds = 1.0 / 100
check(abs(exp.exposureTime - 0.01) < 1e-12 && exp.shutterDescription == "1/100", "shutter speed mode")
check(ExposureSettings.stopLabel(2.8) == "T2.8" && ExposureSettings.stopLabel(3.17) == "T2.8 +⅓"
      && ExposureSettings.stopLabel(3.56) == "T4 −⅓" && ExposureSettings.stopLabel(5.6) == "T5.6", "stop labels in thirds")
check(ExposureSettings.stopLabel(64) == "T64" && ExposureSettings.stopLabel(128) == "T128" && ExposureSettings.stopLabel(0.7) == "T0.71"
      && ExposureSettings.stopLabel(0.125) == "T0.13" && ExposureSettings.stopLabel(0.25) == "T0.25" && ExposureSettings.stopLabel(0.004) == "under T0.13",
      "stop labels past T64 and under T1")
check(abs(ExposureSettings().keyLux - 117.6) < 1e-9 && abs({ var e = ExposureSettings(); e.iso = 100; return e.keyLux }() - 940.8) < 1e-9,
      "key lux by hand: ISO 800 → 117.6 lx, ISO 100 → 940.8 lx at T2.8, 1/48")
check(ExposureSettings.stopsDelta(1.34) == "+1⅓" && ExposureSettings.stopsDelta(-0.66) == "−⅔"
      && ExposureSettings.stopsDelta(0.05) == "±0", "stop differences in thirds")
var expJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ExposureSettings())) as! [String: Any]
expJSON.removeValue(forKey: "ndStops")
check((try JSONDecoder().decode(ExposureSettings.self, from: JSONSerialization.data(withJSONObject: expJSON))).ndStops == 0, "exposure decodes with keys missing")

// MARK: People, meters, display
var maya = PrevisCharacter(name: "Maya", type: .woman, position: P(0, 1))
check(abs(maya.eyeHeight / maya.height - 0.936) < 0.01, "adult eye height ≈ 94 % of height")
let standingEye = maya.eyeHeight
maya.posture = .sitting
check(maya.eyeHeight < standingEye - 0.4 && maya.eyeHeight > 1.0, "sitting lowers the eyes")
let kid = PrevisCharacter(name: "Sam", type: .boy, position: P(0, 0))
check(kid.proportions.headHeight / kid.height > maya.proportions.headHeight / maya.height, "children have bigger heads for their height")
var broad = maya; broad.build = 1
check(broad.proportions.shoulderWidth > maya.proportions.shoulderWidth, "build widens the figure")
let mayaBack = try JSONDecoder().decode(PrevisCharacter.self, from: JSONEncoder().encode(maya))
check(mayaBack == maya, "person round trip")
check((try JSONDecoder().decode(PrevisCharacter.self, from: Data(#"{"name":"X","type":"girl","position":{"x":1,"z":2}}"#.utf8))).height == CharacterType.girl.defaultHeight, "person decodes with defaults")
// Same cases as web/tests/characters.test.ts.
let sam = PrevisCharacter(name: "Sam", type: .universal, position: P(0, 0))
check(!CharacterType.universal.isChild && sam.height > CharacterType.woman.defaultHeight && sam.height < CharacterType.man.defaultHeight, "universal adult sits between man and woman")
check(abs(sam.eyeHeight / sam.height - 0.936) < 0.01, "universal eye height")
check(sam.proportions.shoulderWidth / sam.height < PrevisCharacter(name: "M", type: .man, position: P(0, 0)).proportions.shoulderWidth / CharacterType.man.defaultHeight, "universal shoulders narrower than the man's")
check(sam.hairStyle == .cropped && sam.hair == nil, "hair follows the type until set")
var samLong = sam; samLong.hair = .long
check((try JSONDecoder().decode(PrevisCharacter.self, from: JSONEncoder().encode(samLong))) == samLong, "hair round trip")
let future = try JSONDecoder().decode(PrevisCharacter.self, from: Data(#"{"name":"X","type":"robot","hair":"mohawk","position":{"x":0,"z":0}}"#.utf8))
check(future.type == .universal && future.hairStyle == .cropped, "unknown type and hair fall back instead of failing the location")
var previs = Location(name: "Previs")
previs.previsCharacters = [maya]
previs.lightMeters = [LightMeter(name: "M1", position: P(0, -3))]
var shotRig = CameraRig(); shotRig.position = P(0, 3); shotRig.pan = 0
previs.shots = [Shot(number: 1, rig: shotRig)]
let points = previs.meterPoints(scanID: nil)
check(points.count == 2, "meters plus a face per person")
let face = points.first { if case .character = $0.source { return true }; return false }!
check(face.normal.z > 0.9, "face meter points at the camera")
var disp = SceneDisplay()
let sofaID = UUID()
disp.setHidden(category: "Sofa", true)
check(disp.isHidden(object: sofaID, category: "sofa") && !disp.isHidden(object: UUID(), category: "Table"), "hide a category")
disp.setHidden(category: "Sofa", false); disp.setHidden(item: SceneItemKey.object(sofaID), true)
check(disp.isHidden(object: sofaID, category: "Sofa") && disp.hiddenGroups == nil, "hide one piece")
disp.setLabels(.objects, shown: false)
check(!disp.showsLabels(.objects) && disp.showsLabels(.lights), "labels hide separately from objects")
previs.displaySettings = SceneDisplay()
check(previs.display == nil, "default display isn't stored")
previs.displaySettings = disp
let previsBack = try JSONDecoder().decode(Location.self, from: JSONEncoder().encode(previs))
check(previsBack == previs, "location with people, meters and display settings round-trips")
// Levelling turns a tilted floor normal straight up.
let tiltedNormal = (x: sin(3 * Double.pi / 180), y: cos(3 * Double.pi / 180) * cos(2 * Double.pi / 180), z: cos(3 * Double.pi / 180) * sin(2 * Double.pi / 180))
let lev = ScanAlignment.levelling(floorNormal: tiltedNormal)
do {
    let r = lev.roll * Double.pi / 180, p = lev.pitch * Double.pi / 180
    let x1 = tiltedNormal.x * cos(r) - tiltedNormal.y * sin(r), y1 = tiltedNormal.x * sin(r) + tiltedNormal.y * cos(r)
    let z2 = y1 * sin(p) + tiltedNormal.z * cos(p)
    check(abs(x1) < 1e-9 && abs(z2) < 1e-9, "levelling angles put the floor normal straight up (\(lev))")
}

// MARK: Plan-built 3D
var demoPlan = FloorPlan()
demoPlan.walls = [P(-3, -2), P(3, -2), P(3, 2), P(-3, 2)].enumerated().map { i, a in
    let corners = [P(-3, -2), P(3, -2), P(3, 2), P(-3, 2)]
    return PlanSegment(kind: .wall, a: a, b: corners[(i + 1) % 4], height: 2.7, bottom: 0)
}
demoPlan.windows = [PlanSegment(kind: .window, a: P(-1, -2), b: P(1, -2), height: 1.4, bottom: 0.8)]
demoPlan.floorPolygons = [[P(-3, -2), P(3, -2), P(3, 2), P(-3, 2)]]
demoPlan.objects = [PlanObject(category: "Sofa", center: P(0, 1), width: 2, depth: 0.9, height: 0.8, rotation: 0)]
demoPlan.floorY = -1.2
let planScene = PlanSceneBuilder.sceneGeometry(demoPlan)
var wallPieces = 0, sawWindow = false, sawSofa = false
planScene.root.walk { node, _, _ in
    if node.info["category"] == "wall" { wallPieces += (node.mesh?.triangleCount ?? 0) / 12 }
    if node.info["category"] == "window" { sawWindow = true }
    if node.info["id"] == demoPlan.objects[0].id.uuidString { sawSofa = true }
}
check(wallPieces >= 6 && sawWindow && sawSofa, "plan-built 3D: walls with a window hole, pane, set piece keeps its id")
if let floor = planScene.floorEstimate() {
    check(floor.normal.y > 0.999 && abs(floor.height - -1.2) < 0.03, "floor estimate is level at the plan floor")
} else { check(false, "floor estimate found") }

// MARK: Lighting setups
do {
    var person = PrevisCharacter(name: "Maya", type: .woman, position: P(0, 1), facing: 0)
    person.scanID = nil
    var exp = ExposureSettings(); exp.iso = 800; exp.tStop = 2.8
    let setup = LightingSetup.threePoint.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    check(setup.lights.count == 3 && setup.notes.count == 3, "three-point builds key, fill and back")
    let inside = setup.lights.allSatisfy { abs($0.position.x) < 3 && abs($0.position.z) < 2 }
    check(inside, "setup units stay inside the room (\(setup.lights.map(\.position)))")
    let scene = LightingCalculator.Scene(lights: setup.lights, plan: demoPlan)
    let face = LightingCalculator.Point(person.position, height: person.eyeHeight - 0.03)
    let toCam = LightingCalculator.direction(bearing: 0, tilt: 0)
    let r = LightingCalculator.reading(at: face, normal: toCam, scene: scene)
    let keyID = setup.lights[0].id, fillID = setup.lights[1].id
    let keyLux = r.contributions.filter { $0.lightID == keyID }.reduce(0) { $0 + $1.lux }
    let fillLux = r.contributions.filter { $0.lightID == fillID }.reduce(0) { $0 + $1.lux }
    check(abs(log2(keyLux / exp.keyLux)) < 0.2, "key solved to the camera's key level (\(keyLux) vs \(exp.keyLux))")
    check(fillLux > 0 && abs(log2(keyLux / fillLux) - 2) < 0.4, "fill about two stops under key (\(keyLux) / \(fillLux))")
    let soft = LightingSetup.softSide.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    check(soft.lights.contains { $0.kind == .negative }, "soft side light adds a neg fill")
    for kind in LightingSetup.allCases {
        let built = kind.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
        let lit = LightingCalculator.reading(at: face, normal: toCam, scene: LightingCalculator.Scene(lights: built.lights, plan: demoPlan))
        let k = lit.contributions.filter { $0.lightID == built.lights[0].id }.reduce(0) { $0 + $1.lux }
        check(abs(log2(k / exp.keyLux)) < 0.2, "\(kind.label): key solved to the camera's key level (\(k))")
    }
    let edge = LightingSetup.keyAndEdge.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    check(edge.lights.count == 2 && edge.lights[1].role == .edge, "key and edge places a soft key and an edge light")
}

// MARK: Lighting presets (same cases as web/tests/presets.test.ts)
do {
    let person = PrevisCharacter(name: "Maya", type: .woman, position: P(0, 1), facing: 0)
    var exp = ExposureSettings(); exp.iso = 800; exp.tStop = 2.8
    func faceLux(_ lights: [LightFixture], _ id: UUID, _ who: PrevisCharacter, _ bearing: Double, _ e: ExposureSettings = exp) -> Double {
        let face = LightingCalculator.Point(who.position, height: who.eyeHeight - 0.03)
        return LightingCalculator.reading(at: face, normal: LightingCalculator.direction(bearing: bearing, tilt: 0),
                                          scene: LightingCalculator.Scene(lights: lights, plan: demoPlan))
            .contributions.filter { $0.lightID == id }.reduce(0) { $0 + $1.lux }
    }
    let original = LightingSetup.threePoint.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    let preset = LightingPreset.capture(name: "My three-point", lights: original.lights, person: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    check(preset.units.map(\.light.name) == ["Key", "Fill", "Back"], "preset keeps unit names without the person (\(preset.units.map(\.light.name)))")
    check(preset.units[0].angle > 0 && abs((preset.units[1].stopsUnderKey ?? 9) - 2) < 0.5, "preset saves the key on + and the fill ≈ 2 stops under")
    let again = preset.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    func sameUnit(_ a: LightFixture, _ b: LightFixture) -> Bool {
        let near: Bool = a.position.distance(to: b.position) < 0.02
        let level: Bool = abs(a.height - b.height) < 0.02
        let named: Bool = a.name == b.name
        let unit: Bool = a.profileID == b.profileID
        return near && level && named && unit
    }
    let same = Swift.zip(again.lights, original.lights).allSatisfy { sameUnit($0, $1) }
    check(again.lights.count == 3 && same, "saved three-point used again lands where it was")
    check(abs(log2(faceLux(again.lights, again.lights[0].id, person, 0) / exp.keyLux)) < 0.2, "used again, the key is at the set stop")

    let mine = LightingPreset.capture(name: "Mine", lights: LightingSetup.keyAndEdge.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan).lights,
                                      person: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    var leo = PrevisCharacter(name: "Leo", type: .man, position: P(1.5, 0), facing: 270)
    leo.scanID = nil
    var brighter = exp; brighter.tStop = 4
    let moved = mine.build(for: leo, camera: P(-1.5, 0), exposure: brighter, plan: demoPlan)
    check(moved.lights.map(\.name) == ["Key · Leo", "Edge · Leo"], "preset names units after the new person")
    check(moved.lights.allSatisfy { l in abs(l.position.x) < 3 && abs(l.position.z) < 2 }, "preset units stay inside the room")
    check(abs(log2(faceLux(moved.lights, moved.lights[0].id, leo, 270) / brighter.keyLux)) < 0.2, "preset follows the person, camera and stop")

    let single = LightingPreset.capture(name: "Side", lights: LightingSetup.hardSingle.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan).lights,
                                        person: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    var nearWall = person; nearWall.position = P(2.4, 0)
    let auto = single.build(for: nearWall, camera: P(2.4, -1.8), exposure: exp, plan: demoPlan).lights[0]
    var keep = single; keep.keepSides = true
    let kept = keep.build(for: nearWall, camera: P(2.4, -1.8), exposure: exp, plan: demoPlan).lights[0]
    let mirroredAway: Bool = auto.position.x < 2.4
    check(mirroredAway && kept.position.x > auto.position.x, "preset mirrors to the roomier side unless sides are kept")

    let w = demoPlan.windows[0]
    let out = demoPlan.outwardBearing(of: w)
    let dir = PlanPoint.unit(bearing: out)
    var sun = LightFixture(name: "Sun", kind: .hmi, position: w.midpoint + dir * 3, pan: (out + 180).truncatingRemainder(dividingBy: 360))
    sun.height = 3; sun.tilt = -25; sun.dimmer = 0.8
    let bounce = LightFixture(name: "Bounce", kind: .bounce, position: w.midpoint + dir * -0.5, pan: out)
    let windowPreset = LightingPreset.capture(name: "Sun through window", lights: [sun, bounce], window: w, plan: demoPlan)
    let outOK: Bool = abs(windowPreset.units[0].out - 3) < 0.01
    let aimOK: Bool = abs(windowPreset.units[0].panOffset) < 0.1
    let insideOK: Bool = abs(windowPreset.units[1].out + 0.5) < 0.01
    check(outOK && aimOK && insideOK,
          "window preset saves out from the glass and aim (\(windowPreset.units.map(\.out)))")
    let atWindow = windowPreset.build(at: w, plan: demoPlan, scanID: nil)
    let placed = atWindow.lights[0]
    let placedOK: Bool = placed.position.distance(to: sun.position) < 0.02
    check(placedOK && placed.dimmer == 0.8 && placed.tilt == -25,
          "window preset used again lands where it was, at its dimmer")
    let viaPerson = windowPreset.build(for: person, camera: P(0, -1.5), exposure: exp, plan: demoPlan)
    let noWindow = windowPreset.build(for: person, camera: nil, exposure: exp, plan: nil)
    let saysSo: Bool = noWindow.notes.first?.contains("needs a window") == true
    check(viaPerson.lights.count == 2 && saysSo,
          "window preset from a person uses the nearest window, or says it needs one")

    let text = LightingPreset.encode([mine])
    check(LightingPreset.decode(text) == [mine], "presets round-trip through the shared JSON")
    check(LightingPreset.decode("hello") == nil, "presets refuse other text")
    let fromWeb = #"{"framescanPresets":1,"presets":[{"id":"5f0c2a5e-8a7b-4f4e-9a40-1d2b3c4d5e6f","name":"Web","anchor":"person","keepSides":false,"units":[{"light":{"id":"0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d","name":"Key","kind":"fresnel","position":{"x":0,"z":0},"height":2,"pan":0,"tilt":-20,"beamAngle":35,"width":0.3,"power":"","colorTemperature":5600,"gel":"","modifier":"","dimmer":1,"isOn":true,"notes":""},"angle":45,"distance":2,"rise":0.5,"along":0,"out":0,"height":1.5,"panOffset":0,"stopsUnderKey":0}]}]}"#
    check(LightingPreset.decode(fromWeb)?.first?.units.first?.angle == 45, "a preset copied from the planner opens on the phone")
}

// MARK: Sync merge (same cases as web/tests/merge.test.ts)
do {
    func j(_ s: String) -> Any { try! JSONSerialization.jsonObject(with: Data(s.utf8)) }
    let base = j(#"{"id":"P","name":"Shoot","modifiedAt":"2026-11-01T10:00:00Z","locations":[{"id":"L1","lights":[{"id":"A","dimmer":1},{"id":"B","name":"Fill","dimmer":0.5}]}]}"#)
    let phone = j(#"{"id":"P","name":"Phone","modifiedAt":"2026-11-02T10:00:00Z","locations":[{"id":"L1","lights":[{"id":"A","dimmer":0.7},{"id":"B","name":"Fill","dimmer":0.5},{"id":"C","dimmer":1}]}]}"#)
    let web = j(#"{"id":"P","name":"Web","modifiedAt":"2026-11-01T12:00:00Z","locations":[{"id":"L1","lights":[{"id":"A","dimmer":1},{"id":"D","dimmer":1},{"id":"B","name":"Fill (bounce)","dimmer":0.5}]}]}"#)
    let m = SyncMerge.merge(base: base, local: web, remote: phone) as! [String: Any]
    let lights = ((m["locations"] as! [[String: Any]])[0]["lights"] as! [[String: Any]])
    check(lights.map { $0["id"] as! String } == ["A", "D", "B", "C"], "sync merge keeps lights added on both sides, in place")
    check((lights[0]["dimmer"] as! Double) == 0.7 && (lights[2]["name"] as! String) == "Fill (bounce)", "sync merge keeps edits to different lights")
    check((m["name"] as! String) == "Web" && (m["modifiedAt"] as! String) == "2026-11-02T10:00:00Z", "sync merge: local wins a clash, modifiedAt takes the later")
    let deleted = j(#"{"id":"P","name":"Shoot","modifiedAt":"2026-11-01T10:00:00Z","locations":[{"id":"L1","lights":[{"id":"B","name":"Fill","dimmer":0.5}]}]}"#)
    let changedA = j(#"{"id":"P","name":"Shoot","modifiedAt":"2026-11-01T10:00:00Z","locations":[{"id":"L1","lights":[{"id":"A","dimmer":0.2},{"id":"B","name":"Fill","dimmer":0.5}]}]}"#)
    let kept = SyncMerge.merge(base: base, local: changedA, remote: deleted) as! [String: Any]
    let keptIDs = (((kept["locations"] as! [[String: Any]])[0]["lights"] as! [[String: Any]])).map { $0["id"] as! String }
    check(keptIDs == ["A", "B"], "sync merge keeps an item deleted on one side but changed on the other")
    let p = try SyncMerge.project(from: SyncMerge.jsonObject(Project(name: "Round trip")))
    check(p.name == "Round trip", "project survives the JSON round trip used by sync")
} catch {
    check(false, "sync merge: \(error)")
}

// MARK: Web parity
// web/tests/fixtures/parity-bundle.json is a project written by the web planner. Decoding it proves
// the phone can read web edits; the readings are compared with the TypeScript port by
// web/tests/parity.test.ts (CI passes this file to it as PARITY_READINGS).
struct WebBundle: Decodable { var project: Project; var plans: [String: FloorPlan] }
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: "web/tests/fixtures/parity-bundle.json"))
    let bundle = try JSONCoding.decoder.decode(WebBundle.self, from: data)
    check(true, "web-written project decodes in Swift")
    let loc = bundle.project.locations[0]
    let scanID = loc.primaryScanID
    let plan = scanID.flatMap { bundle.plans[$0.uuidString] }
    let lights = loc.lightFixtures.filter { $0.scanID == nil || $0.scanID == scanID }
    let scene = LightingCalculator.Scene(lights: lights, plan: plan, windowTransmission: loc.displaySettings.windowTransmissionValue)
    var readings: [String: Double] = [:]
    for m in loc.meterPoints(scanID: scanID) {
        let key: String
        switch m.source {
        case .meter(let id): key = "m:" + id.uuidString
        case .character(let id): key = "c:" + id.uuidString
        }
        readings[key] = LightingCalculator.reading(at: m.point, normal: m.normal, scene: scene).lux
    }
    let gridValues = LightingCalculator.grid(bounds: plan?.bounds ?? .unit, columns: 12, rows: 10, height: 1.5, scene: scene) { _ in
        LightingCalculator.Point(x: 0, y: 1, z: 0)
    }
    check(readings.count >= 3 && plan != nil, "parity fixture has a plan and meter points")
    let json = try JSONSerialization.data(withJSONObject: ["readings": readings, "grid": gridValues])
    try json.write(to: outDir.appendingPathComponent("parity-readings.json"))
} catch {
    check(false, "web-written project decodes in Swift: \(error)")
}

// MARK: Studio builds, daylight and curtains (same cases as web/tests/stage.test.ts)
do {
    let zen = Stage.daylightLevels(.clear, elevation: 90)
    check(zen.directNormal > 95000 && zen.directNormal < 110000, "clear-sky sun at the zenith ≈ 100 klx")
    check(Stage.daylightLevels(.overcast, elevation: 50).directNormal == 0, "no direct sun under overcast")
    check(abs(Stage.daylightLevels(.clear, elevation: -3).skyHorizontal - 400) < 1e-6, "twilight fades the sky")
    var london = Location(name: "London")
    london.coordinate = GeoCoordinate(latitude: 51.5074, longitude: -0.1278)
    let noon = SolarCalculator.position(date: Date(timeIntervalSince1970: 1718971320), latitude: 51.5074, longitude: -0.1278)
    check(noon.elevation > 61.4 && noon.elevation < 62.4 && abs(noon.azimuth - 180) < 3, "midsummer noon sun in London")
    london.daylight = DaylightSetup(isOn: true, fromClock: true, time: 1718971320)
    let northless = ScanRecord(name: "s", kind: .room, stats: ScanStats())
    check(!Stage.sunPlacement(london, scan: northless).fromClock, "no north: the sun stays where it was put")

    // The drawn room's window is on the top wall, so a sun at plan bearing 0 shines in through it.
    let room = DrawnRoom(shape: .box, length: 6, width: 4.5, ceiling: 2.7, windows: 1, door: false).plan
    var lit = Location(name: "Sun")
    lit.daylight = DaylightSetup(isOn: true, sky: .clear, sunBearing: 0, sunElevation: 30)
    func lux(_ l: Location, _ plan: FloorPlan, _ p: LightingCalculator.Point, _ n: LightingCalculator.Point, _ id: UUID? = nil) -> Double {
        let r = LightingCalculator.reading(at: p, normal: n, scene: .init(lights: l.lightFixtures, plan: plan, windowTransmission: 0.78,
                                                                           environment: l.environment(plan: plan, scan: nil)))
        return id.map { id in r.contributions.filter { $0.lightID == id }.reduce(0) { $0 + $1.lux } } ?? r.lux
    }
    let near = LightingCalculator.Point(x: 0, y: 1.2, z: -1.2), toWindow = LightingCalculator.Point(x: 0, y: 0, z: -1)
    let sun = lux(lit, room, near, toWindow, Stage.sunID)
    check(abs(sun - Stage.daylightLevels(.clear, elevation: 30).directNormal * cos(.pi / 6) * 0.78) < 1e-6 * sun, "sun beam through bare glass")
    let sky = lux(lit, room, near, toWindow, Stage.skyID)
    check(sky > 200 && sky < 5000, "sky light through the window")
    check(lux(lit, room, LightingCalculator.Point(x: 0, y: 1.2, z: 1.8), toWindow, Stage.sunID) == 0, "the sun stops where the window can't reach")
    var high = lit
    high.daylight?.sunElevation = 85
    check(lux(high, room, LightingCalculator.Point(x: 0, y: 1, z: 0), LightingCalculator.Point(x: 0, y: 1, z: 0), Stage.sunID) == 0, "no sun through the ceiling")
    var sheer = room
    sheer.windows = sheer.windows.map { var w = $0; w.curtain = .sheer; return w }
    check(lux(lit, sheer, near, toWindow, Stage.sunID) == 0 && lux(lit, sheer, near, toWindow, Stage.skyID) > sky, "a sheer turns the sun into a glow")
    var black = room
    black.windows = black.windows.map { var w = $0; w.curtain = .blackout; return w }
    check(lux(lit, black, near, toWindow) == 0, "blackout stops daylight")

    // LED wall
    var led = Location(name: "Volume")
    led.studio = StudioSetup(backdrop: "led-wall", wallID: room.walls[0].id, width: 6, height: 2.7, nits: 300)
    let e = lux(led, room, LightingCalculator.Point(x: 0, y: 1.5, z: -0.25), toWindow, Stage.ledWallID)
    check(e > 250 && e < 800, "an LED wall lights the subject (\(e))")
    var paper = Location(name: "Paper")
    paper.studio = StudioSetup(backdrop: "paper-white", wallID: room.walls[0].id)
    check(lux(paper, room, LightingCalculator.Point(x: 0, y: 1.5, z: -0.25), toWindow) == 0, "paper gives no light")
    check(Set(Stage.backdrops.map(\.id)).count == Stage.backdrops.count, "backdrop ids are unique")
}

// MARK: Web parity, studio and daylight (web/tests/stage.test.ts, STAGE_READINGS)
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: "web/tests/fixtures/stage-bundle.json"))
    let bundle = try JSONCoding.decoder.decode(WebBundle.self, from: data)
    let loc = bundle.project.locations[0]
    let scanID = loc.primaryScanID
    let plan = scanID.flatMap { bundle.plans[$0.uuidString] }
    let scan = loc.scans.first { $0.id == scanID }
    check(plan?.windows.first?.curtain == .sheer && loc.studio?.backdrop == "led-wall", "web-written curtains and studio decode in Swift")
    let lights = loc.lightFixtures.filter { $0.scanID == nil || $0.scanID == scanID }
    let scene = LightingCalculator.Scene(lights: lights, plan: plan, windowTransmission: loc.displaySettings.windowTransmissionValue,
                                         environment: loc.environment(plan: plan, scan: scan))
    var readings: [String: Double] = [:]
    for m in loc.meterPoints(scanID: scanID) {
        let key: String
        switch m.source {
        case .meter(let id): key = "m:" + id.uuidString
        case .character(let id): key = "c:" + id.uuidString
        }
        readings[key] = LightingCalculator.reading(at: m.point, normal: m.normal, scene: scene).lux
    }
    let sun = Stage.sunPlacement(loc, scan: scan)
    check(sun.fromClock, "stage fixture places the sun from the clock")
    let json = try JSONSerialization.data(withJSONObject: ["readings": readings, "sunBearing": sun.bearing, "sunElevation": sun.elevation])
    try json.write(to: outDir.appendingPathComponent("stage-readings.json"))
} catch {
    check(false, "stage fixture: \(error)")
}

// MARK: Photometrics matrix (same cases as web/tests/support/matrix.ts)
// Every fixture × modifier × beam × filters × dimmer and a spread of exposures, written for
// web/tests/photometry-audit.test.ts (CI passes this file to it as PHOTOMETRICS_MATRIX).
do {
    func key(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : "\(v)" }
    let filterSets: [[String]] = [[], ["cto-full"], ["diff-light"], ["diff-medium", "ctb-half"], ["diff-heavy", "nd-6"]]
    var matrix: [String: [Double]] = [:]
    for p in FixtureLibrary.profiles {
        let mods: [String?] = [nil, "none"] + FixtureLibrary.modifiers(for: p).map(\.id)
        for mod in mods { for beam in [12.0, 30, 60] { for (fi, filters) in filterSets.enumerated() {
            for dimmer in [1.0, 0.37] { for rgb in (p.color.rgb ? [false, true] : [false]) {
                var l = LightFixture(name: "M", kind: p.kind, position: P(0, 0))
                l.apply(profile: p)
                l.modifierID = mod
                l.beamAngle = beam; l.colorTemperature = 4300; l.dimmer = dimmer
                if !filters.isEmpty { l.filterIDs = filters }
                if rgb { l.colorMode = .rgb; l.hue = 200; l.saturation = 0.7 }
                let pm = l.photometrics
                let k = [p.id, mod ?? "-", key(beam), String(fi), key(dimmer), rgb ? "rgb" : "w"].joined(separator: "|")
                matrix[k] = [pm.peakIntensity, pm.flux, pm.beamAngle, pm.kelvin, pm.drawWatts] + [0.5, 1, 3, 7].map { pm.illuminanceOnAxis(at: $0) }
            } }
        } } }
    }
    var exposures: [String: [Any]] = [:]
    let shutters: [(Double, Double, Double?)] = [(24, 180, nil), (25, 172.8, nil), (23.976, 90, nil), (24, 180, 1.0 / 125)]
    for iso in [100.0, 800, 3200] { for (si, sh) in shutters.enumerated() { for nd in [0.0, 2] { for lux in [3.0, 117, 1000, 250000] {
        var e = ExposureSettings()
        e.iso = iso; e.frameRate = sh.0; e.shutterAngle = sh.1; e.shutterSeconds = sh.2; e.ndStops = nd; e.tStop = 4
        let t = e.tStop(forLux: lux), st = e.stops(forLux: lux)
        exposures[[key(iso), String(si), key(nd), key(lux)].joined(separator: "|")] =
            [e.keyLux, t, st, ExposureSettings.stopLabel(t), ExposureSettings.stopsDelta(st)]
    } } } }
    check(matrix.count > 2000 && matrix.values.allSatisfy { $0.allSatisfy(\.isFinite) }, "photometrics matrix (\(matrix.count) configurations)")
    let json = try JSONSerialization.data(withJSONObject: ["photometrics": matrix, "exposure": exposures])
    try json.write(to: outDir.appendingPathComponent("photometrics-matrix.json"))
} catch {
    check(false, "photometrics matrix written: \(error)")
}

// MARK: Stands and beam clipping (same rules as web/src/model/rigging.ts)
do {
    var cob = LightFixture(name: "K", kind: .fresnel, position: .zero)
    cob.profileID = "cob-600-d"
    cob.height = 2
    check(cob.supportValue == .cStand, "600 W COB at 2 m goes on a C-stand")
    cob.height = 0.5
    check(cob.supportValue == .turtleBase, "low unit goes on a turtle base")
    cob.height = 2
    cob.modifierID = "softbox-150"
    check(cob.supportValue == .comboStand, "big softbox goes on a combo")
    cob.support = .cStand
    cob.height = 3.8
    check(cob.supportWarning?.hasPrefix("Higher than a C-stand") == true, "warns above a C-stand's reach")
    var hmi = LightFixture(name: "H", kind: .hmi, position: .zero)
    hmi.profileID = "hmi-1800-par"
    check(hmi.supportValue == .comboStand, "HMI goes on a combo")
    check(CameraRig().supportValue == .tripod && CameraSupport.automatic(height: 0.3) == .highHat, "camera on a tripod, high hat when low")
    var plan = FloorPlan()
    plan.walls = [PlanSegment(kind: .wall, a: PlanPoint(x: -5, z: -2), b: PlanPoint(x: 5, z: -2), height: 2.5, bottom: 0)]
    check(abs(BeamClip.planReach(from: .zero, bearing: 0, limit: 6, plan: plan) - 2) < 1e-6, "beam stops at the wall")
    check(abs(BeamClip.planReach(from: .zero, bearing: 180, limit: 6, plan: plan) - 6) < 1e-6, "beam away from walls keeps its reach")
    // Older rigs without the field still decode.
    let old = try JSONSerialization.data(withJSONObject: ["position": ["x": 0, "z": 0], "height": 1.5, "pan": 0, "tilt": 0, "focalLength": 32,
                                                          "sensorID": "arri-minilf-og", "aspect": "sensor"])
    check((try? JSONDecoder().decode(CameraRig.self, from: old))?.support == nil, "camera rig without a support decodes")
} catch {
    check(false, "stands: \(error)")
}

// MARK: Rooms drawn by hand
do {
    var box = DrawnRoom()
    box.length = 6.2; box.width = 4.8; box.ceiling = 2.74; box.windows = 2
    let bp = box.plan
    check(bp.walls.count == 4 && bp.windows.count == 2 && bp.doors.count == 1, "drawn box has four walls, its windows and a door")
    check(abs(bp.bounds.width - 6.2) < 1e-9 && abs(bp.bounds.depth - 4.8) < 1e-9, "drawn box keeps the typed sizes")
    check(bp.windows.allSatisfy { $0.a.z == -2.4 && $0.a.x > -3.1 && $0.b.x < 3.1 }, "windows sit inside the top wall")
    var ell = DrawnRoom()
    ell.shape = .l; ell.length = 8; ell.width = 6; ell.windows = 0; ell.door = false
    check(ell.plan.walls.count == 6 && abs(ell.floorArea - 36) < 1e-9, "drawn L has six walls and three quarters of the area")
    var silly = DrawnRoom()
    silly.length = 0; silly.width = .nan; silly.ceiling = 99; silly.windows = 9
    check(silly.normalised.length == 1.5 && silly.normalised.width == 1.5 && silly.normalised.ceiling == 20 && silly.normalised.windows == 4, "drawn room clamps silly sizes")
    let st = box.stats
    check(st.provenance(of: .roomSize, kind: .room) == .manual && st.provenance(of: .ceilingHeight, kind: .room) == .manual, "typed sizes are manual, not measured")
    check(ScanStats().provenance(of: .roomSize, kind: .room) == .measured, "scanned rooms still read as measured")
    let data = try JSONEncoder().encode(ScanStats())
    check((try JSONDecoder().decode(ScanStats.self, from: data)).enteredByHand == nil, "older scan stats decode without the new field")
}

// MARK: Rooms from a studio listing (cases shared with web/tests/listing.test.ts)
do {
    struct Expect: Decodable {
        var length, width, ceiling, area: Double?
        var windows: Int?
        var door: Bool?
        var sizeSource: String
        var alternatives: Int
    }
    struct Case: Decodable { var name: String; var text: String; var expect: Expect }
    struct Fixture: Decodable { var cases: [Case] }
    let data = try Data(contentsOf: URL(fileURLWithPath: "web/tests/fixtures/listings.json"))
    let cases = try JSONDecoder().decode(Fixture.self, from: data).cases
    check(cases.count >= 8, "listing fixture loads (\(cases.count) cases)")
    for c in cases {
        let e = c.expect
        let r = ListingReader.read(c.text)
        func same(_ got: Double?, _ want: Double?) -> Bool {
            guard let want else { return got == nil }
            return got.map { abs($0 - want) < 1e-9 } ?? false
        }
        let ok = same(r.length, e.length) && same(r.width, e.width) && same(r.ceiling, e.ceiling) && same(r.area, e.area)
            && r.windows == e.windows && r.door == e.door && r.sizeSource.rawValue == e.sizeSource && r.alternatives.count == e.alternatives
        check(ok, "listing: \(c.name) (got \(String(describing: r.length)) × \(String(describing: r.width)), ceiling \(String(describing: r.ceiling)), area \(String(describing: r.area)), windows \(String(describing: r.windows)), door \(String(describing: r.door)), \(r.sizeSource), \(r.alternatives.count) alt)")
    }
    let quoted = ListingReader.read("Studio 2: 15m × 10m × 6m to grid")
    check(quoted.findings.first?.quote == "Studio 2: 15m × 10m × 6m to grid", "listing quotes keep the original text")
    var base = DrawnRoom()
    base.length = 9; base.width = 7
    let kept = ListingReader.read("Ceiling height 5 m").room(base: base)
    check(kept.length == 9 && kept.width == 7 && kept.ceiling == 5, "a listing keeps what it doesn't say")
    let huge = ListingReader.read("Stage 90m x 45m x 18m").room()
    check(huge.length == 60 && huge.width == 45 && huge.ceiling == 18, "a huge stage is clamped to a drawn room")
    check(ListingReader.read("100 sqm loft").sizeNote.contains("square"), "area-only listing says the shape is a guess")
    check(ListingReader.fmt(15) == "15" && ListingReader.fmt(18.288) == "18.29", "listing numbers print like the web")
}

// MARK: Readings (T-stop first, lux optional)
do {
    let e = ExposureSettings()
    check(ReadingFormat.value(lux: e.keyLux, exposure: e, extra: .off) == ExposureSettings.stopLabel(e.tStop), "key level reads as the set T-stop")
    check(ReadingFormat.value(lux: e.keyLux * 2, exposure: e, extra: .off) == ExposureSettings.stopLabel(e.tStop * 2.0.squareRoot()), "double the light reads one stop higher")
    check(ReadingFormat.value(lux: 536, exposure: e, extra: .lux).hasSuffix(" · 536 lx"), "lux follows the stop")
    check(ReadingFormat.value(lux: 1076.4, exposure: e, extra: .footCandles).hasSuffix(" · 100 fc"), "foot-candles are lux / 10.764")
    check(ReadingFormat.text(lux: 300, exposure: e, extra: .lux).hasPrefix("≈ T"), "the stop comes first and the reading is marked approximate")
    check(ReadingFormat.stop(lux: 0, exposure: e) == "under T0.5" && ReadingFormat.stop(lux: 1e-4, exposure: e) == "under T0.5", "no light reads under T0.5, never T0")
    check(ReadingExtra.allCases.first == ReadingExtra.off, "lux is off until switched on")
    check(ReadingExtra.migrated(from: "lux") == .lux && ReadingExtra.migrated(from: "footCandles") == .footCandles && ReadingExtra.migrated(from: "stops") == nil, "an old lux choice is kept")
    check(abs(ExposureSettings.steppedStop(2.8, thirds: 1) - 3.1748) < 1e-3 && abs(ExposureSettings.steppedStop(2.8, thirds: 3) - 4) < 1e-9, "T-stop steps by thirds")
    check(ExposureSettings.steppedStop(1, thirds: -1) == 1 && ExposureSettings.steppedISO(800, by: 1) == 1000 && ExposureSettings.steppedISO(12800, by: 1) == 12800, "steps stop at the ends")
}

// MARK: Set pieces by hand (same cases as web/tests/setPieces.test.ts)
do {
    var spec = DrawnRoom()
    spec.length = 6; spec.width = 4; spec.ceiling = 2.7; spec.windows = 0; spec.door = false
    let room = spec.plan   // walls at x = ±3 and z = ±2
    let close = { (a: Double, b: Double) in abs(a - b) < 1e-6 }
    let w = SetPieces.placeOpening(room, at: P(1, -1.6), preset: SetPieces.opening("window")!)!
    check(w.kind == .window && w.a.z == -2 && w.b.z == -2 && close(w.length, 1.2) && close(w.midpoint.x, 1), "window goes in the nearest wall at its typical width")
    check(w.bottom == 0.85 && w.height == 1.4 && w.byHand == true, "window keeps its sill and height and is marked by hand")
    check(SetPieces.placeOpening(room, at: P(0, 0), preset: SetPieces.opening("door")!) == nil, "no door far from every wall")
    var low = spec; low.ceiling = 2.0
    let tall = SetPieces.placeOpening(low.plan, at: P(0, -2), preset: SetPieces.opening("tall-window")!)!
    check(tall.bottom + tall.height <= 1.95 + 1e-9, "openings stay under the top of the wall")
    let slid = SetPieces.slide(w, to: P(-2, -2.2), in: room)
    check(close(slid.midpoint.x, -2) && slid.a.z == -2 && slid.id == w.id, "openings slide along the wall")
    let other = SetPieces.slide(w, to: P(2.9, 0.5), in: room)
    check(other.a.x == 3 && close(other.length, 1.2), "openings move onto another wall, same width")
    check(close(SetPieces.resize(w, width: 2, in: room).length, 2) && close(SetPieces.resize(w, width: 50, in: room).length, 5.9), "resizing keeps openings inside the wall")
    let sofa = SetPieces.placeFurniture(room, at: P(0, 1.6), preset: SetPieces.furniturePreset("sofa")!)
    check(close(sofa.center.z, 2 - 0.45 - 0.02) && abs(sin(sofa.rotation)) < 1e-6, "a sofa near a wall backs onto it")
    let side = SetPieces.placeFurniture(room, at: P(-2.6, 0), preset: SetPieces.furniturePreset("wardrobe")!)
    check(close(side.center.x, -3 + 0.3 + 0.02) && abs(cos(side.rotation)) < 1e-6, "a wardrobe turns to back onto the side wall")
    let mid = SetPieces.placeFurniture(room, at: P(0, 0), preset: SetPieces.furniturePreset("dining-table")!)
    check(mid.center == P(0, 0) && mid.rotation == 0, "furniture in the middle stays square")
    var turned = mid
    for _ in 0..<5 { turned = SetPieces.turned(turned, by: .pi / 2) }
    check(abs(turned.rotation - .pi / 2) < 1e-3 && turned.rotation > -.pi && turned.rotation <= .pi, "turning by quarters stays in range")
    var plan = room
    var door = SetPieces.placeOpening(room, at: P(0, 2), preset: SetPieces.opening("door")!)!
    plan.add(door)
    door.kind = .opening
    plan.replace(door)
    check(plan.doors.isEmpty && plan.openings.count == 1, "changing the kind moves a segment to the matching list")
    plan.removeSegment(door.id)
    check(plan.openings.isEmpty, "segments delete by id")
    check(SetPieces.openings.map(\.id) == ["door", "double-door", "window", "tall-window", "opening"]
          && SetPieces.furniture.map(\.id) == ["sofa", "armchair", "chair", "dining-table", "coffee-table", "desk", "bed", "wardrobe", "sideboard", "shelves", "fridge", "cooker", "sink", "bath", "toilet", "fireplace", "box"],
          "same presets as the web planner")
    // Older plans load: byHand is optional.
    let old = try JSONEncoder().encode(PlanObject(category: "Sofa", center: P(0, 0), width: 2, depth: 1, height: 1, rotation: 0))
    check((try JSONDecoder().decode(PlanObject.self, from: old)).byHand == nil, "older set pieces decode without byHand")
    // Plans merge by id: a piece added on each side survives.
    let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(["K": room])) as! [String: Any]
    var phone = room; phone.objects.append(sofa)
    var desk = room; desk.windows.append(w)
    let merged = SyncMerge.merge(base: base, local: try JSONSerialization.jsonObject(with: JSONEncoder().encode(["K": phone])),
                                 remote: try JSONSerialization.jsonObject(with: JSONEncoder().encode(["K": desk]))) as! [String: Any]
    let m = try JSONDecoder().decode(FloorPlan.self, from: JSONSerialization.data(withJSONObject: merged["K"]!))
    check(m.objects.count == 1 && m.windows.count == 1, "set pieces added on the phone and the desktop both survive a sync")
}

// MARK: Known quirks and library order (same rules as web/tests/quirks.test.ts)
do {
    check(FixtureLibrary.profiles.allSatisfy { !KnownQuirks.fixture($0.id).isEmpty }, "every fixture type has things to know")
    check(SensorLibrary.presets.allSatisfy { !KnownQuirks.sensor($0.id).isEmpty }, "every camera format has things to know")
    check(Set(KnownQuirks.fixtures.keys) == Set(FixtureLibrary.profiles.map(\.id))
          && Set(KnownQuirks.sensors.keys) == Set(SensorLibrary.presets.map(\.id)), "quirks only for units in the library")
    let all = KnownQuirks.fixtures.values.flatMap { $0 } + KnownQuirks.sensors.values.flatMap { $0 }
    check(all.allSatisfy { !$0.source.isEmpty && $0.text.count <= 170 && ($0.url?.hasPrefix("https://") ?? true) }, "quirks are short and sourced")
    let cats = FixtureLibrary.profiles.map(\.category)
    let order = FixtureCategory.allCases
    check(Swift.zip(cats, cats.dropFirst()).allSatisfy { order.firstIndex(of: $0)! <= order.firstIndex(of: $1)! }, "fixtures listed family by family")
    check(Swift.zip(FixtureLibrary.profiles, FixtureLibrary.profiles.dropFirst()).allSatisfy { $0.category != $1.category || $0.ratedPower <= $1.ratedPower },
          "fixtures listed small to large within a family")
    check(SensorLibrary.manufacturers == ["ARRI", "RED", "Sony", ""], "camera makers listed A to Z, generic formats last")
    check(SensorLibrary.format(id: "no-such-camera").id == SensorLibrary.defaultID, "unknown camera falls back to the default format")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
