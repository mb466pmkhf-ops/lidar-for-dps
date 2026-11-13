import SceneKit
import UIKit

/// What the 3D view needs to draw a studio set and daylight (see `Stage`). Picture only: how bright
/// things look here is not a reading.
struct StageVisuals: Hashable {
    /// Every piece of the backdrop (one per wall) and the corners where pieces meet.
    var backdrop: Stage.BackdropLayout?
    var ledNits: Double = Stage.ledDefaultNits
    var ledKelvin: Double = 5600
    var floor: FloorInfo?
    var floorColour: String?
    /// Windows with curtains, each with its into-the-room direction.
    var curtains: [Curtain] = []
    var floorPolygons: [[PlanPoint]] = []
    var floorY: Double = 0
    /// Highest wall top, for the shadow lid.
    var ceiling: Double = 2.6
    var daylight: Daylight?

    struct Curtain: Hashable { var window: PlanSegment; var kind: CurtainKind; var inward: PlanPoint }

    struct Daylight: Hashable {
        var sky: SkyKind
        /// Plan bearing the sun shines from, and its height in degrees.
        var bearing: Double
        var elevation: Double
        var directNormal: Double
        var windowLuminance: Double
    }
}

/// SceneKit pieces for `StageVisuals`: cyc and paper sweeps, LED wall, floor finish, curtains, sky.
enum StageSceneKit {
    static func build(_ v: StageVisuals) -> SCNNode {
        let root = SCNNode()
        root.name = "stage"
        if let layout = v.backdrop {
            for bd in layout.pieces { root.addChildNode(named(backdrop(bd, v: v), cutawayName)) }
            for c in layout.corners { root.addChildNode(named(corner(c, layout: layout, v: v), cutawayName)) }
        }
        if let f = v.floor { root.addChildNode(floor(f, colour: v.floorColour, polygons: v.floorPolygons, y: v.floorY)) }
        for c in v.curtains { root.addChildNode(named(curtain(c, v: v), cutawayName)) }
        if v.daylight != nil { root.addChildNode(lid(v)) }
        return root
    }

    /// Name of the pieces that stand against a wall (backdrops, corners, curtains): the dollhouse
    /// view cuts them away with the walls, or a backdrop on a camera-side wall blocks the view.
    static let cutawayName = "stage:cutaway"

    /// The pieces of a built stage that are cut away with the walls.
    static func cutawayPieces(_ root: SCNNode) -> [SCNNode] {
        root.childNodes(passingTest: { n, _ in n.name == cutawayName })
    }

    private static func named(_ n: SCNNode, _ name: String) -> SCNNode { n.name = name; return n }

    // MARK: Backdrop

    /// Wall-to-floor profile as (distance into the room, height) pairs.
    private static func profile(height: Double, sweep: Double, radius: Double) -> [(d: Double, y: Double)] {
        guard sweep > 0 else { return [(0, height), (0, 0)] }
        let r = min(radius, height * 0.5, sweep * 0.8)
        var pts: [(d: Double, y: Double)] = [(0, height)]
        let steps = 10
        for i in 0...steps {
            let t = Double(i) / Double(steps) * .pi / 2
            pts.append((r - r * cos(t), r - r * sin(t)))
        }
        pts.append((sweep, 0))
        return pts
    }

    /// A strip swept between the backdrop's two ends along `profile`.
    private static func sheet(_ bd: Stage.BackdropPlacement, profile: [(d: Double, y: Double)], floorY: Double) -> SCNGeometry {
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        var run = 0.0
        for (i, p) in profile.enumerated() {
            if i > 0 { run += hypot(p.d - profile[i - 1].d, p.y - profile[i - 1].y) }
            // Normal of the profile at this point, pointing into the room / up.
            let q0 = profile[max(0, i - 1)], q1 = profile[min(profile.count - 1, i + 1)]
            let td = q1.d - q0.d, ty = q1.y - q0.y
            let tl = max(hypot(td, ty), 1e-6)
            let nd = -ty / tl, ny = td / tl
            for (end, u) in [(bd.a, 0.0), (bd.b, 1.0)] {
                verts.append(SCNVector3(Float(end.x + bd.inward.x * p.d), Float(floorY + p.y + 0.004), Float(end.z + bd.inward.z * p.d)))
                normals.append(SCNVector3(Float(bd.inward.x * nd), Float(ny), Float(bd.inward.z * nd)))
                uvs.append(CGPoint(x: u, y: run))
            }
            if i > 0 {
                let a = Int32((i - 1) * 2), b = a + 1, c = a + 2, d = a + 3
                idx += [a, c, b, b, c, d]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    private static func backdrop(_ bd: Stage.BackdropPlacement, v: StageVisuals) -> SCNNode {
        let node = SCNNode()
        let colour = UIColor(hex: bd.colour)
        switch bd.info.kind {
        case .cyc, .paper:
            let radius = bd.info.kind == .cyc ? 0.6 : 0.45
            let g = sheet(bd, profile: profile(height: bd.height, sweep: bd.sweep, radius: radius), floorY: v.floorY)
            let m = SceneKitBuilder.material(colour, roughness: bd.info.kind == .cyc ? 0.9 : 0.75)
            m.isDoubleSided = true
            g.materials = [m]
            node.addChildNode(SCNNode(geometry: g))
            if bd.info.kind == .paper { node.addChildNode(paperStands(bd, floorY: v.floorY)) }
        case .led:
            let g = sheet(bd, profile: profile(height: bd.height, sweep: 0, radius: 0), floorY: v.floorY)
            let k = Kelvin.rgb(v.ledKelvin)
            // Brighter set → brighter face, but this is the look, not a level.
            let glow = CGFloat(min(1, 0.25 + v.ledNits / 800))
            let m = SceneKitBuilder.material(.black, emission: UIColor(red: CGFloat(k.r) * glow, green: CGFloat(k.g) * glow, blue: CGFloat(k.b) * glow, alpha: 1),
                                             roughness: 0.35)
            m.isDoubleSided = true
            g.materials = [m]
            let face = SCNNode(geometry: g)
            face.castsShadow = false
            node.addChildNode(face)
            // The light the wall throws into the room.
            let light = SCNLight()
            light.type = .area
            light.areaType = .rectangle
            light.areaExtents = simd_float3(Float(bd.width), Float(bd.height), 0)
            light.drawsArea = false
            light.intensity = CGFloat(min(4000, v.ledNits * 3))
            light.temperature = CGFloat(v.ledKelvin)
            let ln = SCNNode()
            ln.light = light
            let mid = PlanPoint(x: (bd.a.x + bd.b.x) / 2, z: (bd.a.z + bd.b.z) / 2)
            ln.simdPosition = SIMD3(Float(mid.x + bd.inward.x * 0.02), Float(v.floorY + bd.height / 2), Float(mid.z + bd.inward.z * 0.02))
            ln.simdLook(at: ln.simdPosition + SIMD3(Float(bd.inward.x), 0, Float(bd.inward.z)))
            node.addChildNode(ln)
        }
        return node
    }

    /// Where two pieces meet: a cyc bends round a vertical radius (its floor cove swung round the
    /// corner), and cyc and paper get the floor between the two sweeps. LED pieces just butt together.
    private static func corner(_ c: Stage.BackdropCorner, layout: Stage.BackdropLayout, v: StageVisuals) -> SCNNode {
        let node = SCNNode()
        let kind = layout.info.kind
        guard kind != .led else { return node }
        let m = SceneKitBuilder.material(UIColor(hex: layout.colour), roughness: kind == .cyc ? 0.9 : 0.75)
        m.isDoubleSided = true
        let base = v.floorY + c.bottom
        if c.radius > 0.05 {
            let coveR = min(0.6, c.height * 0.5, layout.sweep * 0.8, c.radius - 0.05)
            let prof = profile(height: c.height, sweep: layout.sweep, radius: coveR).filter { $0.d <= coveR + 1e-6 }
            let a0 = atan2(c.tangentA.z - c.centre.z, c.tangentA.x - c.centre.x)
            var da = atan2(c.tangentB.z - c.centre.z, c.tangentB.x - c.centre.x) - a0
            while da > .pi { da -= 2 * .pi }
            while da < -.pi { da += 2 * .pi }
            let steps = 16
            var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [Int32] = []
            for k in 0...steps {
                let a = a0 + da * Double(k) / Double(steps)
                let dir = PlanPoint(x: cos(a), z: sin(a))
                for (i, p) in prof.enumerated() {
                    let q0 = prof[max(0, i - 1)], q1 = prof[min(prof.count - 1, i + 1)]
                    let td = q1.d - q0.d, ty = q1.y - q0.y
                    let tl = max(hypot(td, ty), 1e-6)
                    let nd = -ty / tl, ny = td / tl
                    let r = c.radius - p.d
                    verts.append(SCNVector3(Float(c.centre.x + dir.x * r), Float(base + p.y + 0.004), Float(c.centre.z + dir.z * r)))
                    // Into the room is towards the centre.
                    normals.append(SCNVector3(Float(-dir.x * nd), Float(ny), Float(-dir.z * nd)))
                }
            }
            let n = Int32(prof.count)
            for k in 0..<Int32(steps) {
                for i in 0..<(n - 1) {
                    let p = k * n + i, q = p + n
                    idx += [p, q, p + 1, p + 1, q, q + 1]
                }
            }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                                elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            g.materials = [m]
            node.addChildNode(SCNNode(geometry: g))
        }
        // The floor between the two sweeps.
        let foot = Stage.cornerFootprint(c, sweep: max(layout.sweep, 0.3))
        if foot.count >= 3 {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: foot[0].x, y: -foot[0].z))
            for p in foot.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: -p.z)) }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0)
            shape.materials = [m]
            let f = SCNNode(geometry: shape)
            f.eulerAngles.x = -.pi / 2
            f.simdPosition = SIMD3(0, Float(base + 0.004), 0)
            f.castsShadow = false
            node.addChildNode(f)
        }
        return node
    }

    private static func paperStands(_ bd: Stage.BackdropPlacement, floorY: Double) -> SCNNode {
        let n = SCNNode()
        let metal = SceneKitBuilder.material(UIColor(white: 0.18, alpha: 1), roughness: 0.4)
        metal.metalness.contents = 0.6
        let top = bd.height + 0.08
        let u = PlanPoint(x: bd.b.x - bd.a.x, z: bd.b.z - bd.a.z) * (1 / max(bd.width, 1e-6))
        for (end, sign) in [(bd.a, -1.0), (bd.b, 1.0)] {
            let p = end + u * (0.08 * sign) + bd.inward * -0.05
            let pole = SCNCylinder(radius: 0.015, height: CGFloat(top))
            pole.materials = [metal]
            let pn = SCNNode(geometry: pole)
            pn.simdPosition = SIMD3(Float(p.x), Float(floorY + top / 2), Float(p.z))
            n.addChildNode(pn)
        }
        let bar = SCNCylinder(radius: 0.02, height: CGFloat(bd.width + 0.2))
        bar.materials = [metal]
        let bn = SCNNode(geometry: bar)
        let mid = PlanPoint(x: (bd.a.x + bd.b.x) / 2, z: (bd.a.z + bd.b.z) / 2) + bd.inward * 0.03
        bn.simdPosition = SIMD3(Float(mid.x), Float(floorY + top), Float(mid.z))
        // Cylinders stand on Y; lay it along the wall.
        bn.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(SIMD3(Float(u.x), 0, Float(u.z))))
        n.addChildNode(bn)
        return n
    }

    // MARK: Floor

    private static func floor(_ f: FloorInfo, colour: String?, polygons: [[PlanPoint]], y: Double) -> SCNNode {
        let node = SCNNode()
        let m = SceneKitBuilder.material(UIColor(hex: f.pickColour ? (colour ?? f.colour) : f.colour), roughness: CGFloat(f.roughness))
        m.isDoubleSided = true
        for poly in polygons where poly.count >= 3 {
            let path = UIBezierPath()
            // Shape is drawn in X/Y and turned flat, so plan z becomes −y.
            path.move(to: CGPoint(x: poly[0].x, y: -poly[0].z))
            for p in poly.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: -p.z)) }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0)
            shape.materials = [m]
            let n = SCNNode(geometry: shape)
            n.eulerAngles.x = -.pi / 2
            n.simdPosition = SIMD3(0, Float(y + 0.003), 0)
            n.castsShadow = false
            node.addChildNode(n)
        }
        return node
    }

    // MARK: Curtains

    private static func curtain(_ c: StageVisuals.Curtain, v: StageVisuals) -> SCNNode {
        let w = c.window, kind = c.kind
        let len = max(w.length, 0.1)
        let width = len + 0.3
        let top = min(w.bottom + w.height + 0.15, v.ceiling)
        let bottom = max(0, w.bottom - 0.1)
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(max(0.2, top - bottom)))
        let m = SCNMaterial()
        m.isDoubleSided = true
        m.lightingModel = .physicallyBased
        m.roughness.contents = 1
        if kind == .blackout {
            m.diffuse.contents = UIColor(white: 0.07, alpha: 1)
        } else {
            m.diffuse.contents = UIColor(white: 0.95, alpha: 1)
            m.transparency = 0.55
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
            if let d = v.daylight {
                // Lit from behind by the window; brighter with the sun on it. A look, not a level.
                let glow = CGFloat(min(0.9, 0.15 + d.windowLuminance / 8000 + d.directNormal / 200_000))
                m.emission.contents = UIColor(white: glow, alpha: 1)
            }
        }
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.castsShadow = kind == .blackout
        let mid = w.midpoint + c.inward * 0.08
        n.simdPosition = SIMD3(Float(mid.x), Float(v.floorY + (top + bottom) / 2), Float(mid.z))
        n.simdEulerAngles.y = Float(-atan2(w.b.z - w.a.z, w.b.x - w.a.x))
        return n
    }

    // MARK: Daylight

    /// An invisible ceiling that only casts shadow, so the sun comes in through the windows and not
    /// through the open top of the scan.
    private static func lid(_ v: StageVisuals) -> SCNNode {
        let pts = v.floorPolygons.flatMap { $0 }
        let xs = pts.map(\.x), zs = pts.map(\.z)
        let lo = PlanPoint(x: (xs.min() ?? -5) - 0.5, z: (zs.min() ?? -5) - 0.5)
        let hi = PlanPoint(x: (xs.max() ?? 5) + 0.5, z: (zs.max() ?? 5) + 0.5)
        let plane = SCNPlane(width: CGFloat(hi.x - lo.x), height: CGFloat(hi.z - lo.z))
        let m = SCNMaterial()
        m.colorBufferWriteMask = []
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.name = "stage:lid"
        n.eulerAngles.x = -.pi / 2
        n.simdPosition = SIMD3(Float((lo.x + hi.x) / 2), Float(v.floorY + v.ceiling + 0.02), Float((lo.z + hi.z) / 2))
        n.castsShadow = true
        return n
    }

    /// Sky colour behind the scene, top and bottom (0…1 RGB), by sky kind and sun height.
    static func skyImage(_ d: StageVisuals.Daylight) -> UIImage {
        let day = max(0, min(1, (d.elevation + 6) / 16))
        let top: UIColor, bottom: UIColor
        switch d.sky {
        case .clear:
            top = UIColor(red: 0.20 * day + 0.02, green: 0.42 * day + 0.03, blue: 0.80 * day + 0.06, alpha: 1)
            bottom = UIColor(red: 0.72 * day + 0.05, green: 0.82 * day + 0.05, blue: 0.92 * day + 0.08, alpha: 1)
        case .hazy:
            top = UIColor(red: 0.45 * day + 0.03, green: 0.55 * day + 0.03, blue: 0.70 * day + 0.05, alpha: 1)
            bottom = UIColor(red: 0.82 * day + 0.04, green: 0.84 * day + 0.04, blue: 0.86 * day + 0.05, alpha: 1)
        case .overcast:
            top = UIColor(white: 0.55 * day + 0.03, alpha: 1)
            bottom = UIColor(white: 0.75 * day + 0.04, alpha: 1)
        }
        let size = CGSize(width: 8, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: cs, colors: [top.cgColor, bottom.cgColor, UIColor(white: 0.25 * day + 0.03, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 0.5, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }
}
