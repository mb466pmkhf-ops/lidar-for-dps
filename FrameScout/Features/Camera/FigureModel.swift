import SceneKit
import UIKit
import simd

// Stand-in people for the 3D view. Same build as `person()` in web/src/ui/scene3d/models.ts, so a
// figure looks the same on the phone and on the desktop: keep the two in step.

extension SceneKitBuilder {
    /// A person with the height, build, skin tone, hair and posture set in the planner. Faces −Z.
    /// Neutral grey clothes so the light on the figure reads; a face (eyes, brow, nose, lips, ears)
    /// so you can see where the light falls, and glossy eyes so catchlights show.
    static func figure(_ c: PrevisCharacter, selected: Bool) -> SCNNode {
        FigureBuilder(c, selected: selected).build()
    }
}

private typealias V = SIMD3<Float>
private func v(_ x: Double, _ y: Double, _ z: Double) -> V { V(Float(x), Float(y), Float(z)) }

private final class FigureBuilder {
    let c: PrevisCharacter
    let root = SCNNode()
    let skin, top, legs, lip, hairM, eyeWhite, iris, shoe, sole, belt, chrome, stool: SCNMaterial

    init(_ c: PrevisCharacter, selected: Bool) {
        self.c = c
        func m(_ white: CGFloat? = nil, _ color: UIColor? = nil, rough: CGFloat, doubleSided: Bool = false) -> SCNMaterial {
            let x = SceneKitBuilder.material(color ?? UIColor(white: white ?? 0.5, alpha: 1), roughness: rough)
            x.isDoubleSided = doubleSided
            return x
        }
        let tone = c.skinTone.rgb
        skin = m(nil, SceneKitBuilder.uiColor(tone), rough: 0.52, doubleSided: true)
        top = m(nil, UIColor(red: 0x74 / 255, green: 0x78 / 255, blue: 0x7d / 255, alpha: 1), rough: 0.92)
        legs = m(nil, UIColor(red: 0x3c / 255, green: 0x40 / 255, blue: 0x46 / 255, alpha: 1), rough: 0.9)
        // Lips: the skin tone pulled a little towards red and darkened.
        let mix = { (a: Double, b: Double) in CGFloat((a + (b - a) * 0.28) * 0.88) }
        lip = m(nil, UIColor(red: mix(tone.r, 0.55), green: mix(tone.g, 0.25), blue: mix(tone.b, 0.235), alpha: 1), rough: 0.4)
        hairM = m(nil, UIColor(red: 0x22 / 255, green: 0x1a / 255, blue: 0x15 / 255, alpha: 1), rough: 0.72, doubleSided: true)
        eyeWhite = m(nil, UIColor(red: 0xc4 / 255, green: 0xbd / 255, blue: 0xb2 / 255, alpha: 1), rough: 0.12)
        iris = m(nil, UIColor(red: 0x2e / 255, green: 0x21 / 255, blue: 0x19 / 255, alpha: 1), rough: 0.08)
        shoe = m(nil, UIColor(red: 0x1c / 255, green: 0x19 / 255, blue: 0x17 / 255, alpha: 1), rough: 0.45)
        sole = m(nil, UIColor(red: 0x34 / 255, green: 0x31 / 255, blue: 0x2e / 255, alpha: 1), rough: 0.9)
        belt = m(nil, UIColor(red: 0x20 / 255, green: 0x1b / 255, blue: 0x17 / 255, alpha: 1), rough: 0.5)
        chrome = m(0.85, rough: 0.15)
        chrome.metalness.contents = 1.0
        stool = m(0.2, rough: 0.7)
        if selected {
            for x in [top, legs] { x.emission.contents = UIColor(white: 0.18, alpha: 1) }
        }
    }

    // MARK: Parts

    @discardableResult
    func add(_ g: SCNGeometry, _ m: SCNMaterial, _ at: V, to parent: SCNNode? = nil) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = at
        (parent ?? root).addChildNode(n)
        return n
    }

    @discardableResult
    func blob(_ r: Double, _ m: SCNMaterial, _ at: V, _ sx: Double = 1, _ sy: Double = 1, _ sz: Double = 1, seg: Int = 24, to parent: SCNNode? = nil) -> SCNNode {
        let s = SCNSphere(radius: CGFloat(r))
        s.segmentCount = seg
        let n = add(s, m, at, to: parent)
        n.simdScale = v(sx, sy, sz)
        return n
    }

    /// Points a Y-up node from `a` to `b`.
    func along(_ n: SCNNode, _ a: V, _ b: V) {
        let d = b - a
        n.simdPosition = a + d * 0.5
        if simd_length(d) > 1e-6 { n.simdOrientation = simd_quatf(from: V(0, 1, 0), to: simd_normalize(d)) }
    }

    /// A rounded limb between two points.
    func limb(_ a: V, _ b: V, _ r: Double, _ m: SCNMaterial, to parent: SCNNode? = nil) {
        let len = Double(simd_length(b - a))
        let g = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(len + 2 * r))
        g.radialSegmentCount = 14
        along(add(g, m, .zero, to: parent), a, b)
    }

    /// A limb that narrows from `r1` at `a` to `r2` at `b`, rounded at both ends.
    func taper(_ a: V, _ b: V, _ r1: Double, _ r2: Double, _ m: SCNMaterial) {
        let g = SCNCone(topRadius: CGFloat(r2), bottomRadius: CGFloat(r1), height: CGFloat(max(Double(simd_length(b - a)), 0.001)))
        g.radialSegmentCount = 16
        along(add(g, m, .zero), a, b)
        blob(r1, m, a, seg: 16)
        blob(r2, m, b, seg: 16)
    }

    @discardableResult
    func box(_ w: Double, _ h: Double, _ d: Double, _ chamfer: Double, _ m: SCNMaterial, _ at: V, to parent: SCNNode? = nil) -> SCNNode {
        add(SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: CGFloat(min(chamfer, w / 2, h / 2, d / 2))), m, at, to: parent)
    }

    /// A shell turned round the Y axis from (radius, height) pairs listed bottom to top, flattened front
    /// to back by `depth`. `shape` can push points about before flattening.
    func lathe(_ profile: [(Double, Double)], depth: Double = 1, segments: Int = 48, shape: ((inout V) -> Void)? = nil) -> SCNGeometry {
        var pos: [V] = []
        for (r, y) in profile {
            for j in 0..<segments {
                let t = Double(j) / Double(segments) * 2 * .pi
                var p = v(max(r, 1e-4) * sin(t), y, max(r, 1e-4) * cos(t))
                shape?(&p)
                p.z *= Float(depth)
                pos.append(p)
            }
        }
        var idx: [Int32] = []
        var nrm = [V](repeating: .zero, count: pos.count)
        for i in 0..<(profile.count - 1) {
            for j in 0..<segments {
                let a = i * segments + j, b = i * segments + (j + 1) % segments
                let c2 = (i + 1) * segments + j, d = (i + 1) * segments + (j + 1) % segments
                for tri in [(a, b, c2), (b, d, c2)] {
                    idx += [Int32(tri.0), Int32(tri.1), Int32(tri.2)]
                    let n = simd_cross(pos[tri.1] - pos[tri.0], pos[tri.2] - pos[tri.0])
                    nrm[tri.0] += n; nrm[tri.1] += n; nrm[tri.2] += n
                }
            }
        }
        let normals = nrm.map { simd_length($0) > 1e-9 ? simd_normalize($0) : V(0, 1, 0) }
        let sources = [SCNGeometrySource(vertices: pos.map { SCNVector3($0.x, $0.y, $0.z) }),
                       SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })]
        return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// A spherical cap from the top pole down to `cover` × 180°, like hair over the skull or an eyelid.
    func cap(_ radius: Double, cover: Double) -> SCNGeometry {
        let steps = 14
        let profile = (0...steps).map { i -> (Double, Double) in
            let phi = cover * .pi * Double(steps - i) / Double(steps)
            return (radius * sin(phi), radius * cos(phi))
        }
        return lathe(profile, segments: 36)
    }

    // MARK: Figure

    func build() -> SCNNode {
        let h = c.height, sitting = c.posture == .sitting
        let child = c.type.isChild, fem = c.type.shapeBlend, bust = !child && fem > 0.75
        let headH = h / (child ? 6 : 7.5), r = headH / 2
        let hip0 = h * 0.52, seat = min(0.45, hip0 * 0.5), drop = sitting ? hip0 - seat : 0
        let hipY = hip0 - drop, shoulderY = h - headH * 1.42 - drop, headY = h - r - drop
        let build = min(max(c.build, 0), 1)
        let sw = h * (0.1 + 0.035 * build + 0.008 * (1 - fem)), hw = h * (0.078 + 0.03 * build + 0.006 * fem)
        let depth = h * (0.105 + 0.05 * build)

        // Torso: trousers to a belt, then a loose top with a crew neck.
        let torsoH = shoulderY - hipY
        let waistY = hipY + torsoH * 0.36, chestY = shoulderY - torsoH * 0.3
        let chestR = sw * 0.88, waistR = hw * (0.98 - 0.12 * fem) + h * 0.012 * build, neckR = r * (0.44 - 0.06 * fem)
        let k = depth / (2 * chestR)
        let beltY = hipY + h * 0.06, crotchY = hipY - h * 0.035
        add(lathe([(0, crotchY), (hw * 0.7, crotchY + h * 0.004), (hw * 0.97, hipY), (hw * 1.01, hipY + h * 0.035),
                   (hw * 0.99, beltY + h * 0.012), (0, beltY + h * 0.012)], depth: k * 1.08), legs, .zero)
        add(SCNTorus(ringRadius: CGFloat(hw), pipeRadius: CGFloat(h * 0.007)), belt, v(0, beltY, 0)).simdScale = v(1, 1, k * 1.1)
        box(h * 0.03, h * 0.022, h * 0.006, h * 0.002, chrome, v(0, beltY, -hw * k * 1.1 - h * 0.004)) // buckle
        let shirt: [(Double, Double)] = [
            (hw * 1.03, beltY + h * 0.016), ((hw + waistR) * 0.53, waistY - torsoH * 0.12), (waistR * 1.02, waistY), (chestR, chestY),
            (sw * 0.92, shoulderY - h * 0.045), (sw * 0.84, shoulderY - h * 0.01), (sw * 0.58, shoulderY + h * 0.012),
            (neckR * 1.55, shoulderY + h * 0.024), (neckR * 1.12, shoulderY + h * 0.03),
        ]
        // A soft bust pushed out of the front of the top (before flattening).
        let bustShape: ((inout V) -> Void)? = bust ? { (p: inout V) in
            guard p.z < 0 else { return }
            let dx = Double(abs(p.x)) - chestR * 0.42, dy = Double(p.y) - (chestY - h * 0.02)
            let lift = h * 0.032 * exp(-(dx * dx) / (chestR * chestR * 0.09) - (dy * dy) / (h * h * 0.0018))
            p.z -= Float(lift / k * min(1, Double(-p.z) / chestR))
        } : nil
        add(lathe(shirt, depth: k, shape: bustShape), top, .zero)
        let collar = add(SCNTorus(ringRadius: CGFloat(neckR * 1.14), pipeRadius: CGFloat(h * 0.0035)), top, v(0, shoulderY + h * 0.028, 0))
        collar.simdEulerAngles = v(-0.22, 0, 0)
        collar.simdScale = v(1, 1, 0.9)

        // Neck and head. The skull sits a little back; the jaw, chin, nose, brow and lips build the face.
        let neck = SCNCone(topRadius: CGFloat(neckR * 0.94), bottomRadius: CGFloat(neckR), height: 1)
        let neckA = v(0, shoulderY + h * 0.012, h * 0.006), neckB = v(0, headY - r * 0.38, r * 0.16)
        neck.height = CGFloat(simd_length(neckB - neckA))
        along(add(neck, skin, .zero), neckA, neckB)
        let skullC = v(0, headY + r * 0.06, r * 0.1)
        blob(r, skin, skullC, 0.78, 0.9, 0.9, seg: 32)
        blob(r * 0.55, skin, v(0, headY - r * 0.4, -r * 0.3), 1.12 - 0.12 * fem, 1, 1)          // jaw and mouth
        blob(r * 0.24, skin, v(0, headY - r * 0.83, -r * 0.55), 1.15 - 0.15 * fem, 0.8, 0.9)     // chin
        for s in [-1.0, 1.0] {
            blob(r * 0.25, skin, v(s * r * 0.77, headY - r * 0.1, r * 0.12), 0.34, 1, 0.62).simdEulerAngles = v(0, s * 0.3, 0) // ear
            let eye = v(s * r * 0.29, headY - r * 0.04, -r * 0.7)
            blob(r * 0.1, eyeWhite, eye, seg: 18)
            blob(r * 0.062, iris, eye + v(0, 0, -r * 0.07), 1, 1, 0.55, seg: 14)
            add(cap(r * 0.106, cover: 0.3), skin, eye).simdEulerAngles = v(-0.3, 0, 0)            // upper lid
            limb(v(s * r * 0.13, headY + r * 0.155, -r * 0.83), v(s * r * 0.44, headY + r * 0.165, -r * 0.74), r * 0.022, hairM) // eyebrow
        }
        limb(v(-r * 0.4, headY + r * 0.09, -r * 0.76), v(r * 0.4, headY + r * 0.09, -r * 0.76), r * 0.06, skin) // brow ridge
        let bridge = SCNCone(topRadius: CGFloat(r * 0.085), bottomRadius: CGFloat(r * 0.055), height: 1)
        let bridgeA = v(0, headY + r * 0.02, -r * 0.82), bridgeB = v(0, headY - r * 0.3, -r * 0.96)
        bridge.height = CGFloat(simd_length(bridgeB - bridgeA))
        along(add(bridge, skin, .zero), bridgeA, bridgeB)
        blob(r * 0.1, skin, v(0, headY - r * 0.33, -r * 0.97), 1, 0.85, 0.9, seg: 16)              // nose tip
        for s in [-1.0, 1.0] { blob(r * 0.068, skin, v(s * r * 0.09, headY - r * 0.37, -r * 0.89), seg: 12) }
        blob(r * 0.16, lip, v(0, headY - r * 0.56, -r * 0.84), 1, 0.22, 0.34, seg: 16)
        blob(r * 0.14, lip, v(0, headY - r * 0.63, -r * 0.82), 1, 0.27, 0.34, seg: 16)
        hair(c.hairStyle, skullC, r, headY)

        // Arms: sleeves to the wrist, a cuff, then the hand.
        let ar = h * (0.021 + 0.008 * build)
        for s in [-1.0, 1.0] {
            let shoulder = v(s * (sw * 0.86 - ar * 0.2), shoulderY - ar * 0.95, 0)
            let elbow = sitting ? v(s * (sw + h * 0.02), shoulderY - h * 0.175, -h * 0.025) : v(s * (sw + h * 0.022), shoulderY - h * 0.185, h * 0.008)
            let wrist = sitting ? v(s * sw * 0.72, hipY + h * 0.085, -h * 0.17) : v(s * (sw + h * 0.03), shoulderY - h * 0.345, -h * 0.03)
            taper(shoulder, elbow, ar * 1.18, ar * 0.86, top)
            let fore = simd_normalize(wrist - elbow)
            let cuff = wrist - fore * Float(h * 0.012)
            taper(elbow, cuff, ar * 0.9, ar * 0.7, top)
            let wristBar = SCNCone(topRadius: CGFloat(ar * 0.46), bottomRadius: CGFloat(ar * 0.5), height: CGFloat(h * 0.012))
            along(add(wristBar, skin, .zero), cuff, wrist)
            hand(wrist, fore, h, s, sitting ? s * .pi / 2 : 0)
        }

        // Legs: trousers with a soft knee, then shoes with a sole.
        let tr = h * (0.044 + 0.016 * build), sr = h * (0.029 + 0.008 * build)
        for s in [-1.0, 1.0] {
            let hip = v(s * hw * 0.5, hipY - h * 0.008, 0)
            let knee = sitting ? v(s * hw * 0.68, hipY + h * 0.005, -h * 0.245) : v(s * hw * 0.5, h * 0.285, -h * 0.008)
            let ankle = sitting ? v(s * hw * 0.68, h * 0.055, -h * 0.245 - max(0, h * 0.24 - hipY) * 0.9) : v(s * hw * 0.48, h * 0.055, h * 0.006)
            taper(hip, knee, tr, sr * 1.08, legs)
            taper(knee, ankle, sr * 1.05, sr * 0.82, legs)
            let foot = V(ankle.x, 0, ankle.z)
            box(h * 0.05, h * 0.012, h * 0.152, h * 0.005, sole, foot + v(0, h * 0.006, -h * 0.038))
            blob(h * 0.027, shoe, foot + v(0, h * 0.026, -h * 0.078), 0.95, 0.62, 1.55, seg: 18)      // toe box
            blob(h * 0.029, shoe, foot + v(0, h * 0.03, h * 0.006), 0.9, 0.95, 1.05, seg: 18)         // heel and collar
        }
        if sitting {
            // A stool so a seated figure doesn't float when there's no chair under it.
            let p = c.proportions
            box(p.hipWidth * 1.3, p.seatHeight, p.hipWidth * 1.2, 0.01, stool, v(0, p.seatHeight / 2, 0.02))
        }
        // One mesh per material, so a person costs a handful of draw calls.
        return root.flattenedClone()
    }

    /// A hand hanging from the wrist along `dir`: palm, four fingers and a thumb. `s` is the side (±1); `roll` turns the palm.
    func hand(_ wrist: V, _ dir: V, _ h: Double, _ s: Double, _ roll: Double) {
        let g = SCNNode()
        g.simdPosition = wrist
        g.simdOrientation = simd_quatf(from: V(0, -1, 0), to: simd_normalize(dir)) * simd_quatf(angle: Float(roll), axis: V(0, 1, 0))
        root.addChildNode(g)
        let palmL = h * 0.058, width = h * 0.044, thick = h * 0.019, fingerL = h * 0.046, fr = width / 8.6
        box(thick, palmL, width, thick * 0.45, skin, v(0, -palmL / 2, 0), to: g)
        for (i, len) in [0.92, 1, 0.95, 0.78].enumerated() {
            let z = (-1.5 + Double(i)) * (width / 4) * 0.98
            let l = fingerL * len
            let base = v(-s * thick * 0.05, -palmL + fr * 0.6, z)
            let mid = base + v(-s * l * 0.12, -l * 0.55, 0)
            let tip = mid + v(-s * l * 0.22, -l * 0.4, 0) // a relaxed curl towards the palm
            limb(base, mid, fr, skin, to: g)
            limb(mid, tip, fr * 0.92, skin, to: g)
        }
        let t0 = v(-s * thick * 0.25, -palmL * 0.3, -width * 0.44)
        let t1 = t0 + v(-s * h * 0.012, -h * 0.022, -h * 0.01)
        let t2 = t1 + v(-s * h * 0.008, -h * 0.016, -h * 0.002)
        limb(t0, t1, fr * 1.25, skin, to: g)
        limb(t1, t2, fr * 1.1, skin, to: g)
    }

    /// Hair over the skull (centre `c`, radius `r`, flattened like the skull).
    func hair(_ style: HairStyle, _ c: V, _ r: Double, _ headY: Double) {
        @discardableResult
        func capNode(_ grow: Double, _ cover: Double, _ tilt: Double) -> SCNNode {
            let n = add(cap(r * grow, cover: cover), hairM, c)
            n.simdScale = v(0.79, 0.9, 0.91)
            n.simdEulerAngles = v(tilt, 0, 0)
            return n
        }
        switch style {
        case .bald: return
        case .cropped: capNode(1.025, 0.56, 0.52)
        case .short: capNode(1.07, 0.6, 0.5).simdScale = v(0.79, 0.9 * 0.95, 0.91)
        case .tied:
            capNode(1.04, 0.6, 0.42)
            blob(r * 0.36, hairM, v(0, headY + r * 0.3, r * 1.02), seg: 18)
        case .long:
            // A full cap, a fall of hair down the back to the shoulders and curtains over the ears.
            capNode(1.07, 0.6, 0.4)
            blob(r * 0.92, hairM, v(0, headY - r * 0.62, r * 0.5), 0.9, 1.45, 0.52, seg: 28)
            for s in [-1.0, 1.0] {
                blob(r * 0.85, hairM, v(s * r * 0.7, headY - r * 0.72, r * 0.25), 0.26, 1.5, 0.85).simdEulerAngles = v(0, 0, -s * 0.1)
            }
        }
    }
}
