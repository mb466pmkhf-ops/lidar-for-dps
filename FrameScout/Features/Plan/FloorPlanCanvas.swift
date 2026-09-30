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

struct PlanOverlay {
    var cameras: [PlanCameraMarker] = []
    var subjects: [PlanSubjectMarker] = []
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
        let extra = overlay.cameras.map(\.rig.position) + overlay.subjects.map(\.point)
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
        if full && overlay.showGrid { drawGrid(&ctx) }
        drawFloors(&ctx)
        drawOccupancy(&ctx)
        drawObjects(&ctx)
        drawWalls(&ctx)
        drawApertures(&ctx)
        if full {
            if overlay.showDimensions { drawWallDimensions(&ctx) }
            drawPhotoPoses(&ctx)
            drawCameras(&ctx)
            drawSubjects(&ctx)
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

    private func drawObjects(_ ctx: inout GraphicsContext) {
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
                ctx.draw(Text(o.category).font(.system(size: 9)).foregroundColor(Theme.textSecondary), at: c)
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

    private func drawWallDimensions(_ ctx: inout GraphicsContext) {
        guard vp.scale > 18 else { return }
        let centroid = plan.interiorCentroid
        for w in plan.walls where w.length > 0.6 {
            let n = inwardNormal(w, centroid: centroid)
            let pos = s(w.midpoint + n * (14 / Double(vp.scale)))
            ctx.draw(Text(UnitsFormatter.distance(w.length))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundColor(Theme.textSecondary), at: pos)
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

    private func drawCameras(_ ctx: inout GraphicsContext) {
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
            ctx.draw(Text("\(cam.label) · \(Optics.formatFocal(cam.rig.focalLength))")
                        .font(.system(size: 11, weight: .bold).width(.condensed))
                        .foregroundColor(color), at: labelPos)
        }
    }

    private func drawSubjects(_ ctx: inout GraphicsContext) {
        for subject in overlay.subjects {
            let c = s(subject.point)
            let r: CGFloat = subject.selected ? 9 : 7
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.danger))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)),
                       with: .color(Theme.danger.opacity(0.5)), lineWidth: 1)
            ctx.draw(Text(subject.label).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.danger),
                     at: CGPoint(x: c.x, y: c.y + r + 10))
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
            let text = Text(m.label).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundColor(.black)
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
        ctx.draw(Text("N").font(.system(size: 10, weight: .heavy)).foregroundColor(.white),
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
        ctx.draw(Text(UnitsFormatter.distance(metres)).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.textSecondary),
                 at: CGPoint(x: origin.x + length / 2, y: origin.y - 10))
    }
}
