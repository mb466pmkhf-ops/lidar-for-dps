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
check(abs(cobPM.illuminanceOnAxis(at: 3) - 2200) < 2200 * 0.001, "reference reading round-trips (\(cobPM.illuminanceOnAxis(at: 3)) lx at 3 m)")
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
check(spotGain > 8 && spotGain < 14, "spotting a fresnel concentrates the same flux (\(spotGain)×)")
check(abs(spot.photometrics.flux - flood.photometrics.flux) < 1e-6, "spot/flood keeps flux")
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
// Solve the output for a target.
let solved = C.solveOutput(for: cob, target: 1000, at: at3, normal: facingKey, allLights: [cob], plan: nil)
if case .output(let o) = solved {
    var set = cob; set.dimmer = o
    check(abs(C.reading(at: at3, normal: facingKey, scene: C.Scene(lights: [set])).lux - 1000) < 1, "solved output hits the target")
} else { check(false, "target solve returns an output") }
if case .tooDim(_, let d?) = C.solveOutput(for: cob, target: 20000, at: at3, normal: facingKey, allLights: [cob], plan: nil) {
    check(d < 3, "too dim suggests moving closer (\(d) m)")
} else { check(false, "out-of-reach target reports too dim") }
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

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
