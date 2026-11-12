import SceneKit
import SwiftUI
import UIKit

/// Builds SceneKit content from FrameScout's format-neutral geometry and the previs items
/// (cameras, lights, people, meters). Everything placed on the plan uses plan x/z and height above
/// the floor, so the plan and the 3D view always agree.
enum SceneKitBuilder {
    /// Scan geometry. `register` sees every node that carries a category (walls, windows, set pieces).
    static func node(for geometry: SceneGeometry, register: ((SCNNode, [String: String]) -> Void)? = nil) -> SCNNode {
        func build(_ n: SceneNode) -> SCNNode {
            let node = SCNNode()
            node.name = n.name
            node.simdPosition = n.translation
            if let mesh = n.mesh, !mesh.isEmpty {
                node.geometry = scnGeometry(mesh)
            }
            if n.info["category"] != nil { register?(node, n.info) }
            for c in n.children where c.camera == nil { node.addChildNode(build(c)) }
            return node
        }
        return build(geometry.root)
    }

    static func scnGeometry(_ mesh: SceneMesh) -> SCNGeometry {
        let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        var sources = [SCNGeometrySource(vertices: vertices)]
        if mesh.normals.count == mesh.positions.count {
            sources.append(SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }))
        }
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        let c = mesh.material.color
        material.diffuse.contents = UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        material.transparency = CGFloat(c.w)
        material.lightingModel = .physicallyBased
        // A floor has a little sheen, so a low light rakes across it the way it does on set.
        material.roughness.contents = mesh.material.name == "Floor" ? 0.5 : CGFloat(mesh.material.roughness)
        material.metalness.contents = CGFloat(mesh.material.metallic)
        material.isDoubleSided = mesh.material.isTranslucent || mesh.material.name.hasPrefix("Mesh_")
        geometry.materials = [material]
        return geometry
    }

    static func material(_ color: UIColor, emission: UIColor? = nil, constant: Bool = false, roughness: CGFloat = 0.7) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = constant ? .constant : .physicallyBased
        m.roughness.contents = roughness
        if let emission { m.emission.contents = emission }
        return m
    }

    static func uiColor(_ c: (r: Double, g: Double, b: Double), alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha)
    }

    /// Text that always faces the viewer.
    static func label(_ text: String, color: UIColor = .white, size: CGFloat = 0.09) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0)
        t.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        t.flatness = 0.2
        t.firstMaterial = material(color, constant: true)
        let node = SCNNode(geometry: t)
        let (lo, hi) = node.boundingBox
        let scale = Float(size) / 10
        node.scale = SCNVector3(scale, scale, scale)
        node.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, lo.y, 0)
        let holder = SCNNode()
        holder.addChildNode(node)
        holder.constraints = [SCNBillboardConstraint()]
        holder.renderingOrder = 10
        return holder
    }

    /// Thin lines between point pairs.
    static func lines(_ pairs: [(SIMD3<Float>, SIMD3<Float>)], color: UIColor) -> SCNNode {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for (a, b) in pairs {
            indices += [Int32(vertices.count), Int32(vertices.count + 1)]
            vertices += [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z)]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        g.firstMaterial = material(color, constant: true)
        let node = SCNNode(geometry: g)
        node.castsShadow = false
        return node
    }

    /// 1 m ground grid with a brighter line every 5 m.
    static func groundGrid(extent: Int = 12) -> SCNNode {
        var minor: [(SIMD3<Float>, SIMD3<Float>)] = []
        var major: [(SIMD3<Float>, SIMD3<Float>)] = []
        let e = Float(extent)
        for i in -extent...extent {
            let f = Float(i)
            let pair1 = (SIMD3<Float>(f, 0, -e), SIMD3<Float>(f, 0, e))
            let pair2 = (SIMD3<Float>(-e, 0, f), SIMD3<Float>(e, 0, f))
            if i % 5 == 0 { major += [pair1, pair2] } else { minor += [pair1, pair2] }
        }
        let node = SCNNode()
        node.addChildNode(lines(minor, color: UIColor(white: 1, alpha: 0.10)))
        node.addChildNode(lines(major, color: UIColor(white: 1, alpha: 0.22)))
        return node
    }

    // MARK: People

    // The figure itself is in FigureModel.swift.

    // MARK: Cameras

    /// Cinema camera on its support (O'Connor-style head on sticks by default), with the frame's
    /// field of view drawn out to `reach`.
    static func cameraModel(rig: CameraRig, color: UIColor, label text: String?, reach: Double, selected: Bool) -> SCNNode {
        let root = SCNNode()
        let head = SCNNode()
        head.simdEulerAngles = SIMD3(0, Float(-rig.pan * .pi / 180), 0)
        let tilt = SCNNode()
        tilt.simdEulerAngles = SIMD3(Float(rig.tilt * .pi / 180), 0, 0)
        head.addChildNode(tilt)
        head.simdPosition = SIMD3(0, Float(rig.height), 0)
        root.addChildNode(head)

        let (body, lensFront) = RigModels.cameraBody(rig: rig, accent: color, selected: selected)
        tilt.addChildNode(body)
        RigModels.cameraSupport(rig.supportValue, height: rig.height, to: head)

        // Field of view: frame rectangle at `reach`, joined to the lens.
        let hx = Float(tan(rig.horizontalFOV * .pi / 360) * reach)
        let hy = Float(tan(rig.verticalFOV * .pi / 360) * reach)
        let z = Float(-reach)
        let apex = SIMD3<Float>(0, 0, lensFront)
        let frame: [SIMD3<Float>] = [SIMD3(-hx, -hy, z), SIMD3(hx, -hy, z), SIMD3(hx, hy, z), SIMD3(-hx, hy, z)]
        var pairs = (0..<4).map { (frame[$0], frame[($0 + 1) % 4]) }
        pairs += frame.map { (apex, $0) }
        tilt.addChildNode(lines(pairs, color: color.withAlphaComponent(selected ? 0.9 : 0.45)))

        if let text {
            let l = label(text, color: color)
            l.simdPosition = SIMD3(0, Float(rig.height) + 0.25, 0)
            root.addChildNode(l)
        }
        root.simdPosition = SIMD3(Float(rig.position.x), 0, Float(rig.position.z))
        return root
    }

    // MARK: Lights

    /// Black mask the spot light projects to show barn-door cuts (white passes).
    static func barnDoorGobo(_ doors: BarnDoors, outerAngle: Double) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let t = tan(min(outerAngle, 170) / 2 * .pi / 180)
        func edge(_ limit: Double) -> CGFloat {
            guard limit < 89.5 else { return 1 }
            return CGFloat(min(1, max(-1, tan(limit * .pi / 180) / t)))
        }
        let left = -edge(doors.left), right = edge(doors.right), top = edge(doors.top), bottom = -edge(doors.bottom)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            let x0 = (left + 1) / 2 * size.width, x1 = (right + 1) / 2 * size.width
            let y0 = (1 - top) / 2 * size.height, y1 = (1 - bottom) / 2 * size.height
            if x1 > x0, y1 > y0 { ctx.fill(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) }
        }
    }

    /// Beam rays from the unit's front, each stopped where it first meets the room (scan surfaces or
    /// the floor). Rays that meet nothing leave the location and aren't drawn, so beams never spill
    /// out of the room. `hit` returns the distance to the first surface along a direction in the
    /// light's own space, or nil. Drawing only; lux comes from `LightingCalculator`.
    static func clippedBeam(pm: ResolvedPhotometrics, doors: BarnDoors, color: UIColor, rays: Int = 28,
                            hit: (SIMD3<Float>) -> Float?) -> SCNNode? {
        guard pm.distribution == .beam || pm.distribution == .lambertian else { return nil }
        let half = min(pm.distribution == .beam ? pm.beamAngle * 0.68 : 60, 75)
        let th = Float(tan(half * .pi / 180))
        func t(_ limit: Double) -> Float { Float(tan(min(half, pm.barnDoorsAvailable ? limit : 90) * .pi / 180)) }
        let l = t(doors.left), r = t(doors.right), u = t(doors.top), d = t(doors.bottom)
        var ends: [SIMD3<Float>?] = []
        for k in 0..<rays {
            let a = Float(k) / Float(rays) * 2 * .pi
            let x = min(max(cos(a) * th, -l), r), y = min(max(sin(a) * th, -d), u)
            let dir = simd_normalize(SIMD3<Float>(x, y, -1))
            ends.append(hit(dir).map { dir * $0 })
        }
        let axisDir = SIMD3<Float>(0, 0, -1)
        let centre = hit(axisDir).map { axisDir * $0 }
        guard ends.contains(where: { $0 != nil }) || centre != nil else { return nil }
        var vertices: [SCNVector3] = [SCNVector3(0, 0, 0)]
        var colors: [Float] = []
        var cr: CGFloat = 1, cg: CGFloat = 1, cb: CGFloat = 1, ca: CGFloat = 1
        color.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
        let rgba = (cr, cg, cb, ca)
        func push(_ p: SIMD3<Float>, strength: Float) {
            vertices.append(SCNVector3(p.x, p.y, p.z))
            colors += [Float(rgba.0) * strength, Float(rgba.1) * strength, Float(rgba.2) * strength, 1]
        }
        colors += [Float(rgba.0) * 0.16, Float(rgba.1) * 0.16, Float(rgba.2) * 0.16, 1]
        func fade(_ p: SIMD3<Float>) -> Float { 0.09 / (1 + simd_length(p) * 0.35) }
        var index: [Int32?] = []
        for e in ends {
            if let e { index.append(Int32(vertices.count)); push(e, strength: fade(e)) } else { index.append(nil) }
        }
        var centreIndex: Int32?
        if let c = centre { centreIndex = Int32(vertices.count); push(c, strength: fade(c)) }
        var indices: [Int32] = []
        for k in 0..<rays {
            guard let i0 = index[k], let i1 = index[(k + 1) % rays] else { continue }
            indices += [0, i0, i1]
            // The far end, closed towards the centre ray, so the beam reads as a solid cone.
            if let c = centreIndex { indices += [c, i1, i0] }
        }
        guard !indices.isEmpty else { return nil }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: vertices.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<Float>.size * 4)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), colorSource],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = material(.white, constant: true)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .add
        g.materials = [m]
        let node = SCNNode(geometry: g)
        node.castsShadow = false
        node.renderingOrder = 5
        return node
    }

    /// Brightness for the viewport only. `share` is the unit's on-axis output against the brightest
    /// unit in the scene (from the photometric model), so units keep their true ratio to each other
    /// while the picture as a whole is fitted to the screen. Never used for lux.
    static func viewportIntensity(share: Double) -> CGFloat {
        CGFloat(800 * min(max(share, 0.004), 1))
    }

    /// A small top-to-bottom gradient, for the backdrop and for reflections in metal and glass.
    static func gradient(top: CGFloat, bottom: CGFloat) -> UIImage {
        let size = CGSize(width: 16, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: top, alpha: 1).cgColor, UIColor(white: bottom, alpha: 1).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    /// Picture settings shared by the orbit and viewfinder cameras: HDR with a fixed exposure (auto
    /// exposure would hide how bright one setup is against another), a soft glow round bright
    /// faces, and contact shading where surfaces meet.
    static func film(_ camera: SCNCamera?) {
        guard let camera else { return }
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.bloomThreshold = 1.0
        camera.bloomIntensity = 0.25
        camera.bloomBlurRadius = 10
        camera.screenSpaceAmbientOcclusionIntensity = 0.9
        camera.screenSpaceAmbientOcclusionRadius = 0.35
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.2
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
    }
}

/// One selectable viewpoint (camera position or shot).
struct VirtualViewpoint: Identifiable, Hashable {
    enum Kind: Hashable { case camera, shot }
    var id: UUID
    var kind: Kind
    var label: String
    var rig: CameraRig
    var subject: PlanPoint?
    var subjectHeight: Double
}

/// Dollhouse view: walls (and their doors and windows) between the orbit camera and the room are
/// cut away so you can see in. Runs on SceneKit's render thread; only touches the nodes it was given.
final class WallFader {
    private let lock = NSLock()
    private var walls: [SCNNode] = []
    private weak var world: SCNNode?
    private var centre = SIMD3<Float>(0, 0, 0)
    /// Each wall's centre in the world node's space.
    private var mids: [SIMD3<Float>] = []
    /// Hidden by the user (Layers), per node.
    private var userHidden: [Bool] = []
    private var cut: [Bool] = []

    func configure(walls: [SCNNode], world: SCNNode, centre: SIMD3<Float>) {
        lock.lock(); defer { lock.unlock() }
        self.walls = walls
        self.world = world
        self.centre = centre
        // Wall meshes can sit on child nodes with vertices in room coordinates, so measure the geometry.
        mids = walls.map { wall in
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            func visit(_ n: SCNNode) {
                if let g = n.geometry {
                    let (a, b) = g.boundingBox
                    for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                        let p = n.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: world)
                        lo = simd_min(lo, p); hi = simd_max(hi, p)
                    } } }
                }
                n.childNodes.forEach(visit)
            }
            visit(wall)
            return lo.x <= hi.x ? (lo + hi) / 2 : centre
        }
        userHidden = walls.map(\.isHidden)
        cut = Array(repeating: false, count: walls.count)
    }

    /// Records what the user has hidden; call after applying display settings.
    func syncUserHidden() {
        lock.lock(); defer { lock.unlock() }
        userHidden = walls.map(\.isHidden)
        cut = Array(repeating: false, count: walls.count)
    }

    /// Puts every cut wall back (for views from inside the room).
    func restore() {
        lock.lock(); defer { lock.unlock() }
        for (i, wall) in walls.enumerated() where cut[i] {
            wall.isHidden = userHidden[i]
            cut[i] = false
        }
    }

    func update(camera: SIMD3<Float>) {
        lock.lock(); defer { lock.unlock() }
        guard let world, !walls.isEmpty else { return }
        let c = world.presentation.simdConvertPosition(centre, to: nil)
        for (i, wall) in walls.enumerated() {
            guard i < mids.count, i < cut.count else { break }
            let mid = world.presentation.simdConvertPosition(mids[i], to: nil)
            let outward = SIMD2(mid.x - c.x, mid.z - c.z)
            let toCamera = SIMD2(camera.x - mid.x, camera.z - mid.z)
            // In front of the wall's outside face, and outside the room.
            let near = simd_dot(outward, toCamera) > 0 && simd_length(SIMD2(camera.x - c.x, camera.z - c.z)) > simd_length(outward)
            if near != cut[i] {
                cut[i] = near
                wall.isHidden = near || userHidden[i]
            }
        }
    }
}

/// The 3D scene for a location: the scan (or geometry built from its plan) plus everything placed
/// on the plan. Scan, cameras, lights and people sit under one `world` node, so a levelling or
/// alignment correction moves them together and they stay where they are in the room.
@MainActor
final class VirtualSceneModel: ObservableObject {
    @Published var loaded = false
    @Published var error: String?
    /// The room was built from the floor plan because the scan's geometry files aren't available.
    @Published var builtFromPlan = false
    let scene = SCNScene()
    let world = SCNNode()
    let panNode = SCNNode()
    let tiltNode = SCNNode()
    let cameraNode = SCNNode()
    let orbitCameraNode = SCNNode()
    let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let scanHolder = SCNNode()
    private let markers = SCNNode()
    private let lightRig = SCNNode()
    private let people = SCNNode()
    private let meterNodes = SCNNode()
    private let grid = SceneKitBuilder.groundGrid()
    private let selectionRing = SCNNode()
    private(set) var floorY: Double = 0
    private(set) var roomCentre = SIMD3<Float>(0, 1, 0)
    private(set) var roomSpan: Float = 6
    private(set) var geometry: SceneGeometry?
    private var scanItems: [(node: SCNNode, category: String, id: UUID?)] = []
    /// Pieces placed by hand on the plan, drawn over a real scan (see `showPlanEdits`).
    private var handItems: [(node: SCNNode, category: String, id: UUID?)] = []
    private var handNode: SCNNode?
    /// What the room or the hand-placed overlay was last built from, so unchanged plans aren't rebuilt.
    private var builtPlan: FloorPlan?
    private var builtHand: FloorPlan?
    /// Scanned set pieces moved or deleted on the plan: hidden in the scan, redrawn from the plan.
    private var replacedScanPieces: Set<UUID> = []
    private var alignment = ScanAlignment.identity
    private weak var orbitView: SCNView?
    let wallFader = WallFader()
    /// Built nodes per item with the hash of what they were built from; unchanged items are reused.
    private var lightCache: [UUID: (key: Int, node: SCNNode)] = [:]
    /// Each lit unit's SceneKit light with its on-axis output, so brightness can be re-fitted
    /// without rebuilding the unit.
    private var viewportLights: [UUID: (light: SCNLight, onAxis: Double, full: Double)] = [:]
    /// Soft sources standing in for light thrown back off grip and passed through diffusion (D-013).
    private let gripGlow = SCNNode()
    /// Flags, frames and boards a beam's haze stops at.
    private var beamBlockers: [LightFixture] = []
    /// True while the sun has been placed from a real date and time (the viewfinder's sun study).
    private var sunIsSet = false
    private var markerCache: [UUID: (key: Int, node: SCNNode)] = [:]
    private let subjectMarks = SCNNode()
    /// Bumped when the scan geometry changes, so beams are traced again against the new room.
    private var sceneGeneration = 0
    /// The scan's footprint (x/z) in world-node space; floor outside it doesn't stop a beam.
    private var roomFootprint: (lo: SIMD2<Float>, hi: SIMD2<Float>)?

    // Orbit view: the camera circles `orbitTarget` at `orbitDistance`, `orbitYaw` round from +Z and
    // `orbitPitch` above the horizon. All moves go through here on the main thread.
    private(set) var orbitTarget = SIMD3<Float>(0, 1, 0)
    private var orbitYaw: Float = 0
    private var orbitPitch: Float = 0.8
    private var orbitDistance: Float = 6

    init() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.03
        cameraNode.camera?.zFar = 500
        cameraNode.camera?.projectionDirection = .horizontal
        SceneKitBuilder.film(cameraNode.camera)
        tiltNode.addChildNode(cameraNode)
        panNode.addChildNode(tiltNode)

        orbitCameraNode.camera = SCNCamera()
        orbitCameraNode.camera?.zNear = 0.05
        orbitCameraNode.camera?.zFar = 500
        SceneKitBuilder.film(orbitCameraNode.camera)
        scene.rootNode.addChildNode(orbitCameraNode)

        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 450
        scene.rootNode.addChildNode(ambientNode)

        sunNode.light = SCNLight()
        sunNode.light?.type = .directional
        sunNode.light?.intensity = 900
        sunNode.light?.castsShadow = true
        sunNode.light?.shadowMode = .deferred
        sunNode.light?.shadowColor = UIColor.black.withAlphaComponent(0.6)
        sunNode.simdPosition = SIMD3(3, 10, 4)
        sunNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(sunNode)

        scene.rootNode.addChildNode(grid)
        scene.rootNode.addChildNode(world)
        for n in [scanHolder, markers, subjectMarks, lightRig, gripGlow, people, meterNodes, panNode, selectionRing] { world.addChildNode(n) }
        let ring = SCNTorus(ringRadius: 0.4, pipeRadius: 0.012)
        ring.firstMaterial = SceneKitBuilder.material(.white, constant: true)
        selectionRing.geometry = ring
        selectionRing.isHidden = true
        selectionRing.castsShadow = false
        scene.background.contents = SceneKitBuilder.gradient(top: 0.10, bottom: 0.02)
        // A soft surround, mostly for reflections in stands, lenses and glass.
        scene.lightingEnvironment.contents = SceneKitBuilder.gradient(top: 0.85, bottom: 0.2)
        scene.lightingEnvironment.intensity = 0.6
    }

    /// Loads the scan. With `plan`, a scan whose geometry files are missing is built from the plan instead.
    func load(scan: ScanRecord, ref: LocationRef, floorY: Double, plan: FloorPlan? = nil) {
        self.floorY = floorY
        grid.simdPosition = SIMD3(0, Float(floorY), 0)
        Task {
            do {
                let geometry: SceneGeometry
                do {
                    geometry = try await Task.detached(priority: .userInitiated) {
                        try ScanAssets.geometry(for: scan, ref: ref, options: .init(includeCeiling: false, includeObjects: true))
                    }.value
                } catch let failure as ScanAssets.AssetError {
                    guard let plan, !plan.isEmpty else { throw failure }
                    geometry = PlanSceneBuilder.sceneGeometry(plan)
                    builtFromPlan = true
                }
                if builtFromPlan { builtPlan = plan }
                installRoom(geometry)
                applyAlignment(alignment)
                resetView()
                loaded = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Puts the room's geometry in the scene (replacing what was there) and registers its parts.
    private func installRoom(_ geometry: SceneGeometry) {
        self.geometry = geometry
        var items: [(node: SCNNode, category: String, id: UUID?)] = []
        let node = SceneKitBuilder.node(for: geometry) { n, info in
            items.append((n, info["category"]?.lowercased() ?? "", info["id"].flatMap(UUID.init(uuidString:))))
        }
        scanItems = items
        handNode = nil
        handItems = []
        builtHand = nil
        replacedScanPieces = []
        let cutaway: Set<SceneGroup> = [.walls, .windows, .doors]
        wallFader.configure(walls: items.filter { group(for: $0.category).map(cutaway.contains) ?? false }.map(\.node), world: world,
                            centre: SIMD3(roomCentreLocal(node).x, Float(floorY) + 1, roomCentreLocal(node).z))
        scanHolder.childNodes.forEach { $0.removeFromParentNode() }
        scanHolder.addChildNode(node)
        let (lo, hi) = node.boundingBox
        roomCentre = SIMD3(Float(lo.x + hi.x) / 2, Float(floorY) + 1, Float(lo.z + hi.z) / 2)
        roomSpan = max(Float(hi.x - lo.x), Float(hi.z - lo.z), 3)
        roomFootprint = (SIMD2(Float(lo.x) - 0.05, Float(lo.z) - 0.05), SIMD2(Float(hi.x) + 0.05, Float(hi.z) + 0.05))
        sceneGeneration += 1
    }

    /// Doors, windows and set pieces added or changed by hand on the plan. A room built from the plan
    /// is rebuilt; a real scan keeps its own geometry, with the pieces placed by hand drawn over it as
    /// simple boxes and the scanned pieces that were moved or deleted on the plan hidden.
    func showPlanEdits(_ plan: FloorPlan) {
        guard loaded else { return }
        if builtFromPlan {
            guard plan != builtPlan, !plan.isEmpty else { return }
            builtPlan = plan
            installRoom(PlanSceneBuilder.sceneGeometry(plan))
            applyAlignment(alignment)
            return
        }
        var hand = FloorPlan()
        hand.floorY = plan.floorY
        hand.objects = plan.objects.filter { $0.byHand == true }
        hand.windows = plan.windows.filter { $0.byHand == true }
        hand.doors = plan.doors.filter { $0.byHand == true }
        let kept = Set(plan.objects.filter { $0.byHand != true }.map(\.id))
        let replaced = Set(scanItems.compactMap { item -> UUID? in
            guard group(for: item.category) == .furniture, let id = item.id, !kept.contains(id) else { return nil }
            return id
        })
        guard hand != builtHand || replaced != replacedScanPieces else { return }
        builtHand = hand
        replacedScanPieces = replaced
        handNode?.removeFromParentNode()
        handNode = nil
        handItems = []
        if !(hand.objects.isEmpty && hand.windows.isEmpty && hand.doors.isEmpty) {
            var items: [(node: SCNNode, category: String, id: UUID?)] = []
            let node = SceneKitBuilder.node(for: PlanSceneBuilder.sceneGeometry(hand)) { n, info in
                items.append((n, info["category"]?.lowercased() ?? "", info["id"].flatMap(UUID.init(uuidString:))))
            }
            scanHolder.addChildNode(node)
            handNode = node
            handItems = items
        }
        sceneGeneration += 1
    }

    private func roomCentreLocal(_ node: SCNNode) -> SIMD3<Float> {
        let (lo, hi) = node.boundingBox
        return SIMD3(Float(lo.x + hi.x) / 2, 0, Float(lo.z + hi.z) / 2)
    }

    // MARK: Display

    private func group(for category: String) -> SceneGroup? {
        switch category {
        case "wall", "walls": return .walls
        case "door", "doors": return .doors
        case "window", "windows": return .windows
        case "floor": return .floors
        case "ceiling", "unclassified", "mesh": return nil
        default: return .furniture
        }
    }

    /// Visibility, window and wall transparency. Changes nothing in the scan.
    func applyDisplay(_ d: SceneDisplay) {
        for item in scanItems + handItems {
            let g = group(for: item.category)
            var hidden = g.map { d.isHidden(group: $0) } ?? false
            if g == .furniture {
                hidden = hidden || d.isHidden(category: item.category) || (item.id.map { d.isHidden(item: SceneItemKey.object($0)) } ?? false)
                // The scanned copy of a piece that was moved or deleted on the plan.
                if let id = item.id, replacedScanPieces.contains(id), !handItems.contains(where: { $0.node === item.node }) {
                    hidden = true
                }
            }
            item.node.isHidden = hidden
            switch g {
            case .windows?:
                item.node.opacity = CGFloat(d.windowOpacityValue)
                // Glass never shadows the 3D lights; how much light it passes is in the lux maths.
                item.node.castsShadow = false
                item.node.geometry?.firstMaterial?.transparency = 1
                item.node.geometry?.firstMaterial?.writesToDepthBuffer = d.windowOpacityValue > 0.95
            case .walls?:
                item.node.opacity = CGFloat(d.wallOpacityValue)
                item.node.geometry?.firstMaterial?.writesToDepthBuffer = d.wallOpacityValue > 0.95
            default:
                break
            }
        }
        wallFader.syncUserHidden()
        if let orbitView { wallFader.update(camera: orbitView.pointOfView?.presentation.simdWorldPosition ?? orbitCameraNode.simdWorldPosition) }
        markers.isHidden = d.isHidden(group: .cameras)
        subjectMarks.isHidden = d.isHidden(group: .cameras)
        people.isHidden = d.isHidden(group: .people)
        meterNodes.isHidden = d.isHidden(group: .meters)
    }

    // MARK: Alignment

    /// Applies a levelling/placement correction to the scan and everything placed in it.
    func applyAlignment(_ a: ScanAlignment) {
        alignment = a
        let pivot = SIMD3<Float>(roomCentre.x, Float(floorY), roomCentre.z)
        let yaw = simd_quatf(angle: Float(-a.yaw * .pi / 180), axis: SIMD3(0, 1, 0))
        let pitch = simd_quatf(angle: Float(a.pitch * .pi / 180), axis: SIMD3(1, 0, 0))
        let roll = simd_quatf(angle: Float(a.roll * .pi / 180), axis: SIMD3(0, 0, 1))
        let rotation = simd_float4x4(yaw * pitch * roll)
        func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
            var m = matrix_identity_float4x4
            m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
            return m
        }
        let offset = SIMD3<Float>(Float(a.offsetX), Float(a.offsetY), Float(a.offsetZ))
        world.simdTransform = translation(pivot + offset) * rotation * translation(-pivot)
    }

    /// Pitch and roll that level the scan's floor, and the move that puts it on the ground grid.
    func autoLevel() -> ScanAlignment? {
        guard let floor = geometry?.floorEstimate() else { return nil }
        let lev = ScanAlignment.levelling(floorNormal: floor.normal)
        var a = alignment
        a.pitch = lev.pitch
        a.roll = lev.roll
        a.offsetY = floorY - floor.height
        return a
    }

    // MARK: Camera views

    func attach(_ view: SCNView) { orbitView = view }

    /// Three-quarter view over the whole room.
    func resetView() {
        setOrbit(target: worldPoint(roomCentre), yaw: 0.6, pitch: 0.75, distance: roomSpan * 1.35, animated: true)
    }

    /// Straight down, like the plan.
    func topView() {
        setOrbit(target: worldPoint(roomCentre), yaw: 0, pitch: 1.55, distance: roomSpan * 1.6, animated: true)
    }

    /// Standing in the room at eye height, looking across it.
    func eyeLevelView() {
        let c = worldPoint(roomCentre)
        setOrbit(target: SIMD3(c.x, Float(floorY) + 1.4, c.z), yaw: orbitYaw, pitch: 0.12, distance: max(roomSpan * 0.45, 1.5), animated: true)
    }

    /// Frames a point (plan x/z, height above floor) from the current viewing direction.
    func focus(on p: PlanPoint, height: Double, distance: Float = 3) {
        let target = worldPoint(SIMD3(Float(p.x), Float(floorY + height), Float(p.z)))
        setOrbit(target: target, yaw: orbitYaw, pitch: max(orbitPitch, 0.3), distance: distance, animated: true)
    }

    /// Recentres the orbit on a world point (e.g. a double-tapped surface) without changing the angle.
    func centre(onWorld p: SIMD3<Float>) {
        setOrbit(target: p, yaw: orbitYaw, pitch: orbitPitch, distance: min(orbitDistance, max(2.5, roomSpan * 0.6)), animated: true)
    }

    /// One-finger drag: turn round the target. `dx`/`dy` in points.
    func orbitBy(dx: CGFloat, dy: CGFloat) {
        setOrbit(target: orbitTarget, yaw: orbitYaw - Float(dx) * 0.008, pitch: orbitPitch + Float(dy) * 0.006, distance: orbitDistance, animated: false)
    }

    /// Two-finger drag: slide the target over the floor, map-style.
    func panBy(dx: CGFloat, dy: CGFloat, viewHeight: CGFloat) {
        let scale = orbitDistance * 1.2 / Float(max(viewHeight, 1))
        let right = SIMD3<Float>(cos(orbitYaw), 0, -sin(orbitYaw))
        let forward = SIMD3<Float>(-sin(orbitYaw), 0, -cos(orbitYaw))
        let t = orbitTarget - right * Float(dx) * scale + forward * Float(dy) * scale
        setOrbit(target: t, yaw: orbitYaw, pitch: orbitPitch, distance: orbitDistance, animated: false)
    }

    /// Pinch: `factor` > 1 moves in.
    func zoomBy(_ factor: CGFloat, animated: Bool = false) {
        setOrbit(target: orbitTarget, yaw: orbitYaw, pitch: orbitPitch, distance: orbitDistance / Float(max(factor, 0.01)), animated: animated)
    }

    /// Two-finger twist on empty space: turn the view.
    func turnBy(radians: CGFloat) {
        setOrbit(target: orbitTarget, yaw: orbitYaw - Float(radians), pitch: orbitPitch, distance: orbitDistance, animated: false)
    }

    private func worldPoint(_ local: SIMD3<Float>) -> SIMD3<Float> { world.simdConvertPosition(local, to: nil) }

    /// The only place the orbit camera moves. Keeps it above the floor, out of the target, and near
    /// the room, then cuts away the walls in front of it (on the main thread, never mid-render).
    private func setOrbit(target: SIMD3<Float>, yaw: Float, pitch: Float, distance: Float, animated: Bool) {
        let c = worldPoint(roomCentre)
        let limit = max(roomSpan, 3)
        var t = target
        t.x = min(max(t.x, c.x - limit), c.x + limit)
        t.z = min(max(t.z, c.z - limit), c.z + limit)
        t.y = min(max(t.y, Float(floorY)), Float(floorY) + 3)
        orbitTarget = t
        orbitYaw = yaw
        orbitPitch = min(max(pitch, 0.03), 1.55)
        orbitDistance = min(max(distance, 0.6), max(roomSpan * 4, 10))
        let dir = SIMD3<Float>(sin(orbitYaw) * cos(orbitPitch), sin(orbitPitch), cos(orbitYaw) * cos(orbitPitch))
        var position = orbitTarget + dir * orbitDistance
        position.y = max(position.y, Float(floorY) + 0.25)
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
        }
        orbitCameraNode.simdPosition = position
        orbitCameraNode.simdLook(at: orbitTarget, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        if animated { SCNTransaction.commit() }
        wallFader.update(camera: position)
    }

    /// World point under a screen point on the scan or the floor.
    func surfacePoint(at screen: CGPoint, in view: SCNView) -> SIMD3<Float>? {
        let hits = view.hitTest(screen, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
                                                  SCNHitTestOption.ignoreHiddenNodes: true])
        if let h = hits.first { return h.simdWorldCoordinates }
        guard let p = planPoint(at: screen, in: view, height: 0) else { return nil }
        return worldPoint(SIMD3(Float(p.x), Float(floorY), Float(p.z)))
    }

    /// Plan point under a screen point, on the horizontal plane at `height` above the floor.
    func planPoint(at screen: CGPoint, in view: SCNView, height: Double) -> PlanPoint? {
        let near = view.unprojectPoint(SCNVector3(Float(screen.x), Float(screen.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(screen.x), Float(screen.y), 1))
        let a = world.simdConvertPosition(SIMD3(near.x, near.y, near.z), from: nil)
        let b = world.simdConvertPosition(SIMD3(far.x, far.y, far.z), from: nil)
        let y = Float(floorY + height)
        guard abs(b.y - a.y) > 1e-5 else { return nil }
        let t = (y - a.y) / (b.y - a.y)
        guard t > 0 else { return nil }
        let p = a + (b - a) * t
        return PlanPoint(x: Double(p.x), z: Double(p.z))
    }

    // MARK: Walkthrough camera

    func apply(_ vp: VirtualViewpoint) {
        let rig = vp.rig
        panNode.simdPosition = SIMD3(Float(rig.position.x), Float(floorY + rig.height), Float(rig.position.z))
        panNode.simdEulerAngles = SIMD3(0, Float(-rig.pan * .pi / 180), 0)
        tiltNode.simdEulerAngles = SIMD3(Float(rig.tilt * .pi / 180), 0, 0)
        cameraNode.camera?.fieldOfView = CGFloat(rig.horizontalFOV)
    }

    // MARK: Placed items

    /// Cameras (with their field of view), and the subject marks of shots that have no person on them.
    /// `hideSelected` leaves out the camera you're looking through (walkthrough).
    func setMarkers(viewpoints: [VirtualViewpoint], selected: UUID?, showLabels: Bool = true, hideSelected: Bool = false, hiddenSubjects: Bool = false) {
        var keep = Set<UUID>()
        for vp in viewpoints where !(hideSelected && vp.id == selected) {
            let reach = vp.subject.map { max(1.5, vp.rig.position.distance(to: $0)) } ?? 2.5
            var h = Hasher()
            h.combine(vp)
            h.combine(vp.id == selected)
            h.combine(showLabels)
            h.combine(floorY)
            let key = h.finalize()
            keep.insert(vp.id)
            if let cached = markerCache[vp.id], cached.key == key { continue }
            markerCache[vp.id]?.node.removeFromParentNode()
            let color = vp.kind == .shot ? UIColor(red: 0.56, green: 0.65, blue: 0.74, alpha: 1) : UIColor.white
            let m = SceneKitBuilder.cameraModel(rig: vp.rig, color: color, label: showLabels ? "\(vp.label) · \(Optics.formatFocal(vp.rig.focalLength))" : nil,
                                                reach: reach, selected: vp.id == selected)
            m.name = "sel:\(vp.kind == .shot ? "shot" : "camera"):\(vp.id.uuidString)"
            m.simdPosition.y = Float(floorY)
            markers.addChildNode(m)
            markerCache[vp.id] = (key, m)
        }
        for (id, cached) in markerCache where !keep.contains(id) {
            cached.node.removeFromParentNode()
            markerCache[id] = nil
        }
        subjectMarks.childNodes.forEach { $0.removeFromParentNode() }
        guard !hiddenSubjects else { return }
        for vp in viewpoints {
            guard let s = vp.subject else { continue }
            let mark = SCNCylinder(radius: 0.18, height: 0.01)
            mark.firstMaterial = SceneKitBuilder.material(UIColor(red: 0.86, green: 0.4, blue: 0.37, alpha: 0.8), constant: true)
            let node = SCNNode(geometry: mark)
            node.simdPosition = SIMD3(Float(s.x), Float(floorY) + 0.006, Float(s.z))
            node.castsShadow = false
            subjectMarks.addChildNode(node)
        }
    }

    func setPeople(_ list: [PrevisCharacter], selected: UUID?, showLabels: Bool) {
        people.childNodes.forEach { $0.removeFromParentNode() }
        for c in list {
            let f = SceneKitBuilder.figure(c, selected: c.id == selected)
            f.simdPosition = SIMD3(Float(c.position.x), Float(floorY), Float(c.position.z))
            f.simdEulerAngles = SIMD3(0, Float(-c.facing * .pi / 180), 0)
            f.name = "sel:character:\(c.id.uuidString)"
            if showLabels {
                let l = SceneKitBuilder.label(c.name, color: UIColor(white: 0.9, alpha: 1))
                l.simdPosition = SIMD3(0, Float(c.proportions.top) + 0.15, 0)
                f.addChildNode(l)
            }
            people.addChildNode(f)
        }
    }

    /// Meter readings as small domes with their value.
    func setMeters(_ points: [(id: UUID, name: String, point: LightingCalculator.Point, text: String)], selected: UUID?, showLabels: Bool) {
        meterNodes.childNodes.forEach { $0.removeFromParentNode() }
        for m in points {
            let dome = SCNSphere(radius: 0.06)
            dome.firstMaterial = SceneKitBuilder.material(m.id == selected ? .white : UIColor(white: 0.85, alpha: 1), constant: true)
            let n = SCNNode(geometry: dome)
            n.simdPosition = SIMD3(Float(m.point.x), Float(floorY + m.point.y), Float(m.point.z))
            n.name = "sel:meter:\(m.id.uuidString)"
            n.castsShadow = false
            let stand = SCNCylinder(radius: 0.006, height: CGFloat(max(m.point.y, 0.05)))
            stand.firstMaterial = SceneKitBuilder.material(UIColor(white: 0.5, alpha: 1), constant: true)
            let s = SCNNode(geometry: stand)
            s.simdPosition = SIMD3(0, -Float(m.point.y) / 2, 0)
            n.addChildNode(s)
            if showLabels {
                let l = SceneKitBuilder.label(m.text, color: .white, size: 0.08)
                l.simdPosition = SIMD3(0, 0.1, 0)
                n.addChildNode(l)
            }
            meterNodes.addChildNode(n)
        }
    }

    /// Lighting units: a head shaped by type and modifier on its yoke and stand, a SceneKit light set
    /// from the unit's colour and its output relative to the brightest unit, barn doors as leaves and
    /// a projected mask, and beam rays that stop at the room. Viewport brightness is a visual guide
    /// only (D-011); lux comes from `LightingCalculator`. Units that haven't changed keep their nodes, so dragging one light
    /// doesn't rebuild (and re-shadow) the whole rig every frame.
    func setLights(_ lights: [LightFixture], selected: UUID?, showLabels: Bool = false, showBeams: Bool = true, hideGrip: Bool = false, plan: FloorPlan? = nil) {
        var anyOn = false
        var shadowCount = 0
        var keep = Set<UUID>()
        beamBlockers = lights.filter { !$0.kind.emits }
        var gripHash = Hasher()
        gripHash.combine(beamBlockers)
        let gripKey = gripHash.finalize()
        for l in lights {
            if hideGrip && !l.kind.emits { continue }
            // Up to six units cast shadows, so flags and frames cut them.
            let wantsShadow = l.kind.emits && l.isOn && shadowCount < 6 && l.photometrics.distribution != .omni && l.photometrics.distribution != .tube
            if wantsShadow { shadowCount += 1 }
            if l.kind.emits && l.isOn { anyOn = true }
            var h = Hasher()
            h.combine(l)
            h.combine(l.id == selected)
            h.combine(showLabels)
            h.combine(showBeams)
            h.combine(wantsShadow)
            if l.kind.emits && showBeams { h.combine(gripKey) } // a beam is redrawn when grip in its way moves
            h.combine(floorY)
            h.combine(sceneGeneration)
            let key = h.finalize()
            keep.insert(l.id)
            if let cached = lightCache[l.id], cached.key == key { continue }
            lightCache[l.id]?.node.removeFromParentNode()
            viewportLights[l.id] = nil
            let node = buildLight(l, selected: l.id == selected, showLabels: showLabels, showBeams: showBeams, shadow: wantsShadow)
            lightRig.addChildNode(node)
            lightCache[l.id] = (key, node)
        }
        for (id, cached) in lightCache where !keep.contains(id) {
            cached.node.removeFromParentNode()
            lightCache[id] = nil
            viewportLights[id] = nil
        }
        // Fit the picture to the brightest unit at full output; every unit keeps its true ratio to it.
        // It depends on the units alone, so moving a person or a flag, or dimming a unit, never
        // changes how bright the other units look.
        let brightest = viewportLights.values.map(\.full).max() ?? 0
        for entry in viewportLights.values {
            entry.light.intensity = SceneKitBuilder.viewportIntensity(share: brightest > 0 ? entry.onAxis / brightest : 1)
        }
        setGripGlow(lights.filter { hideGrip ? $0.kind.emits : true }, plan: plan, brightest: brightest)
        // With units on, the room keeps only a trace of work light so their shadows read; the
        // stand-in sun is for an unlit room (or the viewfinder's sun study).
        ambientNode.light?.intensity = anyOn ? 60 : 450
        scene.lightingEnvironment.intensity = anyOn ? 0.25 : 0.6
        if !sunIsSet { sunNode.light?.intensity = anyOn ? 0 : 900 }
    }

    /// Grip as a second source, from the calculator's own patches (D-013): each lit face of a board
    /// gets a soft spot facing out of it, and the far face of a diffusion glows where it is lit.
    private func setGripGlow(_ lights: [LightFixture], plan: FloorPlan?, brightest: Double) {
        gripGlow.childNodes.forEach { $0.removeFromParentNode() }
        let n = LightingCalculator.Scene.patchesPerSide
        let optical = LightingCalculator.Scene(lights: lights.filter { !$0.kind.emits || $0.isOn }, plan: plan)
        for b in optical.boards {
            var glow: [Int: [Double]] = [1: Array(repeating: 0, count: n * n), -1: Array(repeating: 0, count: n * n)]
            let ab = b.b - b.a
            let abLen2 = max(1e-9, ab.x * ab.x + ab.z * ab.z)
            let patchArea = b.area / Double(n * n)
            for side in [1, -1] {
                let mine = optical.patches.filter { $0.board == b.id && ($0.normal.dot(b.normal) > 0 ? 1 : -1) == side }
                let total = mine.reduce(0) { $0 + $1.intensity }
                guard total > 0 else { continue }
                for q in mine {
                    // A patch facing away from its unit is light that came through the frame.
                    guard let e = optical.emitters.first(where: { $0.id == q.lightID }), (e.position - q.centre).dot(q.normal) < 0 else { continue }
                    let i = min(n - 1, Int(((q.centre.x - b.a.x) * ab.x + (q.centre.z - b.a.z) * ab.z) / abLen2 * Double(n)))
                    let j = min(n - 1, Int((q.centre.y - b.bottom) / max(1e-6, b.top - b.bottom) * Double(n)))
                    glow[side]![max(0, j) * n + max(0, i)] += q.intensity / patchArea
                }
                // Same scale as the units: a source's intensity against the brightest unit's at 3 m.
                let share = brightest > 0 ? total / 9 / brightest : 0
                guard share > 1e-4 else { continue }
                var centre = LightingCalculator.Point(x: 0, y: 0, z: 0)
                for q in mine { centre = centre + q.centre * (q.intensity / total) }
                let normal = b.normal * Double(side)
                let light = SCNLight()
                light.type = .spot
                light.spotInnerAngle = 30
                light.spotOuterAngle = 170
                light.color = UIColor.white
                light.intensity = CGFloat(800 * min(share, 1))
                light.attenuationStartDistance = 0.3
                light.attenuationEndDistance = 14
                light.attenuationFalloffExponent = 2
                let node = SCNNode()
                node.light = light
                let from = centre + normal * 0.03, to = centre + normal
                node.simdPosition = SIMD3(Float(from.x), Float(floorY + from.y), Float(from.z))
                node.look(at: SCNVector3(Float(to.x), Float(floorY + to.y), Float(to.z)))
                gripGlow.addChildNode(node)
            }
            guard let boardNode = lightCache[b.id]?.node else { continue }
            for side in [1, -1] {
                guard let face = boardNode.childNode(withName: "face\(side)", recursively: true)?.geometry?.firstMaterial else { continue }
                let values = glow[side]!
                let peak = values.max() ?? 0
                // A diffusion's far face, as bright against a white card lit by the brightest unit at 3 m.
                let level = brightest > 0 ? min(1, peak * .pi / brightest) : 0
                guard level > 0.002 else { if face.emission.contents is UIImage { face.emission.contents = nil }; continue }
                let image = UIGraphicsImageRenderer(size: CGSize(width: n, height: n)).image { ctx in
                    for j in 0..<n {
                        for i in 0..<n {
                            // Face +1 is turned round, so its picture runs the other way along the board;
                            // image rows run top down.
                            let v = values[j * n + (side > 0 ? n - 1 - i : i)] / peak * level
                            UIColor(white: CGFloat(pow(v, 1 / 2.2)), alpha: 1).setFill()
                            ctx.fill(CGRect(x: i, y: n - 1 - j, width: 1, height: 1))
                        }
                    }
                }
                face.emission.contents = image
                face.emission.magnificationFilter = .linear
            }
        }
    }

    private func buildLight(_ l: LightFixture, selected: Bool, showLabels: Bool, showBeams: Bool, shadow: Bool) -> SCNNode {
        let pan = SCNNode()
        pan.name = "sel:light:\(l.id.uuidString)"
        pan.simdPosition = SIMD3(Float(l.position.x), Float(floorY + l.height), Float(l.position.z))
        pan.simdEulerAngles = SIMD3(0, Float(-l.pan * .pi / 180), 0)
        let tilt = SCNNode()
        tilt.simdEulerAngles = SIMD3(Float(l.tilt * .pi / 180), 0, 0)
        pan.addChildNode(tilt)
        let support = l.supportValue

        if l.kind.emits {
            let pm = l.photometrics
            let color = SceneKitBuilder.uiColor(pm.color)
            tilt.addChildNode(RigModels.lightHead(l, pm: pm, color: color, selected: selected))
            if pm.profile.category == .practical {
                // A practical is its own lamp: a slim pole and base to the floor.
                RigModels.bar(SIMD3(0, -0.05, 0), SIMD3(0, Float(-l.height) + 0.02, 0), radius: 0.008, RigModels.darkMetal, to: pan, segments: 8)
                RigModels.add(SCNCylinder(radius: 0.11, height: 0.025), RigModels.blackMetal, to: pan, at: SIMD3(0, Float(-l.height) + 0.012, 0))
            } else if support != .none {
                let hanging = support == .overhead || support == .megaBoom
                let stud = RigModels.yoke(RigModels.headSize(l, pm: pm), hanging: hanging, to: pan)
                RigModels.stand(support, headHeight: l.height, studY: stud, to: pan)
            }
            if l.isOn && pm.flux > 0 {
                let light = SCNLight()
                switch pm.distribution {
                case .omni, .tube:
                    light.type = .omni
                case .lambertian:
                    light.type = .spot
                    light.spotInnerAngle = 60
                    light.spotOuterAngle = 170
                case .beam:
                    light.type = .spot
                    light.spotInnerAngle = CGFloat(min(pm.beamAngle * 0.6, 170))
                    light.spotOuterAngle = CGFloat(min(pm.beamAngle * 1.35, 175))
                }
                if l.usesRGB {
                    light.color = color
                } else {
                    light.color = UIColor.white
                    light.temperature = CGFloat(pm.kelvin)
                }
                var atFull = l
                atFull.dimmer = 1
                viewportLights[l.id] = (light, pm.illuminanceOnAxis(at: 3), atFull.photometrics.illuminanceOnAxis(at: 3))
                light.attenuationStartDistance = 0.3
                light.attenuationEndDistance = 14
                light.attenuationFalloffExponent = 2
                if light.type == .spot {
                    if pm.barnDoorsAvailable && !l.barnDoorSettings.isOpen {
                        light.gobo?.contents = SceneKitBuilder.barnDoorGobo(l.barnDoorSettings, outerAngle: Double(light.spotOuterAngle))
                    }
                    if shadow {
                        // A shadow takes away this unit's light only, and a bigger source gives a softer edge.
                        let soft = min(1, pm.emitterRadius / 0.5)
                        light.castsShadow = true
                        light.shadowMode = .forward
                        light.shadowColor = UIColor.black
                        light.shadowMapSize = CGSize(width: 2048, height: 2048)
                        light.shadowRadius = CGFloat(2 + soft * 9)
                        light.shadowSampleCount = soft > 0.3 ? 24 : 12
                        light.zNear = 0.1
                        light.zFar = 18
                    }
                }
                let lightNode = SCNNode()
                lightNode.light = light
                // Just in front of the head so the unit doesn't shadow itself.
                lightNode.simdPosition = SIMD3(0, 0, -0.14)
                tilt.addChildNode(lightNode)
                if showBeams {
                    let origin = SIMD3<Float>(0, 0, -0.1)
                    let q = pan.simdOrientation * tilt.simdOrientation
                    let start = pan.simdPosition + q.act(origin)
                    if let beam = SceneKitBuilder.clippedBeam(pm: pm, doors: l.barnDoorSettings, color: color,
                                                              hit: { [weak self] dir in self?.surfaceDistance(from: start, direction: q.act(dir)) }) {
                        beam.simdPosition = origin
                        tilt.addChildNode(beam)
                    }
                }
            }
        } else {
            let h = l.boardHeight ?? (l.kind == .flag ? min(l.width, 0.9) : l.width)
            // Two faces back to back, so each side can show what it does with the light: albedo is
            // the board's reflectance (a faint sheen on black cloth), and the far face of a
            // diffusion glows with what it passes (`setGripGlow`). Face +1 looks the way the board faces.
            let reflectance = BoardOptics.defaults(for: l.kind).reflectance
            for side in [1, -1] {
                let board = SCNPlane(width: CGFloat(l.width), height: CGFloat(h))
                let m = SCNMaterial()
                m.lightingModel = .physicallyBased
                m.diffuse.contents = UIColor(white: CGFloat(pow(reflectance, 1 / 2.2)), alpha: 1)
                m.roughness.contents = 0.95
                m.metalness.contents = 0
                if selected { m.emission.contents = UIColor.white.withAlphaComponent(0.35) }
                board.materials = [m]
                let face = SCNNode(geometry: board)
                face.name = "face\(side)"
                face.simdPosition = SIMD3(0, 0, Float(side) * -0.002)
                if side > 0 { face.simdEulerAngles = SIMD3(0, .pi, 0) }
                tilt.addChildNode(face)
            }
            // Frame round the board, then a grip head down to its stand.
            let hw = Float(l.width / 2), hh = Float(h / 2)
            let corners: [SIMD3<Float>] = [SIMD3(-hw, -hh, 0), SIMD3(hw, -hh, 0), SIMD3(hw, hh, 0), SIMD3(-hw, hh, 0)]
            for i in 0..<4 { RigModels.bar(corners[i], corners[(i + 1) % 4], radius: 0.01, RigModels.steel, to: tilt, segments: 8) }
            let support = l.supportValue
            if support != .none {
                let stud = -Float(h / 2) - 0.03
                RigModels.bar(SIMD3(0, -Float(h / 2), 0), SIMD3(0, stud, 0), radius: 0.008, RigModels.steel, to: pan, segments: 8)
                RigModels.add(SCNCylinder(radius: 0.03, height: 0.02), RigModels.darkMetal, to: pan, at: SIMD3(0, stud, 0), euler: SIMD3(0, 0, .pi / 2))
                RigModels.stand(support, headHeight: l.height, studY: stud - 0.02, to: pan)
            }
        }
        if showLabels {
            let text = l.kind.emits ? "\(l.name) · \(l.isOn ? "\(Int((l.dimmer * 100).rounded())) %" : "off")" : l.name
            let label = SceneKitBuilder.label(text, color: UIColor(white: 0.95, alpha: 1), size: 0.08)
            label.simdPosition = SIMD3(0, 0.35, 0)
            pan.addChildNode(label)
        }
        return pan
    }

    /// Distance from `start` (world node space) along `direction` to the first scan surface or the
    /// floor, within 12 m. nil when the ray leaves the room without meeting anything.
    private func surfaceDistance(from start: SIMD3<Float>, direction: SIMD3<Float>) -> Float? {
        let maxLength: Float = 12
        let d = simd_normalize(direction)
        var best: Float?
        if d.y < -1e-4 {
            let t = (Float(floorY) - start.y) / d.y
            if t > 0, t < maxLength {
                // Only floor inside the room's footprint counts.
                let p = start + d * t
                if roomFootprint.map({ p.x >= $0.lo.x && p.x <= $0.hi.x && p.z >= $0.lo.y && p.z <= $0.hi.y }) ?? true { best = t }
            }
        }
        // Flags, frames and boards stop the beam too.
        for g in beamBlockers {
            let n = LightingCalculator.direction(bearing: g.pan, tilt: g.tilt)
            let r = LightingCalculator.direction(bearing: g.pan + 90, tilt: 0)
            let u = r.cross(n).normalized
            let normal = SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z))
            let denom = simd_dot(d, normal)
            guard abs(denom) > 1e-5 else { continue }
            let centre = SIMD3<Float>(Float(g.position.x), Float(floorY + g.height), Float(g.position.z))
            let t = simd_dot(centre - start, normal) / denom
            guard t > 0.05, t < (best ?? maxLength) else { continue }
            let off = start + d * t - centre
            let h = g.boardHeight ?? (g.kind == .flag ? min(g.width, 0.9) : g.width)
            if abs(simd_dot(off, SIMD3(Float(r.x), Float(r.y), Float(r.z)))) <= Float(g.width / 2),
               abs(simd_dot(off, SIMD3(Float(u.x), Float(u.y), Float(u.z)))) <= Float(h / 2) { best = t }
        }
        let end = start + d * (best ?? maxLength)
        let results = scanHolder.hitTestWithSegment(from: SCNVector3(start.x, start.y, start.z), to: SCNVector3(end.x, end.y, end.z),
                                                    options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
                                                              SCNHitTestOption.backFaceCulling.rawValue: false,
                                                              SCNHitTestOption.ignoreHiddenNodes.rawValue: false])
        if let r = results.first {
            let p = scanHolder.simdConvertPosition(r.simdWorldCoordinates, from: nil)
            let t = simd_length(p - start)
            if t > 0.05 { best = min(best ?? t, t) }
        }
        return best
    }

    /// White ring on the floor under the selected item.
    func showSelection(at p: PlanPoint?, radius: Double = 0.4) {
        guard let p else { selectionRing.isHidden = true; return }
        (selectionRing.geometry as? SCNTorus)?.ringRadius = CGFloat(radius)
        selectionRing.simdPosition = SIMD3(Float(p.x), Float(floorY) + 0.01, Float(p.z))
        selectionRing.isHidden = false
    }

    /// Points the directional light from the sun's world direction.
    func setSun(worldBearing: Double?, elevation: Double?) {
        let centre = worldPoint(roomCentre)
        sunIsSet = worldBearing != nil && elevation != nil
        guard let worldBearing, let elevation else {
            sunNode.simdPosition = centre + SIMD3(3, 10, 4)
            sunNode.simdLook(at: centre)
            sunNode.light?.intensity = 900
            return
        }
        let b = worldBearing * .pi / 180, e = max(elevation, 0) * .pi / 180
        let towardsSun = SIMD3<Float>(Float(sin(b) * cos(e)), Float(sin(e)), Float(-cos(b) * cos(e)))
        sunNode.simdPosition = centre + towardsSun * 20
        sunNode.simdLook(at: centre)
        sunNode.light?.intensity = elevation > 0 ? CGFloat(400 + 1400 * sin(e)) : 0
    }

    /// Item under a screen point: the first node up the hierarchy named "sel:<kind>:<uuid>",
    /// or a set piece from the scan.
    func hit(at point: CGPoint, in view: SCNView) -> PlanSelection? {
        let results = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                                                    SCNHitTestOption.ignoreHiddenNodes: true])
        for r in results {
            var n: SCNNode? = r.node
            while let node = n {
                if let name = node.name, name.hasPrefix("sel:") {
                    let parts = name.split(separator: ":")
                    if parts.count == 3, let id = UUID(uuidString: String(parts[2])) {
                        switch parts[1] {
                        case "light": return .light(id)
                        case "camera": return .camera(id)
                        case "shot": return .shot(id)
                        case "character": return .character(id)
                        case "meter": return .meter(id)
                        default: break
                        }
                    }
                }
                if let item = (scanItems + handItems).first(where: { $0.node === node }), group(for: item.category) == .furniture, let id = item.id {
                    return .object(id)
                }
                n = node.parent
            }
        }
        return nil
    }
}

/// SceneKit view. In orbit mode: drag to orbit, two fingers to slide over the floor, pinch to zoom,
/// twist to turn the view, double-tap to centre on a spot; tap selects, press-and-hold then drag
/// moves the item, two-finger twist on an item turns it. The camera only moves on the main thread.
struct SceneKitContainer: UIViewRepresentable {
    let model: VirtualSceneModel
    var orbit: Bool
    var onSelect: ((PlanSelection?) -> Void)? = nil
    /// Moving an item: the selection, its new plan position.
    var onMove: ((PlanSelection, PlanPoint) -> Void)? = nil
    /// Turning an item by a number of degrees (clockwise seen from above).
    var onRotate: ((PlanSelection, Double) -> Void)? = nil
    /// Height above the floor at which an item is dragged.
    var dragHeight: ((PlanSelection) -> Double)? = nil
    /// Tap with the item hit (if any) and the floor point under the finger; replaces `onSelect` for taps.
    var onTap: ((PlanSelection?, PlanPoint?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = model.scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.pointOfView = orbit ? model.orbitCameraNode : model.cameraNode
        view.allowsCameraControl = false
        if orbit { model.attach(view) }
        let c = context.coordinator
        c.view = view
        if !orbit { model.wallFader.restore() }
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        if orbit {
            let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap(_:)))
            double.numberOfTapsRequired = 2
            view.addGestureRecognizer(double)
            tap.require(toFail: double)
            let drag = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.orbitDrag(_:)))
            drag.maximumNumberOfTouches = 1
            drag.delegate = c
            view.addGestureRecognizer(drag)
            let slide = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.slide(_:)))
            slide.minimumNumberOfTouches = 2
            slide.delegate = c
            view.addGestureRecognizer(slide)
            let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
            pinch.delegate = c
            view.addGestureRecognizer(pinch)
        }
        let press = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.3
        press.delegate = c
        view.addGestureRecognizer(press)
        let rotate = UIRotationGestureRecognizer(target: c, action: #selector(Coordinator.rotate(_:)))
        rotate.delegate = c
        view.addGestureRecognizer(rotate)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        let pov = orbit ? model.orbitCameraNode : model.cameraNode
        if view.pointOfView !== pov { view.pointOfView = pov }
        // Re-claim the shared orbit camera after another view (e.g. the alignment sheet) used it.
        if orbit { model.attach(view) }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.delegate = nil
        view.gestureRecognizers?.forEach(view.removeGestureRecognizer)
        coordinator.parent = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SceneKitContainer?
        weak var view: SCNView?
        private var dragItem: PlanSelection?
        private var rotateItem: PlanSelection?
        private var lastRotation: CGFloat = 0
        private var lastScale: CGFloat = 1

        @MainActor @objc func tap(_ g: UITapGestureRecognizer) {
            guard let parent, let view else { return }
            let point = g.location(in: view)
            let item = parent.model.hit(at: point, in: view)
            if let onTap = parent.onTap {
                onTap(item, parent.model.planPoint(at: point, in: view, height: 0))
            } else {
                parent.onSelect?(item)
            }
        }

        @MainActor @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let parent, let view, let p = parent.model.surfacePoint(at: g.location(in: view), in: view) else { return }
            parent.model.centre(onWorld: p)
        }

        @MainActor @objc func orbitDrag(_ g: UIPanGestureRecognizer) {
            guard let parent, let view, dragItem == nil else { return }
            let t = g.translation(in: view)
            parent.model.orbitBy(dx: t.x, dy: t.y)
            g.setTranslation(.zero, in: view)
        }

        @MainActor @objc func slide(_ g: UIPanGestureRecognizer) {
            guard let parent, let view, dragItem == nil else { return }
            let t = g.translation(in: view)
            parent.model.panBy(dx: t.x, dy: t.y, viewHeight: view.bounds.height)
            g.setTranslation(.zero, in: view)
        }

        @MainActor @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let parent else { return }
            switch g.state {
            case .began: lastScale = 1
            case .changed:
                parent.model.zoomBy(g.scale / lastScale)
                lastScale = g.scale
            default: break
            }
        }

        @MainActor @objc func press(_ g: UILongPressGestureRecognizer) {
            guard let parent, let view, parent.onMove != nil else { return }
            switch g.state {
            case .began:
                guard let item = parent.model.hit(at: g.location(in: view), in: view), item.isMovable else { return }
                dragItem = item
                parent.onSelect?(item)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .changed:
                guard let item = dragItem else { return }
                let h = parent.dragHeight?(item) ?? 0
                if let p = parent.model.planPoint(at: g.location(in: view), in: view, height: h) { parent.onMove?(item, p) }
            default:
                dragItem = nil
            }
        }

        @MainActor @objc func rotate(_ g: UIRotationGestureRecognizer) {
            guard let parent, let view else { return }
            switch g.state {
            case .began:
                rotateItem = parent.onRotate == nil ? nil : parent.model.hit(at: g.location(in: view), in: view)
                lastRotation = 0
            case .changed:
                let delta = g.rotation - lastRotation
                lastRotation = g.rotation
                if let item = rotateItem {
                    parent.onRotate?(item, Double(delta) * 180 / .pi)
                } else if parent.orbit {
                    parent.model.turnBy(radians: delta)
                }
            default:
                rotateItem = nil
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Pinch, twist and two-finger slide work together; holding to move an item doesn't mix.
            let together: (UIGestureRecognizer) -> Bool = { $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer || ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2 }
            return together(g) && together(other)
        }
    }
}
