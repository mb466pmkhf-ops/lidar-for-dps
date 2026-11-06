import SceneKit
import UIKit

/// Film-set equipment for the 3D view: light heads by type, yokes, stands (C-stand, combo, turtle
/// base, MegaBoom…), and a cinema camera on its support. Built from SceneKit primitives at real
/// sizes, so a 2 m C-stand reads as one next to a person. Looks only; nothing here changes the maths.
enum RigModels {
    // MARK: Materials (shared; SceneKit copies nothing, so these are cheap to reuse)

    static let steel = metal(white: 0.62, roughness: 0.32)
    static let blackMetal = metal(white: 0.09, roughness: 0.45)
    static let darkMetal = metal(white: 0.2, roughness: 0.4)
    static let rubber = matte(white: 0.05)
    static let sandbag = matte(UIColor(red: 0.42, green: 0.36, blue: 0.24, alpha: 1))
    static let silk = matte(white: 0.92)
    static let wood = matte(UIColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 1))
    static let glass = { () -> SCNMaterial in
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.0
        m.roughness.contents = 0.08
        return m
    }()

    static func metal(white: CGFloat, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(white: white, alpha: 1)
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.85
        m.roughness.contents = roughness
        return m
    }

    static func matte(white: CGFloat) -> SCNMaterial { matte(UIColor(white: white, alpha: 1)) }

    static func matte(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.85
        return m
    }

    /// Glowing face of a light: the beam colour when on, grey when off.
    static func emitter(_ color: UIColor, on: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = on ? color : UIColor(white: 0.32, alpha: 1)
        if on { m.emission.contents = color }
        return m
    }

    // MARK: Primitives

    @discardableResult
    static func add(_ g: SCNGeometry, _ m: SCNMaterial, to parent: SCNNode, at p: SIMD3<Float> = .zero, euler: SIMD3<Float> = .zero) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        n.simdEulerAngles = euler
        parent.addChildNode(n)
        return n
    }

    /// A round bar between two points.
    @discardableResult
    static func bar(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: Float, _ m: SCNMaterial, to parent: SCNNode, segments: Int = 12) -> SCNNode {
        let d = b - a
        let len = simd_length(d)
        let g = SCNCylinder(radius: CGFloat(radius), height: CGFloat(max(len, 0.001)))
        g.radialSegmentCount = segments
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = orientation(along: d)
        parent.addChildNode(n)
        return n
    }

    /// A flat bar (rectangular section) between two points, e.g. a C-stand leg.
    @discardableResult
    static func strap(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width: Float, thickness: Float, _ m: SCNMaterial, to parent: SCNNode) -> SCNNode {
        let d = b - a
        let len = simd_length(d)
        let g = SCNBox(width: CGFloat(width), height: CGFloat(max(len, 0.001)), length: CGFloat(thickness), chamferRadius: CGFloat(thickness / 3))
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = orientation(along: d)
        parent.addChildNode(n)
        return n
    }

    /// Rotation taking +Y onto `d` (safe for straight down).
    static func orientation(along d: SIMD3<Float>) -> simd_quatf {
        let len = simd_length(d)
        guard len > 1e-5 else { return simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) }
        let dir = d / len
        if simd_dot(dir, SIMD3(0, 1, 0)) < -0.9999 { return simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)) }
        return simd_quatf(from: SIMD3(0, 1, 0), to: dir)
    }

    // MARK: Light heads

    /// Size of a head for its yoke: half-width across, and the distance from the tilt axis to its bottom.
    struct HeadSize { var halfWidth: Float; var below: Float }

    static func headSize(_ l: LightFixture, pm: ResolvedPhotometrics) -> HeadSize {
        switch pm.profile.category {
        case .cob: return HeadSize(halfWidth: 0.12, below: 0.13)
        case .fresnel, .tungsten: return HeadSize(halfWidth: 0.16, below: 0.16)
        case .hmi: return HeadSize(halfWidth: 0.19, below: 0.19)
        case .panel, .soft: return HeadSize(halfWidth: Float(pm.profile.emitterWidth / 2 + 0.03), below: Float(pm.profile.emitterHeight / 2 + 0.03))
        case .tube: return HeadSize(halfWidth: 0.05, below: 0.04)
        case .spaceLight: return HeadSize(halfWidth: 0.35, below: 0.3)
        case .practical: return HeadSize(halfWidth: 0.1, below: 0.1)
        }
    }

    /// The unit itself, facing −Z, pivoting about its tilt axis at the origin.
    static func lightHead(_ l: LightFixture, pm: ResolvedPhotometrics, color: UIColor, selected: Bool) -> SCNNode {
        let node = SCNNode()
        let glow = emitter(color, on: l.isOn)
        let housing = selected ? metal(white: 0.32, roughness: 0.4) : blackMetal
        if selected { housing.emission.contents = UIColor(white: 0.12, alpha: 1) }

        switch pm.profile.category {
        case .cob:
            // Body with fan grille, handle on top, Bowens mount at the front.
            add(SCNBox(width: 0.2, height: 0.22, length: 0.26, chamferRadius: 0.02), housing, to: node, at: SIMD3(0, 0, 0.1))
            add(SCNBox(width: 0.16, height: 0.16, length: 0.005, chamferRadius: 0.01), darkMetal, to: node, at: SIMD3(0, 0, 0.233))
            bar(SIMD3(0, 0.11, 0.0), SIMD3(0, 0.15, 0.04), radius: 0.008, darkMetal, to: node)
            bar(SIMD3(0, 0.11, 0.2), SIMD3(0, 0.15, 0.16), radius: 0.008, darkMetal, to: node)
            bar(SIMD3(0, 0.15, 0.04), SIMD3(0, 0.15, 0.16), radius: 0.01, rubber, to: node)
            add(SCNTube(innerRadius: 0.05, outerRadius: 0.075, height: 0.04), darkMetal, to: node, at: SIMD3(0, 0, -0.04), euler: SIMD3(.pi / 2, 0, 0))
            cobModifier(l, pm: pm, glow: glow, housing: housing, to: node)
        case .fresnel, .tungsten:
            // Round can with cooling rings, a fresnel lens behind a bezel, and a focus knob.
            let can = SCNCylinder(radius: 0.13, height: 0.3)
            can.radialSegmentCount = 28
            add(can, housing, to: node, at: SIMD3(0, 0, 0.1), euler: SIMD3(.pi / 2, 0, 0))
            for z: Float in [0.04, 0.1, 0.16] {
                add(SCNTorus(ringRadius: 0.133, pipeRadius: 0.006), darkMetal, to: node, at: SIMD3(0, 0, z), euler: SIMD3(.pi / 2, 0, 0))
            }
            add(SCNTube(innerRadius: 0.1, outerRadius: 0.14, height: 0.03), darkMetal, to: node, at: SIMD3(0, 0, -0.06), euler: SIMD3(.pi / 2, 0, 0))
            add(SCNCylinder(radius: 0.1, height: 0.01), glow, to: node, at: SIMD3(0, 0, -0.055), euler: SIMD3(.pi / 2, 0, 0))
            add(SCNCylinder(radius: 0.02, height: 0.04), rubber, to: node, at: SIMD3(0, -0.14, 0.2))
            barnDoors(l, pm: pm, half: 0.14, front: -0.075, to: node)
        case .hmi:
            // PAR: deep can, wide lens, lens retaining ring, rear igniter box.
            let can = SCNCylinder(radius: 0.17, height: 0.36)
            can.radialSegmentCount = 32
            add(can, housing, to: node, at: SIMD3(0, 0, 0.12), euler: SIMD3(.pi / 2, 0, 0))
            add(SCNBox(width: 0.18, height: 0.14, length: 0.12, chamferRadius: 0.01), darkMetal, to: node, at: SIMD3(0, 0, 0.35))
            add(SCNTube(innerRadius: 0.14, outerRadius: 0.185, height: 0.04), darkMetal, to: node, at: SIMD3(0, 0, -0.07), euler: SIMD3(.pi / 2, 0, 0))
            add(SCNCylinder(radius: 0.14, height: 0.01), glow, to: node, at: SIMD3(0, 0, -0.065), euler: SIMD3(.pi / 2, 0, 0))
            cobModifier(l, pm: pm, glow: glow, housing: housing, to: node, mountZ: -0.09)
            barnDoors(l, pm: pm, half: 0.18, front: -0.09, to: node)
        case .panel:
            let w = CGFloat(pm.profile.emitterWidth), h = CGFloat(pm.profile.emitterHeight)
            add(SCNBox(width: w + 0.04, height: h + 0.04, length: 0.05, chamferRadius: 0.008), housing, to: node, at: SIMD3(0, 0, 0.02))
            add(SCNPlane(width: w, height: h), glow, to: node, at: SIMD3(0, 0, -0.006), euler: SIMD3(0, .pi, 0))
            add(SCNBox(width: 0.12, height: 0.08, length: 0.04, chamferRadius: 0.005), darkMetal, to: node, at: SIMD3(0, 0, 0.065))
            if l.modifierItem?.id == "panel-softbox" {
                softbox(width: Float(w) + 0.1, height: Float(h) + 0.1, depth: 0.25, glow: glow, to: node, back: -0.005)
            } else if pm.barnDoorsAvailable {
                barnDoors(l, pm: pm, half: Float(max(w, h) / 2), front: -0.01, to: node)
            }
        case .soft:
            // Flexible mat in its frame: a thin aluminium frame with a diffusion face.
            let w = CGFloat(pm.profile.emitterWidth), h = CGFloat(pm.profile.emitterHeight)
            add(SCNBox(width: w, height: h, length: 0.02, chamferRadius: 0), silk, to: node, at: SIMD3(0, 0, 0.01))
            add(SCNPlane(width: w * 0.97, height: h * 0.97), glow, to: node, at: SIMD3(0, 0, -0.002), euler: SIMD3(0, .pi, 0))
            let hw = Float(w / 2), hh = Float(h / 2)
            let corners: [SIMD3<Float>] = [SIMD3(-hw, -hh, 0), SIMD3(hw, -hh, 0), SIMD3(hw, hh, 0), SIMD3(-hw, hh, 0)]
            for i in 0..<4 { bar(corners[i], corners[(i + 1) % 4], radius: 0.012, steel, to: node, segments: 8) }
            // Diffusion skirt for a soft, wrapped look.
            softbox(width: Float(w), height: Float(h), depth: 0.18, glow: glow, to: node, back: 0, skirtOnly: true)
        case .tube:
            let len = CGFloat(pm.profile.emitterWidth)
            let tube = SCNCylinder(radius: 0.022, height: len)
            tube.radialSegmentCount = 16
            add(tube, glow, to: node, euler: SIMD3(0, 0, .pi / 2))
            for s: Float in [-1, 1] {
                add(SCNCylinder(radius: 0.026, height: 0.05), housing, to: node, at: SIMD3(s * Float(len / 2), 0, 0), euler: SIMD3(0, 0, .pi / 2))
            }
            add(SCNBox(width: 0.06, height: 0.05, length: 0.05, chamferRadius: 0.005), darkMetal, to: node, at: SIMD3(0, -0.035, 0))
        case .spaceLight:
            // Silk skirt around a downward-facing ring of LEDs.
            let skirt = SCNCylinder(radius: 0.32, height: 0.55)
            skirt.radialSegmentCount = 32
            add(skirt, glow, to: node)
            add(SCNCylinder(radius: 0.18, height: 0.08), housing, to: node, at: SIMD3(0, 0.31, 0))
        case .practical:
            // Bulb under a fabric shade.
            add(SCNSphere(radius: 0.04), glow, to: node)
            if l.modifierItem?.id == "shade" || l.modifierID == nil {
                let shade = SCNCone(topRadius: 0.11, bottomRadius: 0.17, height: 0.2)
                shade.radialSegmentCount = 28
                let m = emitter(color.withAlphaComponent(1), on: l.isOn)
                m.diffuse.contents = l.isOn ? color.withAlphaComponent(0.85) : UIColor(white: 0.75, alpha: 1)
                m.isDoubleSided = true
                m.emission.intensity = 0.55
                add(shade, m, to: node, at: SIMD3(0, 0.03, 0))
            }
        }
        return node
    }

    /// Reflector, softbox, lantern or projector on a Bowens mount at `mountZ`.
    private static func cobModifier(_ l: LightFixture, pm: ResolvedPhotometrics, glow: SCNMaterial, housing: SCNMaterial, to node: SCNNode, mountZ: Float = -0.06) {
        guard pm.profile.category == .cob || pm.profile.category == .hmi || pm.profile.category == .fresnel || pm.profile.category == .tungsten else { return }
        let id = l.modifierItem?.id ?? ""
        if id.hasPrefix("softbox") {
            let size = Float(pm.modifier?.size ?? 0.9)
            softbox(width: size, height: size, depth: size * 0.55, glow: glow, to: node, back: mountZ, octa: true)
        } else if id.hasPrefix("lantern") {
            let r = CGFloat((pm.modifier?.size ?? 0.65) / 2)
            let lantern = SCNSphere(radius: r)
            lantern.segmentCount = 24
            add(lantern, glow, to: node, at: SIMD3(0, 0, mountZ - Float(r)))
            add(SCNCylinder(radius: 0.08, height: 0.06), darkMetal, to: node, at: SIMD3(0, 0, mountZ - 0.02), euler: SIMD3(.pi / 2, 0, 0))
        } else if id == "projector" || id == "fresnel-attachment" {
            let lensLength: Float = id == "projector" ? 0.3 : 0.12
            let barrel = SCNCylinder(radius: id == "projector" ? 0.07 : 0.11, height: CGFloat(lensLength))
            barrel.radialSegmentCount = 24
            add(barrel, blackMetal, to: node, at: SIMD3(0, 0, mountZ - lensLength / 2), euler: SIMD3(.pi / 2, 0, 0))
            add(SCNCylinder(radius: id == "projector" ? 0.06 : 0.1, height: 0.01), glow, to: node, at: SIMD3(0, 0, mountZ - lensLength - 0.004), euler: SIMD3(.pi / 2, 0, 0))
        } else if pm.profile.category == .cob, id != "cob-bare" {
            // Open reflector dish; narrower ones are longer.
            let length: Float = id == "reflector-15" ? 0.3 : id == "reflector-30" ? 0.2 : 0.13
            let front: CGFloat = id == "reflector-15" ? 0.13 : 0.11
            let dish = SCNCone(topRadius: front, bottomRadius: 0.065, height: CGFloat(length))
            dish.radialSegmentCount = 32
            let m = metal(white: 0.75, roughness: 0.2)
            m.isDoubleSided = true
            add(dish, m, to: node, at: SIMD3(0, 0, mountZ - length / 2), euler: SIMD3(-.pi / 2, 0, 0))
            add(SCNCylinder(radius: 0.05, height: 0.01), glow, to: node, at: SIMD3(0, 0, mountZ - 0.01), euler: SIMD3(.pi / 2, 0, 0))
        } else {
            add(SCNCylinder(radius: 0.045, height: 0.01), glow, to: node, at: SIMD3(0, 0, mountZ - 0.005), euler: SIMD3(.pi / 2, 0, 0))
        }
    }

    /// Softbox: a frustum from the speed ring at `back` to a diffusion face in front. `octa` rounds it.
    private static func softbox(width: Float, height: Float, depth: Float, glow: SCNMaterial, to node: SCNNode, back: Float,
                                octa: Bool = false, skirtOnly: Bool = false) {
        let sides = octa ? 8 : 4
        let ring: Float = 0.08
        let frontZ = back - depth
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        func corner(_ i: Int, _ rx: Float, _ ry: Float, _ z: Float) -> SIMD3<Float> {
            let a = (Float(i) + (octa ? 0.5 : 0.5)) / Float(sides) * 2 * .pi
            let s = octa ? SIMD2(cos(a), sin(a)) : SIMD2(cos(a) >= 0 ? 1 : -1, sin(a) >= 0 ? 1 : -1)
            return SIMD3(s.x * rx, s.y * ry, z)
        }
        for i in 0..<sides {
            let b0 = corner(i, skirtOnly ? width / 2 : ring, skirtOnly ? height / 2 : ring, skirtOnly ? 0 : back)
            let b1 = corner(i + 1, skirtOnly ? width / 2 : ring, skirtOnly ? height / 2 : ring, skirtOnly ? 0 : back)
            let f0 = corner(i, width / 2, height / 2, skirtOnly ? -depth : frontZ)
            let f1 = corner(i + 1, width / 2, height / 2, skirtOnly ? -depth : frontZ)
            let n = simd_normalize(simd_cross(b1 - b0, f0 - b0))
            let base = Int32(vertices.count)
            for p in [b0, b1, f1, f0] {
                vertices.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(n.x, n.y, n.z))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let cloth = matte(white: skirtOnly ? 0.2 : 0.07)
        cloth.isDoubleSided = true
        g.materials = [cloth]
        node.addChildNode(SCNNode(geometry: g))
        guard !skirtOnly else { return }
        // Diffusion face.
        let face: SCNGeometry
        if octa {
            let c = SCNCylinder(radius: CGFloat(width / 2), height: 0.004)
            c.radialSegmentCount = 8
            face = c
            add(face, glow, to: node, at: SIMD3(0, 0, frontZ), euler: SIMD3(.pi / 2, .pi / 8, 0))
        } else {
            face = SCNPlane(width: CGFloat(width), height: CGFloat(height))
            add(face, glow, to: node, at: SIMD3(0, 0, frontZ), euler: SIMD3(0, .pi, 0))
        }
    }

    /// Four leaves hinged at the front, opened to their cut.
    private static func barnDoors(_ l: LightFixture, pm: ResolvedPhotometrics, half: Float, front: Float, to node: SCNNode) {
        guard pm.barnDoorsAvailable, l.barnDoors != nil else { return }
        let d = l.barnDoorSettings
        let leafM = blackMetal.copy() as! SCNMaterial
        leafM.isDoubleSided = true
        let leafLength = half * 1.1
        let leaves: [(Double, SIMD3<Float>, SIMD3<Float>)] = [
            (d.top, SIMD3(0, half, 0), SIMD3(1, 0, 0)),
            (d.bottom, SIMD3(0, -half, 0), SIMD3(-1, 0, 0)),
            (d.left, SIMD3(-half, 0, 0), SIMD3(0, 1, 0)),
            (d.right, SIMD3(half, 0, 0), SIMD3(0, -1, 0)),
        ]
        // Frame ring the leaves hang from.
        add(SCNTube(innerRadius: CGFloat(half * 0.9), outerRadius: CGFloat(half * 1.02), height: 0.015), darkMetal, to: node,
            at: SIMD3(0, 0, front), euler: SIMD3(.pi / 2, 0, 0))
        for (angle, hinge, axis) in leaves {
            let vertical = abs(axis.y) > 0.5
            let leaf = vertical ? SCNPlane(width: CGFloat(leafLength), height: CGFloat(half * 2)) : SCNPlane(width: CGFloat(half * 2), height: CGFloat(leafLength))
            leaf.materials = [leafM]
            let n = SCNNode(geometry: leaf)
            let pivot = SCNNode()
            pivot.simdPosition = hinge + SIMD3(0, 0, front)
            n.simdPosition = SIMD3(0, 0, -leafLength / 2)
            n.simdEulerAngles = vertical ? SIMD3(0, .pi / 2, 0) : SIMD3(.pi / 2, 0, 0)
            pivot.addChildNode(n)
            pivot.simdOrientation = simd_quatf(angle: Float(min(angle, 90) * .pi / 180), axis: axis)
            node.addChildNode(pivot)
        }
    }

    // MARK: Yoke and stands

    /// U-shaped yoke around the head (turns with pan, not tilt). `hanging` puts the stud on top.
    static func yoke(_ size: HeadSize, hanging: Bool, to node: SCNNode) -> Float {
        let x = size.halfWidth + 0.025
        let y = (size.below + 0.03) * (hanging ? 1 : -1)
        for s: Float in [-1, 1] {
            strap(SIMD3(s * x, 0, 0), SIMD3(s * x, y, 0), width: 0.035, thickness: 0.01, blackMetal, to: node)
            add(SCNCylinder(radius: 0.022, height: 0.025), rubber, to: node, at: SIMD3(s * (x + 0.012), 0, 0), euler: SIMD3(0, 0, .pi / 2))
        }
        strap(SIMD3(-x, y, 0), SIMD3(x, y, 0), width: 0.035, thickness: 0.01, blackMetal, to: node)
        let stud = y + (hanging ? 0.07 : -0.07)
        bar(SIMD3(0, y, 0), SIMD3(0, stud, 0), radius: 0.008, steel, to: node, segments: 8)
        return stud
    }

    /// The stand under (or the rigging above) a unit whose yoke stud ends at `studY` relative to the
    /// head, `headHeight` above the floor. Lives in the unit's pan space: −Z is where it faces.
    static func stand(_ support: LightSupport, headHeight: Double, studY: Float, to node: SCNNode) {
        let floor = Float(-headHeight)
        let top = studY
        switch support {
        case .cStand:
            cStand(base: floor, top: top, at: .zero, to: node)
        case .comboStand:
            comboStand(base: floor, top: top, at: .zero, wheels: false, to: node)
        case .rollerStand:
            comboStand(base: floor, top: top, at: .zero, wheels: true, to: node)
        case .turtleBase:
            // Three low legs and a short riser.
            for i in 0..<3 {
                let a = Float(i) * 2 * .pi / 3 + .pi / 6
                let foot = SIMD3<Float>(sin(a) * 0.36, floor + 0.02, cos(a) * 0.36)
                strap(SIMD3(0, floor + 0.07, 0), foot, width: 0.03, thickness: 0.012, darkMetal, to: node)
                add(SCNCylinder(radius: 0.02, height: 0.015), rubber, to: node, at: foot - SIMD3(0, 0.012, 0))
            }
            bar(SIMD3(0, floor + 0.04, 0), SIMD3(0, top, 0), radius: 0.016, steel, to: node)
        case .megaBoom:
            // Combo base stood back behind the light, boom arm over the top, counterweight behind.
            let reach = Float(support.boomReach)
            let armY = top + 0.12
            comboStand(base: floor, top: armY - 0.06, at: SIMD3(0, 0, reach), wheels: true, to: node)
            bar(SIMD3(0, armY, -0.05), SIMD3(0, armY, reach + 0.9), radius: 0.02, steel, to: node)
            add(SCNBox(width: 0.14, height: 0.2, length: 0.16, chamferRadius: 0.01), darkMetal, to: node, at: SIMD3(0, armY - 0.06, reach + 0.95))
            add(SCNBox(width: 0.1, height: 0.1, length: 0.14, chamferRadius: 0.01), blackMetal, to: node, at: SIMD3(0, armY, reach))
            bar(SIMD3(0, armY, 0), SIMD3(0, top, 0), radius: 0.01, steel, to: node, segments: 8)
            // Steering line from the arm's tail.
            bar(SIMD3(0, armY, reach + 0.9), SIMD3(0.05, floor + 1.0, reach + 1.05), radius: 0.003, rubber, to: node, segments: 6)
        case .overhead:
            // Pipe clamp on a speed-rail or grid pipe above.
            let pipeY = top + 0.45
            bar(SIMD3(0, top, 0), SIMD3(0, pipeY, 0), radius: 0.01, steel, to: node, segments: 8)
            bar(SIMD3(-0.8, pipeY + 0.03, 0), SIMD3(0.8, pipeY + 0.03, 0), radius: 0.024, steel, to: node)
            add(SCNBox(width: 0.06, height: 0.07, length: 0.07, chamferRadius: 0.01), blackMetal, to: node, at: SIMD3(0, pipeY, 0))
        case .floor:
            // Floor plate.
            add(SCNBox(width: 0.3, height: 0.012, length: 0.24, chamferRadius: 0.004), darkMetal, to: node, at: SIMD3(0, floor + 0.006, 0))
            bar(SIMD3(0, floor + 0.01, 0), SIMD3(0, top, 0), radius: 0.01, steel, to: node, segments: 8)
        case .none:
            break
        }
    }

    /// Century stand: staggered turtle-base legs, three risers with knuckles, sandbag on the high leg.
    private static func cStand(base floor: Float, top: Float, at o: SIMD3<Float>, to node: SCNNode) {
        let collar = floor + 0.32
        let legHeights: [Float] = [0, 0.05, 0.1]
        for (i, dh) in legHeights.enumerated() {
            let a = Float(i) * 2 * .pi / 3 + .pi / 3
            let hub = o + SIMD3(0, collar - dh, 0)
            let foot = o + SIMD3(sin(a) * 0.42, floor + 0.015, cos(a) * 0.42)
            strap(hub, foot, width: 0.028, thickness: 0.012, steel, to: node)
            add(SCNBox(width: 0.035, height: 0.02, length: 0.035, chamferRadius: 0.005), rubber, to: node, at: foot - SIMD3(0, 0.005, 0))
            if i == 2 {
                // Sandbag over the highest leg.
                let bag = SCNCapsule(capRadius: 0.07, height: 0.42)
                add(bag, sandbag, to: node, at: (hub + foot) / 2 + SIMD3(0, 0.03, 0), euler: SIMD3(0, a, .pi / 2 - 0.55))
            }
        }
        add(SCNCylinder(radius: 0.026, height: 0.16), darkMetal, to: node, at: o + SIMD3(0, collar - 0.04, 0))
        risers(from: collar + 0.04, to: top, radii: [0.017, 0.014, 0.011], at: o, to: node)
    }

    /// Junior/combo: splayed legs on a collar, a heavy column, a junior receiver at the top.
    private static func comboStand(base floor: Float, top: Float, at o: SIMD3<Float>, wheels: Bool, to node: SCNNode) {
        let collar = floor + 0.55
        let spread: Float = wheels ? 0.6 : 0.55
        for i in 0..<3 {
            let a = Float(i) * 2 * .pi / 3
            let foot = o + SIMD3(sin(a) * spread, floor + (wheels ? 0.09 : 0.02), cos(a) * spread)
            bar(o + SIMD3(0, collar, 0), foot, radius: 0.016, steel, to: node, segments: 10)
            // Brace from the leg's middle back to the column.
            bar(o + SIMD3(0, collar - 0.32, 0), (o + SIMD3(0, collar, 0) + foot) / 2, radius: 0.009, steel, to: node, segments: 8)
            if wheels {
                let w = SCNCylinder(radius: 0.06, height: 0.035)
                w.radialSegmentCount = 18
                add(w, rubber, to: node, at: foot - SIMD3(0, 0.03, 0), euler: SIMD3(0, a, .pi / 2))
            } else {
                add(SCNCylinder(radius: 0.025, height: 0.02), rubber, to: node, at: foot - SIMD3(0, 0.01, 0))
            }
        }
        add(SCNCylinder(radius: 0.034, height: 0.14), darkMetal, to: node, at: o + SIMD3(0, collar, 0))
        risers(from: collar - 0.32, to: top, radii: [0.024, 0.02, 0.016], at: o, to: node)
        add(SCNCylinder(radius: 0.03, height: 0.07), darkMetal, to: node, at: o + SIMD3(0, top - 0.02, 0))
    }

    /// Telescoping risers between two heights, with a knuckle at each joint.
    private static func risers(from bottom: Float, to top: Float, radii: [Float], at o: SIMD3<Float>, to node: SCNNode) {
        guard top > bottom else { return }
        let n = radii.count
        let step = (top - bottom) / Float(n)
        for (i, r) in radii.enumerated() {
            let a = bottom + Float(i) * step
            let b = i == n - 1 ? top : a + step + 0.05
            bar(o + SIMD3(0, a, 0), o + SIMD3(0, b, 0), radius: r, i == 0 ? darkMetal : steel, to: node, segments: 14)
            if i > 0 {
                add(SCNCylinder(radius: CGFloat(radii[i - 1] + 0.008), height: 0.04), darkMetal, to: node, at: o + SIMD3(0, a, 0))
                add(SCNCylinder(radius: 0.008, height: 0.05), rubber, to: node, at: o + SIMD3(radii[i - 1] + 0.03, a, 0), euler: SIMD3(0, 0, .pi / 2))
            }
        }
    }

    // MARK: Camera

    /// Cinema camera facing −Z with the lens's entrance at the origin's −Z side; pivot at the head.
    /// Body length follows a typical cine camera; lens length follows the focal length.
    static func cameraBody(rig: CameraRig, accent: UIColor, selected: Bool) -> (node: SCNNode, lensFront: Float) {
        let node = SCNNode()
        let body = selected ? metal(white: 0.28, roughness: 0.45) : metal(white: 0.14, roughness: 0.5)
        if selected { body.emission.contents = accent.withAlphaComponent(0.25) }
        let accentM = SceneKitBuilder.material(accent, constant: true)
        // Body block, rear battery, top handle with posts, side viewfinder.
        add(SCNBox(width: 0.13, height: 0.14, length: 0.2, chamferRadius: 0.012), body, to: node, at: SIMD3(0, 0, 0.06))
        add(SCNBox(width: 0.11, height: 0.11, length: 0.06, chamferRadius: 0.01), blackMetal, to: node, at: SIMD3(0, -0.005, 0.19))
        bar(SIMD3(0, 0.07, -0.02), SIMD3(0, 0.11, -0.02), radius: 0.008, blackMetal, to: node)
        bar(SIMD3(0, 0.07, 0.13), SIMD3(0, 0.11, 0.13), radius: 0.008, blackMetal, to: node)
        add(SCNBox(width: 0.03, height: 0.025, length: 0.22, chamferRadius: 0.008), accentM, to: node, at: SIMD3(0, 0.115, 0.055))
        bar(SIMD3(-0.065, 0.05, 0.0), SIMD3(-0.11, 0.07, -0.02), radius: 0.006, blackMetal, to: node)
        let eye = SCNCylinder(radius: 0.02, height: 0.11)
        add(eye, blackMetal, to: node, at: SIMD3(-0.115, 0.075, 0.03), euler: SIMD3(.pi / 2, 0, 0))
        add(SCNBox(width: 0.06, height: 0.045, length: 0.012, chamferRadius: 0.003), glass, to: node, at: SIMD3(0.08, 0.04, 0.05), euler: SIMD3(0, .pi / 2.4, 0))
        // Baseplate and 15 mm rods under the lens.
        add(SCNBox(width: 0.12, height: 0.02, length: 0.24, chamferRadius: 0.004), blackMetal, to: node, at: SIMD3(0, -0.08, 0.06))
        let lensLength = Float(min(0.3, 0.07 + rig.focalLength / 520))
        for s: Float in [-1, 1] {
            bar(SIMD3(s * 0.03, -0.095, 0.14), SIMD3(s * 0.03, -0.095, -0.05 - lensLength), radius: 0.0075, steel, to: node, segments: 8)
        }
        // Lens: barrel with focus/iris gear rings and a front element.
        let lensZ: Float = -0.04
        let barrel = SCNCylinder(radius: 0.045, height: CGFloat(lensLength))
        barrel.radialSegmentCount = 24
        add(barrel, blackMetal, to: node, at: SIMD3(0, 0, lensZ - lensLength / 2), euler: SIMD3(.pi / 2, 0, 0))
        for f: Float in [0.3, 0.6] {
            add(SCNTorus(ringRadius: 0.047, pipeRadius: 0.006), darkMetal, to: node, at: SIMD3(0, 0, lensZ - lensLength * f), euler: SIMD3(.pi / 2, 0, 0))
        }
        add(SCNTorus(ringRadius: 0.046, pipeRadius: 0.004), accentM, to: node, at: SIMD3(0, 0, lensZ - lensLength), euler: SIMD3(.pi / 2, 0, 0))
        add(SCNCylinder(radius: 0.04, height: 0.004), glass, to: node, at: SIMD3(0, 0, lensZ - lensLength - 0.002), euler: SIMD3(.pi / 2, 0, 0))
        // Follow focus on the rods.
        add(SCNCylinder(radius: 0.022, height: 0.02), darkMetal, to: node, at: SIMD3(0.06, -0.06, lensZ - lensLength * 0.3), euler: SIMD3(0, 0, .pi / 2))
        // Matte box shaped to the frame, with top flag.
        let area = rig.imageArea
        let mbW = Float(0.17), mbH = Float(0.17 * area.height / area.width) + 0.02
        let mbZ = lensZ - lensLength - 0.07
        let mb = SCNNode()
        mb.simdPosition = SIMD3(0, 0, mbZ)
        let t: Float = 0.006
        add(SCNBox(width: CGFloat(mbW), height: CGFloat(t), length: 0.1, chamferRadius: 0), blackMetal, to: mb, at: SIMD3(0, mbH / 2, 0))
        add(SCNBox(width: CGFloat(mbW), height: CGFloat(t), length: 0.1, chamferRadius: 0), blackMetal, to: mb, at: SIMD3(0, -mbH / 2, 0))
        add(SCNBox(width: CGFloat(t), height: CGFloat(mbH), length: 0.1, chamferRadius: 0), blackMetal, to: mb, at: SIMD3(-mbW / 2, 0, 0))
        add(SCNBox(width: CGFloat(t), height: CGFloat(mbH), length: 0.1, chamferRadius: 0), blackMetal, to: mb, at: SIMD3(mbW / 2, 0, 0))
        add(SCNBox(width: CGFloat(mbW), height: CGFloat(t), length: 0.12, chamferRadius: 0), blackMetal, to: mb, at: SIMD3(0, mbH / 2 + 0.01, -0.09), euler: SIMD3(-0.15, 0, 0))
        add(SCNBox(width: 0.05, height: CGFloat(mbH * 0.6), length: 0.05, chamferRadius: 0.004), darkMetal, to: mb, at: SIMD3(0, 0, 0.07))
        node.addChildNode(mb)
        return (node, lensZ - lensLength)
    }

    /// The camera's support below the head, in pan space (the head's pan, not its tilt). The head
    /// itself (O'Connor-style fluid head with pan bar) is included for tripods, baby legs, high hats
    /// and dollies.
    static func cameraSupport(_ support: CameraSupport, height: Double, to node: SCNNode) {
        let floor = Float(-height)
        let headBottom: Float = -0.12
        func fluidHead() {
            add(SCNBox(width: 0.15, height: 0.1, length: 0.16, chamferRadius: 0.015), darkMetal, to: node, at: SIMD3(0, -0.14, 0.02))
            add(SCNCylinder(radius: 0.075, height: 0.04), blackMetal, to: node, at: SIMD3(0, -0.2, 0.02))
            // Pan bar back and to the right, with a rubber grip.
            bar(SIMD3(0.06, -0.12, 0.08), SIMD3(0.2, -0.22, 0.48), radius: 0.011, steel, to: node, segments: 10)
            bar(SIMD3(0.17, -0.2, 0.4), SIMD3(0.205, -0.225, 0.5), radius: 0.016, rubber, to: node, segments: 10)
            // Bowl / mitchell base.
            add(SCNCylinder(radius: 0.085, height: 0.03), darkMetal, to: node, at: SIMD3(0, -0.235, 0.02))
        }
        switch support {
        case .tripod, .babyLegs:
            fluidHead()
            let crown: Float = -0.25
            let spreaderY = floor + 0.05
            for i in 0..<3 {
                let a = Float(i) * 2 * .pi / 3 + .pi
                let foot = SIMD3<Float>(sin(a) * 0.5 * min(1, Float(height) / 1.4 + 0.2), floor, cos(a) * 0.5 * min(1, Float(height) / 1.4 + 0.2))
                let hub = SIMD3<Float>(sin(a) * 0.07, crown, cos(a) * 0.07)
                // Twin-tube legs.
                let side = simd_normalize(SIMD3(cos(a), 0, -sin(a))) * 0.016
                bar(hub + side, foot + side * 0.5, radius: 0.009, wood, to: node, segments: 8)
                bar(hub - side, foot - side * 0.5, radius: 0.009, wood, to: node, segments: 8)
                add(SCNBox(width: 0.04, height: 0.03, length: 0.04, chamferRadius: 0.005), blackMetal, to: node, at: foot + SIMD3(0, 0.015, 0))
                // Ground spreader arm.
                bar(SIMD3(0, spreaderY, 0), SIMD3(foot.x, spreaderY, foot.z) * 0.95, radius: 0.007, blackMetal, to: node, segments: 6)
            }
            add(SCNCylinder(radius: 0.1, height: 0.04), blackMetal, to: node, at: SIMD3(0, crown, 0))
        case .highHat:
            fluidHead()
            let plate = SCNCylinder(radius: 0.16, height: 0.02)
            plate.radialSegmentCount = 3
            add(plate, wood, to: node, at: SIMD3(0, floor + 0.01, 0))
            bar(SIMD3(0, floor + 0.02, 0), SIMD3(0, -0.25, 0.02), radius: 0.04, darkMetal, to: node)
        case .dolly:
            fluidHead()
            add(SCNBox(width: 0.5, height: 0.16, length: 0.8, chamferRadius: 0.02), metal(white: 0.25, roughness: 0.5), to: node, at: SIMD3(0, floor + 0.17, 0.25))
            for x: Float in [-0.24, 0.24] {
                for z: Float in [-0.1, 0.6] {
                    let w = SCNCylinder(radius: 0.06, height: 0.05)
                    w.radialSegmentCount = 18
                    add(w, rubber, to: node, at: SIMD3(x, floor + 0.06, z), euler: SIMD3(0, 0, .pi / 2))
                }
            }
            bar(SIMD3(0, floor + 0.25, 0.0), SIMD3(0, -0.25, 0.02), radius: 0.045, steel, to: node)
            // Push bar at the back.
            bar(SIMD3(-0.2, floor + 0.8, 0.68), SIMD3(0.2, floor + 0.8, 0.68), radius: 0.014, steel, to: node)
            for x: Float in [-0.2, 0.2] { bar(SIMD3(x, floor + 0.25, 0.62), SIMD3(x, floor + 0.8, 0.68), radius: 0.012, steel, to: node) }
            // Track under it.
            for x: Float in [-0.31, 0.31] { bar(SIMD3(x, floor + 0.01, -1.2), SIMD3(x, floor + 0.01, 1.6), radius: 0.012, steel, to: node, segments: 8) }
        case .slider:
            add(SCNBox(width: 0.08, height: 0.05, length: 0.1, chamferRadius: 0.008), darkMetal, to: node, at: SIMD3(0, headBottom - 0.02, 0))
            let railY = headBottom - 0.06
            for z: Float in [-0.4, 0.4] {
                // Two short stands holding the rail ends.
                bar(SIMD3(0, railY, z), SIMD3(0, floor + 0.3, z), radius: 0.012, steel, to: node)
                for i in 0..<3 {
                    let a = Float(i) * 2 * .pi / 3
                    bar(SIMD3(0, floor + 0.3, z), SIMD3(sin(a) * 0.25, floor, z + cos(a) * 0.25), radius: 0.008, steel, to: node, segments: 6)
                }
            }
            add(SCNBox(width: 0.1, height: 0.03, length: 0.9, chamferRadius: 0.006), metal(white: 0.4, roughness: 0.3), to: node, at: SIMD3(0, railY, 0))
        case .handheld:
            // Shoulder pad and handles; no support to the floor.
            add(SCNBox(width: 0.1, height: 0.04, length: 0.16, chamferRadius: 0.015), rubber, to: node, at: SIMD3(0, -0.11, 0.12))
            for s: Float in [-1, 1] {
                bar(SIMD3(0, -0.1, -0.08), SIMD3(s * 0.22, -0.13, -0.2), radius: 0.01, steel, to: node, segments: 8)
                bar(SIMD3(s * 0.22, -0.13, -0.2), SIMD3(s * 0.22, -0.23, -0.2), radius: 0.016, rubber, to: node, segments: 8)
            }
        case .gimbal:
            // Three-axis gimbal frame with a twin handle.
            strap(SIMD3(-0.11, 0, 0.03), SIMD3(-0.11, 0.16, 0.03), width: 0.03, thickness: 0.015, blackMetal, to: node)
            strap(SIMD3(-0.11, 0.16, 0.03), SIMD3(0.0, 0.16, 0.03), width: 0.03, thickness: 0.015, blackMetal, to: node)
            bar(SIMD3(0, 0.16, 0.03), SIMD3(0, 0.3, 0.03), radius: 0.016, blackMetal, to: node)
            bar(SIMD3(-0.25, 0.32, 0.03), SIMD3(0.25, 0.32, 0.03), radius: 0.014, steel, to: node)
            for s: Float in [-1, 1] { bar(SIMD3(s * 0.25, 0.32, 0.03), SIMD3(s * 0.25, 0.2, 0.03), radius: 0.018, rubber, to: node, segments: 8) }
        }
    }
}
