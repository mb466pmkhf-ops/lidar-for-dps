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
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
