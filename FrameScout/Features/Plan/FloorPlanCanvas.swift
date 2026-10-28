import SwiftUI

/// Maps plan metres ↔ screen points. Screen x = world x, screen y = world z (top-down, -Z up).
struct PlanViewport: Equatable {
    var scale: CGFloat
    var offset: CGPoint

    func toScreen(_ p: PlanPoint) -> CGPoint {
        CGPoint(x: offset.x + CGFloat(p.x) * scale, y: offset.y + CGFloat(p.z) * scale)
    }

    func toWorld(_ s: CGPoint) -> PlanPoint {
        PlanPoint(x: Double((s.x - offset.x) / scale), z: Double((s.y - offset.y) / scale))
    }

    static func fit(_ bounds: PlanRect, in size: CGSize, padding: CGFloat = 24) -> PlanViewport {
        let w = max(bounds.width, 0.5), d = max(bounds.depth, 0.5)
        let scale = max(1, min((size.width - 2 * padding) / CGFloat(w), (size.height - 2 * padding) / CGFloat(d)))
        let c = bounds.center
        return PlanViewport(scale: scale,
                            offset: CGPoint(x: size.width / 2 - CGFloat(c.x) * scale,
                                            y: size.height / 2 - CGFloat(c.z) * scale))
    }

    /// Screen direction for a world bearing (0° = up, clockwise).
    static func direction(_ bearing: Double) -> CGVector {
        let r = bearing * .pi / 180
        return CGVector(dx: sin(r), dy: -cos(r))
    }
}

struct PlanCameraMarker: Identifiable {
    var id: UUID
    var label: String
    var rig: CameraRig
    var isShot = false
    var selected = false
    /// Length of the FOV wedge in metres (subject distance when known).
    var reach: Double = 4
}

struct PlanLightMarker: Identifiable {
    var light: LightFixture
    var selected = false
    var id: UUID { light.id }
}

struct PlanSubjectMarker: Identifiable {
    var id: UUID
    var label: String
    var point: PlanPoint
    var selected = false
}

struct PlanMeasureLine: Identifiable {
    var id = UUID()
    var a: PlanPoint
    var b: PlanPoint
    var label: String
    var live = false
}

/// A text label waiting for collision-free placement on the plan.
struct PlanLabel {
    enum Priority: Int {
        case camera, light, subject, dimension, object
        var alwaysShown: Bool { self == .camera || self == .light || self == .subject }
    }
    var text: Text
    var anchor: CGPoint
    var priority: Priority
}

struct PlanOverlay {
    var cameras: [PlanCameraMarker] = []
    var subjects: [PlanSubjectMarker] = []
    var lights: [PlanLightMarker] = []
    var measurements: [PlanMeasureLine] = []
    var photoPoses: [PhotoPose] = []
    /// World bearing of true north (derived from the scan's north offset).
    var northWorldBearing: Double?
    /// World bearing pointing towards the sun, and its elevation.
    var sunWorldBearing: Double?
    var sunElevation: Double?
    var litWindows: Set<UUID> = []
    var showDimensions = true
    var showGrid = true
}

enum PlanStyle {
    case thumbnail, full
}

struct FloorPlanCanvas: View {
    let plan: FloorPlan
    var overlay = PlanOverlay()
    var style: PlanStyle = .full
    /// Explicit viewport (interactive editor). `nil` fits the plan to the view.
    var viewport: PlanViewport? = nil

    var body: some View {
        Canvas { context, size in
            let vp = viewport ?? PlanViewport.fit(fitBounds, in: size, padding: style == .thumbnail ? 4 : 28)
            PlanRenderer(plan: plan, overlay: overlay, style: style, vp: vp, size: size).draw(in: &context)
        }
        .accessibilityLabel("Top-down floor plan")
    }

    private var fitBounds: PlanRect {
        var b = plan.isEmpty ? PlanRect.unit : plan.bounds
        let extra = overlay.cameras.map(\.rig.position) + overlay.subjects.map(\.point) + overlay.lights.map(\.light.position)
        if let e = PlanRect.enclosing(extra) { b = b.union(e) }
        return b
    }
}

struct PlanRenderer {
    let plan: FloorPlan
    let overlay: PlanOverlay
    let style: PlanStyle
    let vp: PlanViewport
    let size: CGSize

    private var full: Bool { style == .full }
    private func s(_ p: PlanPoint) -> CGPoint { vp.toScreen(p) }
    private func px(_ metres: Double) -> CGFloat { CGFloat(metres) * vp.scale }

    func draw(in ctx: inout GraphicsContext) {
        var labels: [PlanLabel] = []
        if full && overlay.showGrid { drawGrid(&ctx) }
        drawFloors(&ctx)
        drawOccupancy(&ctx)
        drawObjects(&ctx, &labels)
        drawWalls(&ctx)
        drawApertures(&ctx)
        if full {
            if overlay.showDimensions { drawWallDimensions(&labels) }
            drawPhotoPoses(&ctx)
            drawLights(&ctx, &labels)
            drawCameras(&ctx, &labels)
            drawSubjects(&ctx, &labels)
            drawLabels(&ctx, labels)
            drawMeasurements(&ctx)
            drawSun(&ctx)
            drawNorth(&ctx)
            drawScaleBar(&ctx)
        }
    }

    // MARK: Layers

    private func drawGrid(_ ctx: inout GraphicsContext) {
        let tl = vp.toWorld(.zero), br = vp.toWorld(CGPoint(x: size.width, y: size.height))
        let step: Double = vp.scale > 25 ? 1 : (vp.scale > 8 ? 5 : 10)
        var path = Path()
        var x = (tl.x / step).rounded(.down) * step
        while x <= br.x {
            path.move(to: s(PlanPoint(x: x, z: tl.z)))
            path.addLine(to: s(PlanPoint(x: x, z: br.z)))
            x += step
        }
        var z = (tl.z / step).rounded(.down) * step
        while z <= br.z {
            path.move(to: s(PlanPoint(x: tl.x, z: z)))
            path.addLine(to: s(PlanPoint(x: br.x, z: z)))
            z += step
        }
        ctx.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 1)
    }

    private func drawFloors(_ ctx: inout GraphicsContext) {
        for poly in plan.floorPolygons where poly.count >= 3 {
            var path = Path()
            path.move(to: s(poly[0]))
            for p in poly.dropFirst() { path.addLine(to: s(p)) }
            path.closeSubpath()
            ctx.fill(path, with: .color(Theme.planFloor))
        }
    }

    private func drawOccupancy(_ ctx: inout GraphicsContext) {
        guard !plan.occupancy.isEmpty else { return }
        let cell = max(1, px(plan.occupancyCellSize))
        var path = Path()
        for p in plan.occupancy {
            let c = s(p)
            path.addRect(CGRect(x: c.x - cell / 2, y: c.y - cell / 2, width: cell, height: cell))
        }
        ctx.fill(path, with: .color(Theme.planWall.opacity(0.75)))
    }

    private func drawObjects(_ ctx: inout GraphicsContext, _ labels: inout [PlanLabel]) {
        for o in plan.objects {
            let ux = CGVector(dx: cos(o.rotation), dy: sin(o.rotation))
            let uz = CGVector(dx: -ux.dy, dy: ux.dx)
            let c = s(o.center)
            let hw = px(o.width / 2), hd = px(o.depth / 2)
            func corner(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
                CGPoint(x: c.x + ux.dx * a * hw + uz.dx * b * hd, y: c.y + ux.dy * a * hw + uz.dy * b * hd)
            }
            var path = Path()
            path.move(to: corner(-1, -1))
            path.addLine(to: corner(1, -1))
            path.addLine(to: corner(1, 1))
            path.addLine(to: corner(-1, 1))
            path.closeSubpath()
            ctx.fill(path, with: .color(Theme.planObject.opacity(0.18)))
            ctx.stroke(path, with: .color(Theme.planObject), lineWidth: 1)
            if full && vp.scale > 40 {
                labels.append(PlanLabel(text: Text(o.category).font(.poppins(.light, 9)).foregroundColor(Theme.textSecondary),
                                        anchor: c, priority: .object))
            }
        }
    }

    private func drawWalls(_ ctx: inout GraphicsContext) {
        var path = Path()
        for w in plan.walls {
            path.move(to: s(w.a))
            path.addLine(to: s(w.b))
        }
        let width = full ? max(2, px(0.1)) : max(1.2, px(0.1))
        ctx.stroke(path, with: .color(Theme.planWall), style: StrokeStyle(lineWidth: width, lineCap: .square))
    }

    private func drawApertures(_ ctx: inout GraphicsContext) {
        let wallWidth = full ? max(2, px(0.1)) : max(1.2, px(0.1))
        let centroid = plan.interiorCentroid
        // Cut the gap out of the wall first.
        for seg in plan.doors + plan.windows + plan.openings {
            var gap = Path()
            gap.move(to: s(seg.a))
            gap.addLine(to: s(seg.b))
            ctx.stroke(gap, with: .color(Theme.background), lineWidth: wallWidth + 1)
        }
        for w in plan.windows {
            var path = Path()
            path.move(to: s(w.a))
            path.addLine(to: s(w.b))
            let lit = overlay.litWindows.contains(w.id)
            ctx.stroke(path, with: .color(lit ? Theme.sun : Theme.planWindow), lineWidth: max(2, wallWidth * 0.8))
            if lit && full {
                // Light spill into the room.
                let inward = inwardNormal(w, centroid: centroid)
                var spill = Path()
                spill.move(to: s(w.a))
                spill.addLine(to: s(w.b))
                spill.addLine(to: s(w.b + inward * 1.2))
                spill.addLine(to: s(w.a + inward * 1.2))
                spill.closeSubpath()
                ctx.fill(spill, with: .color(Theme.sun.opacity(0.18)))
            }
        }
        for o in plan.openings {
            var path = Path()
            path.move(to: s(o.a))
            path.addLine(to: s(o.b))
            ctx.stroke(path, with: .color(Theme.planWall.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        for d in plan.doors {
            var path = Path()
            path.move(to: s(d.a))
            path.addLine(to: s(d.b))
            ctx.stroke(path, with: .color(Theme.planDoor), lineWidth: 2)
            guard full else { continue }
            // Swing arc into the room, hinged at `a`.
            let inward = inwardNormal(d, centroid: centroid)
            let along = (d.b - d.a) * (1 / max(d.length, 0.01))
            var arc = Path()
            arc.move(to: s(d.a))
            for i in 0...12 {
                let t = Double(i) / 12 * .pi / 2
                let dir = along * cos(t) + inward * sin(t)
                arc.addLine(to: s(d.a + dir * d.length))
            }
            arc.closeSubpath()
            ctx.stroke(arc, with: .color(Theme.planDoor.opacity(0.5)), lineWidth: 1)
        }
    }

    private func inwardNormal(_ seg: PlanSegment, centroid: PlanPoint) -> PlanPoint {
        let d = seg.b - seg.a
        let len = max(seg.length, 0.001)
        var n = PlanPoint(x: -d.z / len, z: d.x / len)
        let toC = centroid - seg.midpoint
        if n.x * toC.x + n.z * toC.z < 0 { n = n * -1 }
        return n
    }

    private func drawWallDimensions(_ labels: inout [PlanLabel]) {
        guard vp.scale > 18 else { return }
        let centroid = plan.interiorCentroid
        for w in plan.walls where w.length > 0.6 {
            let n = inwardNormal(w, centroid: centroid)
            let pos = s(w.midpoint + n * (14 / Double(vp.scale)))
            labels.append(PlanLabel(text: Text(UnitsFormatter.distance(w.length))
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary),
                                    anchor: pos, priority: .dimension))
        }
    }

    private func drawPhotoPoses(_ ctx: inout GraphicsContext) {
        for pose in overlay.photoPoses {
            let c = s(pose.position)
            let dir = PlanViewport.direction(pose.bearing)
            var path = Path()
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + dir.dx * 14, y: c.y + dir.dy * 14))
            ctx.stroke(path, with: .color(Theme.info), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Theme.info))
        }
    }

    private func drawCameras(_ ctx: inout GraphicsContext, _ labels: inout [PlanLabel]) {
        for cam in overlay.cameras {
            let origin = s(cam.rig.position)
            let half = cam.rig.horizontalFOV / 2
            let color = cam.isShot ? Theme.info : Theme.accent
            var wedge = Path()
            wedge.move(to: origin)
            let steps = 16
            for i in 0...steps {
                let b = cam.rig.pan - half + Double(i) / Double(steps) * 2 * half
                let d = PlanViewport.direction(b)
                wedge.addLine(to: CGPoint(x: origin.x + d.dx * px(cam.reach), y: origin.y + d.dy * px(cam.reach)))
            }
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(color.opacity(cam.selected ? 0.28 : 0.12)))
            ctx.stroke(wedge, with: .color(color.opacity(cam.selected ? 0.95 : 0.55)), lineWidth: cam.selected ? 1.5 : 1)

            // Camera body: rectangle rotated to the pan direction.
            let d = PlanViewport.direction(cam.rig.pan)
            let side = CGVector(dx: -d.dy, dy: d.dx)
            let bodyLength: CGFloat = 16, bodyWidth: CGFloat = 11
            func pt(_ f: CGFloat, _ l: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + d.dx * f + side.dx * l, y: origin.y + d.dy * f + side.dy * l)
            }
            var body = Path()
            body.move(to: pt(-bodyLength / 2, -bodyWidth / 2))
            body.addLine(to: pt(bodyLength / 2, -bodyWidth / 2))
            body.addLine(to: pt(bodyLength / 2 + 6, -bodyWidth / 2 - 3))
            body.addLine(to: pt(bodyLength / 2 + 6, bodyWidth / 2 + 3))
            body.addLine(to: pt(bodyLength / 2, bodyWidth / 2))
            body.addLine(to: pt(-bodyLength / 2, bodyWidth / 2))
            body.closeSubpath()
            ctx.fill(body, with: .color(color))
            if cam.selected {
                ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - 18, y: origin.y - 18, width: 36, height: 36)),
                           with: .color(.white), lineWidth: 1.5)
            }
            let labelPos = CGPoint(x: origin.x - d.dx * 22, y: origin.y - d.dy * 22)
            labels.append(PlanLabel(text: Text("\(cam.label) · \(Optics.formatFocal(cam.rig.focalLength))")
                                        .font(.poppins(.medium, 10))
                                        .foregroundColor(color),
                                    anchor: labelPos, priority: .camera))
        }
    }

    /// Lighting-diagram units: a beam tinted by colour temperature for lights, a board for grip.
    private func drawLights(_ ctx: inout GraphicsContext, _ labels: inout [PlanLabel]) {
        for marker in overlay.lights {
            let light = marker.light
            let origin = s(light.position)
            let d = PlanViewport.direction(light.pan)
            let side = CGVector(dx: -d.dy, dy: d.dx)
            let rgb = Kelvin.rgb(light.colorTemperature)
            let tint = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
            let on = light.isOn
            let halfWidth = max(px(light.width) / 2, 6)

            if light.kind.emits {
                // Beam: wedge whose reach follows the dimmer, fading out.
                if on {
                    let reach = px(1.5 + 3 * light.dimmer)
                    let half = min(light.beamAngle, 170) / 2
                    var beam = Path()
                    beam.move(to: CGPoint(x: origin.x + side.dx * halfWidth * 0.6, y: origin.y + side.dy * halfWidth * 0.6))
                    for i in 0...16 {
                        let b = light.pan - half + Double(i) / 16 * 2 * half
                        let v = PlanViewport.direction(b)
                        beam.addLine(to: CGPoint(x: origin.x + v.dx * reach, y: origin.y + v.dy * reach))
                    }
                    beam.addLine(to: CGPoint(x: origin.x - side.dx * halfWidth * 0.6, y: origin.y - side.dy * halfWidth * 0.6))
                    beam.closeSubpath()
                    let end = CGPoint(x: origin.x + d.dx * reach, y: origin.y + d.dy * reach)
                    ctx.fill(beam, with: .linearGradient(Gradient(colors: [tint.opacity(marker.selected ? 0.5 : 0.35), tint.opacity(0)]),
                                                         startPoint: origin, endPoint: end))
                }
                // Unit body: rounded block across the beam, sized to the unit.
                func pt(_ f: CGFloat, _ l: CGFloat) -> CGPoint {
                    CGPoint(x: origin.x + d.dx * f + side.dx * l, y: origin.y + d.dy * f + side.dy * l)
                }
                let depth: CGFloat = light.kind == .tube ? 5 : 10
                var body = Path()
                body.move(to: pt(-depth / 2, -halfWidth))
                body.addLine(to: pt(depth / 2, -halfWidth))
                body.addLine(to: pt(depth / 2, halfWidth))
                body.addLine(to: pt(-depth / 2, halfWidth))
                body.closeSubpath()
                ctx.fill(body, with: .color(on ? tint : Theme.textTertiary))
                ctx.stroke(body, with: .color(.black.opacity(0.6)), lineWidth: 1)
            } else {
                // Grip: a board across the facing direction. White bounce, black neg, grey flag,
                // hatched diffusion.
                let a = CGPoint(x: origin.x - side.dx * halfWidth, y: origin.y - side.dy * halfWidth)
                let b = CGPoint(x: origin.x + side.dx * halfWidth, y: origin.y + side.dy * halfWidth)
                var board = Path()
                board.move(to: a)
                board.addLine(to: b)
                let color: Color
                switch light.kind {
                case .bounce: color = .white
                case .negative: color = Color(white: 0.05)
                case .diffusion: color = Color(white: 0.85)
                default: color = Color(white: 0.45)
                }
                if light.kind == .negative {
                    ctx.stroke(board, with: .color(.white.opacity(0.7)), lineWidth: 7)
                }
                ctx.stroke(board, with: .color(color),
                           style: StrokeStyle(lineWidth: 5, lineCap: .butt, dash: light.kind == .diffusion ? [3, 2] : []))
                // Small tick showing which side faces the action.
                var face = Path()
                face.move(to: origin)
                face.addLine(to: CGPoint(x: origin.x + d.dx * 8, y: origin.y + d.dy * 8))
                ctx.stroke(face, with: .color(color.opacity(0.8)), lineWidth: 1.5)
            }
            if marker.selected {
                let r = max(halfWidth + 6, 18)
                ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white), lineWidth: 1.5)
            }
            let labelPos = CGPoint(x: origin.x - d.dx * 20, y: origin.y - d.dy * 20)
            let text = light.kind.emits && !light.power.isEmpty ? "\(light.name) · \(light.power)" : light.name
            labels.append(PlanLabel(text: Text(text).font(.poppins(.medium, 10))
                                        .foregroundColor(light.kind.emits && on ? tint : Theme.textSecondary),
                                    anchor: labelPos, priority: .light))
        }
    }

    private func drawSubjects(_ ctx: inout GraphicsContext, _ labels: inout [PlanLabel]) {
        for subject in overlay.subjects {
            let c = s(subject.point)
            let r: CGFloat = subject.selected ? 9 : 7
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.danger))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)),
                       with: .color(Theme.danger.opacity(0.5)), lineWidth: 1)
            labels.append(PlanLabel(text: Text(subject.label).font(.poppins(.medium, 10)).foregroundColor(Theme.danger),
                                    anchor: CGPoint(x: c.x, y: c.y + r + 10), priority: .subject))
        }
    }

    /// Draws labels most important first, nudging each one clear of those already placed.
    /// Cameras and subjects are always drawn; dimensions and furniture names are dropped
    /// rather than drawn on top of something else.
    private func drawLabels(_ ctx: inout GraphicsContext, _ labels: [PlanLabel]) {
        // Camera bodies and subject marks are obstacles too, so labels never cover them.
        var placed: [CGRect] = overlay.cameras.map { c in
            let p = s(c.rig.position); return CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)
        } + overlay.subjects.map { m in
            let p = s(m.point); return CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)
        } + overlay.lights.map { l in
            let p = s(l.light.position); return CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
        }
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        for label in labels.sorted(by: { $0.priority.rawValue < $1.priority.rawValue }) {
            let resolved = ctx.resolve(label.text)
            let size = resolved.measure(in: CGSize(width: 300, height: 40))
            let step = size.height + 3
            let offsets: [CGPoint] = [.zero, CGPoint(x: 0, y: step), CGPoint(x: 0, y: -step),
                                      CGPoint(x: 0, y: 2 * step), CGPoint(x: 0, y: -2 * step),
                                      CGPoint(x: size.width / 2 + 8, y: 0), CGPoint(x: -size.width / 2 - 8, y: 0)]
            func rect(_ o: CGPoint) -> CGRect {
                CGRect(x: label.anchor.x + o.x - size.width / 2 - 3, y: label.anchor.y + o.y - size.height / 2 - 1,
                       width: size.width + 6, height: size.height + 2)
            }
            let free = offsets.first { o in bounds.contains(rect(o)) && !placed.contains { $0.intersects(rect(o)) } }
            guard let offset = free ?? (label.priority.alwaysShown ? CGPoint.zero : nil) else { continue }
            var box = rect(offset)
            // Keep always-shown labels on screen even when no free slot was found.
            box.origin.x = min(max(box.minX, bounds.minX), max(bounds.minX, bounds.maxX - box.width))
            box.origin.y = min(max(box.minY, bounds.minY), max(bounds.minY, bounds.maxY - box.height))
            placed.append(box)
            ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Theme.background.opacity(0.7)))
            ctx.draw(resolved, at: CGPoint(x: box.midX, y: box.midY))
        }
    }

    private func drawMeasurements(_ ctx: inout GraphicsContext) {
        for m in overlay.measurements {
            let a = s(m.a), b = s(m.b)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            let color = m.live ? Color.white : Theme.accent
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: m.live ? [6, 4] : []))
            for p in [a, b] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(color))
            }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let text = Text(m.label).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.black)
            let resolved = ctx.resolve(text)
            let sz = resolved.measure(in: CGSize(width: 300, height: 40))
            let bg = CGRect(x: mid.x - sz.width / 2 - 5, y: mid.y - sz.height / 2 - 3, width: sz.width + 10, height: sz.height + 6)
            ctx.fill(Path(roundedRect: bg, cornerRadius: 5), with: .color(color))
            ctx.draw(resolved, at: mid)
        }
    }

    private func drawSun(_ ctx: inout GraphicsContext) {
        guard let bearing = overlay.sunWorldBearing else { return }
        let up = (overlay.sunElevation ?? 1) > 0
        let d = PlanViewport.direction(bearing)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 26
        let sunPoint = CGPoint(x: centre.x + d.dx * radius, y: centre.y + d.dy * radius)
        let color = up ? Theme.sun : Theme.textTertiary
        // Light travels from the sun into the location.
        var ray = Path()
        ray.move(to: sunPoint)
        let tip = CGPoint(x: centre.x + d.dx * radius * 0.45, y: centre.y + d.dy * radius * 0.45)
        ray.addLine(to: tip)
        ctx.stroke(ray, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
        let side = CGVector(dx: -d.dy, dy: d.dx)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x + d.dx * 12 + side.dx * 6, y: tip.y + d.dy * 12 + side.dy * 6))
        head.addLine(to: CGPoint(x: tip.x + d.dx * 12 - side.dx * 6, y: tip.y + d.dy * 12 - side.dy * 6))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
        ctx.fill(Path(ellipseIn: CGRect(x: sunPoint.x - 11, y: sunPoint.y - 11, width: 22, height: 22)), with: .color(color))
        var symbol = ctx.resolve(Image(systemName: up ? "sun.max.fill" : "moon.fill"))
        symbol.shading = .color(.black)
        ctx.draw(symbol, at: sunPoint)
    }

    private func drawNorth(_ ctx: inout GraphicsContext) {
        guard let north = overlay.northWorldBearing else { return }
        let c = CGPoint(x: size.width - 30, y: 34)
        let d = PlanViewport.direction(north)
        let side = CGVector(dx: -d.dy, dy: d.dx)
        var arrow = Path()
        arrow.move(to: CGPoint(x: c.x + d.dx * 16, y: c.y + d.dy * 16))
        arrow.addLine(to: CGPoint(x: c.x - d.dx * 10 + side.dx * 8, y: c.y - d.dy * 10 + side.dy * 8))
        arrow.addLine(to: CGPoint(x: c.x - d.dx * 4, y: c.y - d.dy * 4))
        arrow.addLine(to: CGPoint(x: c.x - d.dx * 10 - side.dx * 8, y: c.y - d.dy * 10 - side.dy * 8))
        arrow.closeSubpath()
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44)), with: .color(.black.opacity(0.5)))
        ctx.fill(arrow, with: .color(Theme.danger))
        ctx.draw(Text("N").font(.poppins(.medium, 10)).foregroundColor(.white),
                 at: CGPoint(x: c.x + d.dx * 27, y: c.y + d.dy * 27))
    }

    private func drawScaleBar(_ ctx: inout GraphicsContext) {
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 20, 50]
        let metres = candidates.first { px($0) >= 60 } ?? 50
        let length = px(metres)
        let origin = CGPoint(x: 16, y: size.height - 18)
        var bar = Path()
        bar.move(to: origin)
        bar.addLine(to: CGPoint(x: origin.x + length, y: origin.y))
        bar.move(to: CGPoint(x: origin.x, y: origin.y - 4))
        bar.addLine(to: CGPoint(x: origin.x, y: origin.y + 4))
        bar.move(to: CGPoint(x: origin.x + length, y: origin.y - 4))
        bar.addLine(to: CGPoint(x: origin.x + length, y: origin.y + 4))
        ctx.stroke(bar, with: .color(Theme.textSecondary), lineWidth: 1.5)
        ctx.draw(Text(UnitsFormatter.distance(metres)).font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundColor(Theme.textSecondary),
                 at: CGPoint(x: origin.x + length / 2, y: origin.y - 10))
    }
}
