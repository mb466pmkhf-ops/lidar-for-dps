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
        material.roughness.contents = CGFloat(mesh.material.roughness)
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

    /// Mannequin with believable proportions: clear silhouette, skin-toned head and hands,
    /// neutral clothing so the light on it reads. A small nose shows which way the person faces.
    static func figure(_ c: PrevisCharacter, selected: Bool) -> SCNNode {
        let p = c.proportions
        let root = SCNNode()
        let skin = material(uiColor(c.skinTone.rgb), roughness: 0.55)
        let top = material(UIColor(white: 0.55, alpha: 1), roughness: 0.85)
        let legs = material(UIColor(white: 0.32, alpha: 1), roughness: 0.85)
        if selected {
            for m in [top, legs] { m.emission.contents = UIColor(white: 0.18, alpha: 1) }
        }
        func capsule(_ r: Double, _ length: Double, _ m: SCNMaterial) -> SCNNode {
            let g = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(max(length, 2 * r + 0.001)))
            g.materials = [m]
            return SCNNode(geometry: g)
        }
        func place(_ n: SCNNode, _ x: Double, _ y: Double, _ z: Double) -> SCNNode {
            n.simdPosition = SIMD3(Float(x), Float(y), Float(z))
            root.addChildNode(n)
            return n
        }
        let legSpread = p.hipWidth * 0.26
        if p.sitting {
            // Thighs forward (−Z is the facing direction), shins down to the floor.
            let thigh = p.hipHeight * 0.0 + p.legRadius
            for s in [-1.0, 1.0] {
                let t = capsule(p.legRadius, c.height * 0.25, legs)
                t.simdEulerAngles = SIMD3(Float.pi / 2, 0, 0)
                _ = place(t, s * legSpread, p.seatHeight + thigh, -c.height * 0.11)
                let shin = capsule(p.legRadius * 0.85, p.seatHeight + p.legRadius, legs)
                _ = place(shin, s * legSpread, (p.seatHeight + p.legRadius) / 2, -c.height * 0.23)
            }
            // A stool so a seated figure doesn't float.
            let seat = SCNBox(width: CGFloat(p.hipWidth * 1.3), height: CGFloat(p.seatHeight), length: CGFloat(p.hipWidth * 1.2), chamferRadius: 0.01)
            seat.materials = [material(UIColor(white: 0.2, alpha: 1))]
            _ = place(SCNNode(geometry: seat), 0, p.seatHeight / 2, 0.02)
        } else {
            for s in [-1.0, 1.0] {
                let leg = capsule(p.legRadius, p.hipHeight, legs)
                _ = place(leg, s * legSpread, p.hipHeight / 2, 0)
            }
        }
        // Hips and torso.
        let hip = SCNBox(width: CGFloat(p.hipWidth), height: CGFloat(c.height * 0.09), length: CGFloat(p.chestDepth * 0.95), chamferRadius: CGFloat(p.chestDepth * 0.4))
        hip.materials = [legs]
        _ = place(SCNNode(geometry: hip), 0, p.hipHeight + c.height * 0.02, 0)
        let torsoHeight = p.shoulderHeight - p.hipHeight
        let torso = SCNBox(width: CGFloat(p.shoulderWidth * 0.86), height: CGFloat(torsoHeight), length: CGFloat(p.chestDepth),
                           chamferRadius: CGFloat(min(p.chestDepth, p.shoulderWidth) * 0.45))
        torso.materials = [top]
        _ = place(SCNNode(geometry: torso), 0, p.hipHeight + torsoHeight / 2 + c.height * 0.02, 0)
        // Arms hang from the shoulders.
        for s in [-1.0, 1.0] {
            let arm = capsule(p.armRadius, p.armLength, top)
            _ = place(arm, s * (p.shoulderWidth / 2 - p.armRadius * 0.4), p.shoulderHeight - p.armLength / 2 + p.armRadius, 0)
            let hand = SCNSphere(radius: CGFloat(p.armRadius * 1.15))
            hand.materials = [skin]
            _ = place(SCNNode(geometry: hand), s * (p.shoulderWidth / 2 - p.armRadius * 0.4), p.shoulderHeight - p.armLength + p.armRadius * 0.4, 0)
        }
        // Neck and head.
        let neck = SCNCylinder(radius: CGFloat(p.headWidth * 0.3), height: CGFloat(p.neckBase - p.shoulderHeight + p.headHeight * 0.25))
        neck.materials = [skin]
        _ = place(SCNNode(geometry: neck), 0, (p.shoulderHeight + p.neckBase) / 2 + p.headHeight * 0.1, 0)
        let head = SCNSphere(radius: CGFloat(p.headWidth / 2))
        head.materials = [skin]
        let headNode = place(SCNNode(geometry: head), 0, p.top - p.headHeight / 2, 0)
        headNode.scale = SCNVector3(1, Float(p.headHeight / p.headWidth), 1.1)
        let nose = SCNBox(width: CGFloat(p.headWidth * 0.16), height: CGFloat(p.headHeight * 0.16), length: CGFloat(p.headWidth * 0.25), chamferRadius: 0.004)
        nose.materials = [skin]
        _ = place(SCNNode(geometry: nose), 0, p.eyeHeight - p.headHeight * 0.12, -p.headWidth * 0.55)
        return root
    }

    // MARK: Cameras

    /// Cinema camera: body, lens whose length follows the focal length, matte box, a tripod to the
    /// floor (reads the height), and the frame's field of view drawn out to `reach`.
    static func cameraModel(rig: CameraRig, color: UIColor, label text: String?, reach: Double, selected: Bool) -> SCNNode {
        let root = SCNNode()
        let head = SCNNode()
        head.simdEulerAngles = SIMD3(0, Float(-rig.pan * .pi / 180), 0)
        let tilt = SCNNode()
        tilt.simdEulerAngles = SIMD3(Float(rig.tilt * .pi / 180), 0, 0)
        head.addChildNode(tilt)
        head.simdPosition = SIMD3(0, Float(rig.height), 0)
        root.addChildNode(head)

        let bodyM = material(UIColor(white: 0.16, alpha: 1), emission: selected ? color.withAlphaComponent(0.35) : nil, roughness: 0.5)
        let accent = material(color, constant: true)
        let body = SCNBox(width: 0.13, height: 0.15, length: 0.24, chamferRadius: 0.012)
        body.materials = [bodyM]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.simdPosition = SIMD3(0, 0, 0.08)
        tilt.addChildNode(bodyNode)
        // Top handle and an accent stripe so cameras are easy to tell from lights.
        let handle = SCNBox(width: 0.03, height: 0.03, length: 0.18, chamferRadius: 0.008)
        handle.materials = [accent]
        let handleNode = SCNNode(geometry: handle)
        handleNode.simdPosition = SIMD3(0, 0.1, 0.08)
        tilt.addChildNode(handleNode)
        // Lens: longer for longer focal lengths.
        let lensLength = Float(min(0.32, 0.06 + rig.focalLength / 450))
        let lens = SCNCylinder(radius: 0.045, height: CGFloat(lensLength))
        lens.materials = [material(UIColor(white: 0.08, alpha: 1), roughness: 0.4)]
        let lensNode = SCNNode(geometry: lens)
        lensNode.simdEulerAngles = SIMD3(Float.pi / 2, 0, 0)
        lensNode.simdPosition = SIMD3(0, 0, -0.04 - lensLength / 2)
        tilt.addChildNode(lensNode)
        let ring = SCNTorus(ringRadius: 0.047, pipeRadius: 0.006)
        ring.materials = [accent]
        let ringNode = SCNNode(geometry: ring)
        ringNode.simdEulerAngles = SIMD3(Float.pi / 2, 0, 0)
        ringNode.simdPosition = SIMD3(0, 0, -0.04 - lensLength)
        tilt.addChildNode(ringNode)
        // Matte box: a short open frustum in front of the lens, shaped to the frame.
        let area = rig.imageArea
        let mbW = Float(0.16), mbH = Float(0.16 * area.height / area.width)
        let mbZ = -0.06 - lensLength
        let corners: [SIMD3<Float>] = [SIMD3(-mbW / 2, -mbH / 2, mbZ), SIMD3(mbW / 2, -mbH / 2, mbZ),
                                       SIMD3(mbW / 2, mbH / 2, mbZ), SIMD3(-mbW / 2, mbH / 2, mbZ)]
        tilt.addChildNode(lines((0..<4).map { (corners[$0], corners[($0 + 1) % 4]) }, color: UIColor(white: 0.6, alpha: 1)))

        // Field of view: frame rectangle at `reach`, joined to the lens.
        let hx = Float(tan(rig.horizontalFOV * .pi / 360) * reach)
        let hy = Float(tan(rig.verticalFOV * .pi / 360) * reach)
        let z = Float(-reach)
        let apex = SIMD3<Float>(0, 0, -0.04 - lensLength)
        let frame: [SIMD3<Float>] = [SIMD3(-hx, -hy, z), SIMD3(hx, -hy, z), SIMD3(hx, hy, z), SIMD3(-hx, hy, z)]
        var pairs = (0..<4).map { (frame[$0], frame[($0 + 1) % 4]) }
        pairs += frame.map { (apex, $0) }
        tilt.addChildNode(lines(pairs, color: color.withAlphaComponent(selected ? 0.9 : 0.5)))

        // Tripod: three legs from the head to the floor.
        let legM = material(UIColor(white: 0.25, alpha: 1))
        let h = Float(max(rig.height - 0.08, 0.1))
        for i in 0..<3 {
            let a = Float(i) * 2 * .pi / 3 + Float(-rig.pan * .pi / 180)
            let foot = SIMD3<Float>(sin(a) * h * 0.38, -h, cos(a) * h * 0.38)
            let len = simd_length(foot)
            let leg = SCNCylinder(radius: 0.008, height: CGFloat(len))
            leg.materials = [legM]
            let legNode = SCNNode(geometry: leg)
            legNode.simdPosition = SIMD3(0, Float(rig.height) - 0.08, 0) + foot / 2
            legNode.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(-foot))
            root.addChildNode(legNode)
        }
        if let text {
            let l = label(text, color: color)
            l.simdPosition = SIMD3(0, Float(rig.height) + 0.2, 0)
            root.addChildNode(l)
        }
        root.simdPosition = SIMD3(Float(rig.position.x), 0, Float(rig.position.z))
        return root
    }

    // MARK: Lights

    /// Head for a lighting unit, shaped by its type and modifier, facing −Z.
    static func lightHead(_ l: LightFixture, pm: ResolvedPhotometrics, color: UIColor, selected: Bool) -> SCNNode {
        let node = SCNNode()
        let on = l.isOn
        let glow = material(on ? color : UIColor(white: 0.3, alpha: 1), emission: on ? color : nil, constant: on)
        let housing = material(UIColor(white: 0.14, alpha: 1), emission: selected ? UIColor(white: 0.35, alpha: 1) : nil, roughness: 0.5)
        let size = pm.modifier?.size
        switch (pm.modifier?.distribution ?? pm.profile.distribution, pm.profile.category) {
        case (.omni, _):
            let r = CGFloat((size ?? max(pm.profile.emitterWidth, 0.08)) / 2)
            let g = SCNSphere(radius: r)
            g.materials = [glow]
            node.addChildNode(SCNNode(geometry: g))
        case (_, .tube):
            let g = SCNCylinder(radius: 0.02, height: CGFloat(pm.profile.emitterWidth))
            g.materials = [glow]
            let n = SCNNode(geometry: g)
            n.simdEulerAngles = SIMD3(0, 0, Float.pi / 2)
            node.addChildNode(n)
        case (_, .panel), (_, .soft):
            let w = CGFloat(size ?? pm.profile.emitterWidth), h = CGFloat(size ?? pm.profile.emitterHeight)
            let box = SCNBox(width: w + 0.02, height: h + 0.02, length: 0.05, chamferRadius: 0.005)
            box.materials = [housing]
            node.addChildNode(SCNNode(geometry: box))
            let face = SCNPlane(width: w, height: h)
            face.materials = [glow]
            let f = SCNNode(geometry: face)
            f.simdPosition = SIMD3(0, 0, -0.026)
            f.simdEulerAngles = SIMD3(0, Float.pi, 0)
            node.addChildNode(f)
        default:
            if let size {
                // Softbox: pyramid with its base facing forward.
                let depth = CGFloat(size * 0.6)
                let pyr = SCNPyramid(width: CGFloat(size), height: depth, length: CGFloat(size))
                pyr.materials = [housing]
                let p = SCNNode(geometry: pyr)
                p.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
                p.simdPosition = SIMD3(0, 0, Float(depth))
                node.addChildNode(p)
                let face = SCNPlane(width: CGFloat(size), height: CGFloat(size))
                face.materials = [glow]
                let f = SCNNode(geometry: face)
                f.simdEulerAngles = SIMD3(0, Float.pi, 0)
                f.simdPosition = SIMD3(0, 0, -0.005)
                node.addChildNode(f)
            } else {
                let body = SCNBox(width: 0.22, height: 0.24, length: 0.3, chamferRadius: 0.02)
                body.materials = [housing]
                let b = SCNNode(geometry: body)
                b.simdPosition = SIMD3(0, 0, 0.15)
                node.addChildNode(b)
                let lens = SCNCylinder(radius: 0.095, height: 0.02)
                lens.materials = [glow]
                let ln = SCNNode(geometry: lens)
                ln.simdEulerAngles = SIMD3(Float.pi / 2, 0, 0)
                ln.simdPosition = SIMD3(0, 0, -0.01)
                node.addChildNode(ln)
            }
        }
        // Barn doors: four leaves hinged at the front, angled to their cut.
        if pm.barnDoorsAvailable, l.barnDoors != nil {
            let d = l.barnDoorSettings
            let leafM = material(UIColor(white: 0.1, alpha: 1))
            let half: Float = 0.12
            let leaves: [(Double, SIMD3<Float>, SIMD3<Float>)] = [
                (d.top, SIMD3(0, half, 0), SIMD3(1, 0, 0)),
                (d.bottom, SIMD3(0, -half, 0), SIMD3(-1, 0, 0)),
                (d.left, SIMD3(-half, 0, 0), SIMD3(0, 1, 0)),
                (d.right, SIMD3(half, 0, 0), SIMD3(0, -1, 0)),
            ]
            leafM.isDoubleSided = true
            for (angle, hinge, axis) in leaves {
                let isVertical = abs(axis.y) > 0.5
                // Leaf starts pointing straight forward from its hinge, then opens outwards.
                let leaf = isVertical ? SCNPlane(width: 0.16, height: 0.24) : SCNPlane(width: 0.24, height: 0.16)
                leaf.materials = [leafM]
                let n = SCNNode(geometry: leaf)
                let pivot = SCNNode()
                pivot.simdPosition = hinge + SIMD3(0, 0, -0.02)
                n.simdPosition = SIMD3(0, 0, -0.08)
                n.simdEulerAngles = isVertical ? SIMD3(0, Float.pi / 2, 0) : SIMD3(Float.pi / 2, 0, 0)
                pivot.addChildNode(n)
                pivot.simdOrientation = simd_quatf(angle: Float(min(angle, 90) * .pi / 180), axis: axis)
                node.addChildNode(pivot)
            }
        }
        return node
    }

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

    /// Faint volume showing where the beam goes: a cone, or a four-sided frustum cut by barn doors.
    static func beamVolume(pm: ResolvedPhotometrics, doors: BarnDoors, color: UIColor, length: Double) -> SCNNode? {
        guard pm.distribution == .beam || pm.distribution == .lambertian else { return nil }
        let half = min(pm.distribution == .beam ? pm.beamAngle * 0.68 : 60, 75)
        func t(_ limit: Double) -> Float { Float(tan(min(half, pm.barnDoorsAvailable ? limit : 90) * .pi / 180) * length) }
        let l = t(doors.left), r = t(doors.right), u = t(doors.top), d = t(doors.bottom)
        let z = Float(-length)
        let far: [SIMD3<Float>] = [SIMD3(-l, -d, z), SIMD3(r, -d, z), SIMD3(r, u, z), SIMD3(-l, u, z)]
        var vertices: [SCNVector3] = [SCNVector3(0, 0, 0)]
        vertices += far.map { SCNVector3($0.x, $0.y, $0.z) }
        let indices: [Int32] = [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1]
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = material(color.withAlphaComponent(0.07), constant: true)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .add
        g.materials = [m]
        let node = SCNNode(geometry: g)
        node.castsShadow = false
        return node
    }

    /// Brightness for the viewport only: compresses the estimated flux so a practical and an HMI
    /// can share a scene. Never used for lux.
    static func viewportIntensity(flux: Double) -> CGFloat {
        CGFloat(250 + 900 * log10(1 + max(flux, 0) / 500))
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

/// Dollhouse view: walls between the orbit camera and the room fade so you can see in.
/// Runs on SceneKit's render thread; only touches the wall nodes it was given.
final class WallFader {
    private let lock = NSLock()
    private var walls: [SCNNode] = []
    private weak var world: SCNNode?
    private var centre = SIMD3<Float>(0, 0, 0)
    /// Each wall's centre in the world node's space.
    private var mids: [SIMD3<Float>] = []
    private var base: CGFloat = 1
    private var faded: [Bool] = []
    static let fadedOpacity: CGFloat = 0.12

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
        faded = Array(repeating: false, count: walls.count)
    }

    /// The user's wall opacity; faded walls never go above it.
    func setBase(_ opacity: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        base = opacity
        faded = Array(repeating: false, count: walls.count)
    }

    /// Back to the user's opacity everywhere (for views from inside the room).
    func restore() {
        lock.lock(); defer { lock.unlock() }
        for (i, wall) in walls.enumerated() where faded[i] {
            wall.opacity = base
            faded[i] = false
        }
    }

    func update(camera: SIMD3<Float>) {
        lock.lock(); defer { lock.unlock() }
        guard let world, !walls.isEmpty else { return }
        let c = world.presentation.simdConvertPosition(centre, to: nil)
        for (i, wall) in walls.enumerated() {
            guard i < mids.count else { break }
            let mid = world.presentation.simdConvertPosition(mids[i], to: nil)
            let outward = SIMD2(mid.x - c.x, mid.z - c.z)
            let toCamera = SIMD2(camera.x - mid.x, camera.z - mid.z)
            // In front of the wall's outside face, and outside the room.
            let near = simd_dot(outward, toCamera) > 0 && simd_length(SIMD2(camera.x - c.x, camera.z - c.z)) > simd_length(outward)
            if near != faded[i] {
                faded[i] = near
                wall.opacity = near ? min(base, Self.fadedOpacity) : base
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
    private var alignment = ScanAlignment.identity
    private weak var orbitView: SCNView?
    let wallFader = WallFader()

    init() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.03
        cameraNode.camera?.zFar = 500
        cameraNode.camera?.projectionDirection = .horizontal
        tiltNode.addChildNode(cameraNode)
        panNode.addChildNode(tiltNode)

        orbitCameraNode.camera = SCNCamera()
        orbitCameraNode.camera?.zNear = 0.05
        orbitCameraNode.camera?.zFar = 500
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
        for n in [scanHolder, markers, lightRig, people, meterNodes, panNode, selectionRing] { world.addChildNode(n) }
        let ring = SCNTorus(ringRadius: 0.4, pipeRadius: 0.012)
        ring.firstMaterial = SceneKitBuilder.material(.white, constant: true)
        selectionRing.geometry = ring
        selectionRing.isHidden = true
        selectionRing.castsShadow = false
        scene.background.contents = UIColor(white: 0.05, alpha: 1)
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
                self.geometry = geometry
                var items: [(node: SCNNode, category: String, id: UUID?)] = []
                let node = SceneKitBuilder.node(for: geometry) { n, info in
                    items.append((n, info["category"]?.lowercased() ?? "", info["id"].flatMap(UUID.init(uuidString:))))
                }
                scanItems = items
                wallFader.configure(walls: items.filter { group(for: $0.category) == .walls }.map(\.node), world: world,
                                    centre: SIMD3(roomCentreLocal(node).x, Float(floorY) + 1, roomCentreLocal(node).z))
                scanHolder.addChildNode(node)
                let (lo, hi) = node.boundingBox
                roomCentre = SIMD3(Float(lo.x + hi.x) / 2, Float(floorY) + 1, Float(lo.z + hi.z) / 2)
                roomSpan = max(Float(hi.x - lo.x), Float(hi.z - lo.z), 3)
                applyAlignment(alignment)
                resetView()
                loaded = true
            } catch {
                self.error = error.localizedDescription
            }
        }
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
        for item in scanItems {
            let g = group(for: item.category)
            var hidden = g.map { d.isHidden(group: $0) } ?? false
            if g == .furniture {
                hidden = hidden || d.isHidden(category: item.category) || (item.id.map { d.isHidden(item: SceneItemKey.object($0)) } ?? false)
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
                wallFader.setBase(CGFloat(d.wallOpacityValue))
                item.node.geometry?.firstMaterial?.writesToDepthBuffer = d.wallOpacityValue > 0.95
            default:
                break
            }
        }
        markers.isHidden = d.isHidden(group: .cameras)
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
        let c = worldPoint(roomCentre)
        moveOrbit(to: c + SIMD3(0, roomSpan * 1.0, roomSpan * 0.85), target: c)
    }

    /// Straight down, like the plan.
    func topView() {
        let c = worldPoint(roomCentre)
        moveOrbit(to: c + SIMD3(0, roomSpan * 1.6, 0.01), target: c)
    }

    /// Frames a point (plan x/z, height above floor) from the current viewing direction.
    func focus(on p: PlanPoint, height: Double, distance: Float = 3) {
        let target = worldPoint(SIMD3(Float(p.x), Float(floorY + height), Float(p.z)))
        var dir = orbitCameraNode.simdWorldPosition - target
        if simd_length(dir) < 0.01 { dir = SIMD3(0, 1, 1) }
        dir = simd_normalize(dir)
        if dir.y < 0.25 { dir = simd_normalize(SIMD3(dir.x, 0.35, dir.z)) }
        moveOrbit(to: target + dir * distance, target: target)
    }

    private func worldPoint(_ local: SIMD3<Float>) -> SIMD3<Float> { world.simdConvertPosition(local, to: nil) }

    private func moveOrbit(to position: SIMD3<Float>, target: SIMD3<Float>) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.45
        orbitCameraNode.simdPosition = position
        orbitCameraNode.simdLook(at: target)
        SCNTransaction.commit()
        orbitView?.defaultCameraController.target = SCNVector3(target.x, target.y, target.z)
        wallFader.update(camera: position)
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
        markers.childNodes.forEach { $0.removeFromParentNode() }
        for vp in viewpoints {
            if !(hideSelected && vp.id == selected) {
                let color = vp.kind == .shot ? UIColor(red: 0.56, green: 0.65, blue: 0.74, alpha: 1) : UIColor.white
                let reach = vp.subject.map { max(1.5, vp.rig.position.distance(to: $0)) } ?? 2.5
                let m = SceneKitBuilder.cameraModel(rig: vp.rig, color: color, label: showLabels ? "\(vp.label) · \(Optics.formatFocal(vp.rig.focalLength))" : nil,
                                                    reach: reach, selected: vp.id == selected)
                m.name = "sel:\(vp.kind == .shot ? "shot" : "camera"):\(vp.id.uuidString)"
                m.simdPosition.y = Float(floorY)
                markers.addChildNode(m)
            }
            if let s = vp.subject, !hiddenSubjects {
                let mark = SCNCylinder(radius: 0.18, height: 0.01)
                mark.firstMaterial = SceneKitBuilder.material(UIColor(red: 0.86, green: 0.4, blue: 0.37, alpha: 0.8), constant: true)
                let node = SCNNode(geometry: mark)
                node.simdPosition = SIMD3(Float(s.x), Float(floorY) + 0.006, Float(s.z))
                node.castsShadow = false
                markers.addChildNode(node)
            }
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

    /// Lighting units: a head shaped by type and modifier, a SceneKit light set from the unit's
    /// colour and (compressed) output, barn doors as leaves and a projected mask, and a faint beam.
    /// Viewport brightness is a visual guide only; lux comes from `LightingCalculator`.
    func setLights(_ lights: [LightFixture], selected: UUID?, showLabels: Bool = false, showBeams: Bool = true, hideGrip: Bool = false) {
        lightRig.childNodes.forEach { $0.removeFromParentNode() }
        var anyOn = false
        var shadowCount = 0
        for l in lights {
            if hideGrip && !l.kind.emits { continue }
            let pan = SCNNode()
            pan.name = "sel:light:\(l.id.uuidString)"
            pan.simdPosition = SIMD3(Float(l.position.x), Float(floorY + l.height), Float(l.position.z))
            pan.simdEulerAngles = SIMD3(0, Float(-l.pan * .pi / 180), 0)
            let tilt = SCNNode()
            tilt.simdEulerAngles = SIMD3(Float(l.tilt * .pi / 180), 0, 0)
            pan.addChildNode(tilt)

            if l.kind.emits {
                let pm = l.photometrics
                let color = SceneKitBuilder.uiColor(pm.color)
                tilt.addChildNode(SceneKitBuilder.lightHead(l, pm: pm, color: color, selected: l.id == selected))
                if l.isOn && pm.flux > 0 {
                    anyOn = true
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
                    light.intensity = SceneKitBuilder.viewportIntensity(flux: pm.flux)
                    light.attenuationStartDistance = 0.3
                    light.attenuationEndDistance = 14
                    light.attenuationFalloffExponent = 2
                    if light.type == .spot {
                        if pm.barnDoorsAvailable && !l.barnDoorSettings.isOpen {
                            light.gobo?.contents = SceneKitBuilder.barnDoorGobo(l.barnDoorSettings, outerAngle: Double(light.spotOuterAngle))
                        }
                        // Shadows only for the first few units; they are the expensive part.
                        if shadowCount < 4 {
                            light.castsShadow = true
                            light.shadowMode = .deferred
                            light.shadowColor = UIColor.black.withAlphaComponent(0.55)
                            shadowCount += 1
                        }
                    }
                    let lightNode = SCNNode()
                    lightNode.light = light
                    // Just in front of the head so the unit doesn't shadow itself.
                    lightNode.simdPosition = SIMD3(0, 0, -0.14)
                    tilt.addChildNode(lightNode)
                    if showBeams, let beam = SceneKitBuilder.beamVolume(pm: pm, doors: l.barnDoorSettings, color: color,
                                                                        length: min(6, max(1.2, (pm.distance(forLux: 50) ?? 3)))) {
                        beam.simdPosition = SIMD3(0, 0, -0.1)
                        tilt.addChildNode(beam)
                    }
                }
            } else {
                let h = l.boardHeight ?? (l.kind == .flag ? min(l.width, 0.9) : l.width)
                let board = SCNPlane(width: CGFloat(l.width), height: CGFloat(h))
                let m = SCNMaterial()
                switch l.kind {
                case .bounce: m.diffuse.contents = UIColor.white
                case .negative: m.diffuse.contents = UIColor(white: 0.04, alpha: 1)
                case .diffusion: m.diffuse.contents = UIColor(white: 1, alpha: 0.55)
                default: m.diffuse.contents = UIColor(white: 0.25, alpha: 1)
                }
                m.isDoubleSided = true
                if l.id == selected { m.emission.contents = UIColor.white.withAlphaComponent(0.35) }
                board.materials = [m]
                tilt.addChildNode(SCNNode(geometry: board))
                // Stand to the floor.
                let stand = SCNCylinder(radius: 0.01, height: CGFloat(max(l.height - h / 2, 0.05)))
                stand.firstMaterial = SceneKitBuilder.material(UIColor(white: 0.3, alpha: 1))
                let s = SCNNode(geometry: stand)
                s.simdPosition = SIMD3(0, -Float(h / 2) - Float(max(l.height - h / 2, 0.05)) / 2, 0)
                pan.addChildNode(s)
            }
            if showLabels {
                let text = l.kind.emits ? "\(l.name) · \(l.isOn ? "\(Int((l.dimmer * 100).rounded())) %" : "off")" : l.name
                let label = SceneKitBuilder.label(text, color: UIColor(white: 0.95, alpha: 1), size: 0.08)
                label.simdPosition = SIMD3(0, 0.3, 0)
                pan.addChildNode(label)
            }
            lightRig.addChildNode(pan)
        }
        ambientNode.light?.intensity = anyOn ? 160 : 450
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
                if let item = scanItems.first(where: { $0.node === node }), group(for: item.category) == .furniture, let id = item.id {
                    return .object(id)
                }
                n = node.parent
            }
        }
        return nil
    }
}

/// SceneKit view. In orbit mode: drag to orbit, two fingers to pan, pinch to zoom; tap selects,
/// press-and-hold then drag moves the item, two-finger twist turns it.
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
        view.allowsCameraControl = orbit
        if orbit {
            view.defaultCameraController.interactionMode = .orbitTurntable
            view.defaultCameraController.inertiaEnabled = true
            view.defaultCameraController.maximumVerticalAngle = 89
            model.attach(view)
        }
        let c = context.coordinator
        c.view = view
        c.fader = model.wallFader
        c.fades = orbit
        view.delegate = c
        if !orbit { model.wallFader.restore() }
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
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
        if !context.coordinator.dragging { view.allowsCameraControl = orbit }
        // Re-claim the shared orbit camera after another view (e.g. the alignment sheet) used it.
        if orbit { model.attach(view) }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, SCNSceneRendererDelegate {
        var fader: WallFader?
        var fades = false
        var parent: SceneKitContainer?
        weak var view: SCNView?
        var dragging = false
        private var dragItem: PlanSelection?
        private var rotateItem: PlanSelection?
        private var lastRotation: CGFloat = 0

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

        @MainActor @objc func press(_ g: UILongPressGestureRecognizer) {
            guard let parent, let view, parent.onMove != nil else { return }
            switch g.state {
            case .began:
                guard let item = parent.model.hit(at: g.location(in: view), in: view), item.isMovable else { return }
                dragItem = item
                dragging = true
                view.allowsCameraControl = false
                parent.onSelect?(item)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .changed:
                guard let item = dragItem else { return }
                let h = parent.dragHeight?(item) ?? 0
                if let p = parent.model.planPoint(at: g.location(in: view), in: view, height: h) { parent.onMove?(item, p) }
            default:
                dragItem = nil
                dragging = false
                view.allowsCameraControl = parent.orbit
            }
        }

        @MainActor @objc func rotate(_ g: UIRotationGestureRecognizer) {
            guard let parent, let view, parent.onRotate != nil else { return }
            switch g.state {
            case .began:
                rotateItem = parent.model.hit(at: g.location(in: view), in: view)
                lastRotation = 0
                if rotateItem != nil { view.allowsCameraControl = false }
            case .changed:
                guard let item = rotateItem else { return }
                let delta = g.rotation - lastRotation
                lastRotation = g.rotation
                parent.onRotate?(item, Double(delta) * 180 / .pi)
            default:
                rotateItem = nil
                view.allowsCameraControl = parent.orbit
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard fades, let pov = renderer.pointOfView else { return }
            fader?.update(camera: pov.presentation.simdWorldPosition)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // The twist runs alongside the camera's own pinch; press-and-hold doesn't.
            g is UIRotationGestureRecognizer
        }
    }
}
