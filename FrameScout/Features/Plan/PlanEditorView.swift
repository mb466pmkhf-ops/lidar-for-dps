import SwiftUI

enum PlanSelection: Hashable {
    case camera(UUID)
    case shot(UUID)
}

enum PlanTool: String, CaseIterable, Identifiable {
    case select, camera, aim, subject, measure

    var id: String { rawValue }
    var label: String {
        switch self {
        case .select: return "Select"
        case .camera: return "+ Camera"
        case .aim: return "Aim"
        case .subject: return "Subject"
        case .measure: return "Measure"
        }
    }
    var symbol: String {
        switch self {
        case .select: return "hand.point.up.left"
        case .camera: return "video.badge.plus"
        case .aim: return "scope"
        case .subject: return "figure.stand"
        case .measure: return "ruler"
        }
    }
    var hint: String {
        switch self {
        case .select: return "Tap a camera to select. Drag cameras or subjects to move them. Pinch to zoom."
        case .camera: return "Tap where the camera goes."
        case .aim: return "Tap where the selected camera should point."
        case .subject: return "Tap the actor's mark for the selected shot."
        case .measure: return "Tap two points. Snaps to walls and corners."
        }
    }
}

/// Top-down planning surface for a location: camera positions, shots, subjects, plan measurements.
struct PlanEditorView: View {
    let ref: LocationRef
    var focusShots = false

    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @State private var scanID: UUID?
    @State private var tool: PlanTool = .select
    @State private var selection: PlanSelection?
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var dragTarget: DragTarget?
    @State private var measurePoints: [PlanPoint] = []
    @State private var showRigSheet = false
    @State private var showSaveMeasurement = false
    @State private var measurementKind: MeasurementKind = .wallToWall
    @State private var measurementLabel = ""
    @State private var showDimensions = true

    private enum DragTarget: Equatable {
        case camera(UUID), shot(UUID), subject(UUID), canvas
    }

    private var location: Location? { store.location(ref) }
    private var scan: ScanRecord? {
        guard let location else { return nil }
        if let scanID, let s = location.scans.first(where: { $0.id == scanID }) { return s }
        return location.primaryScan
    }
    private var plan: FloorPlan {
        guard let scan else { return .empty }
        return store.floorPlan(ref, scanID: scan.id) ?? .empty
    }

    var body: some View {
        VStack(spacing: 0) {
            toolBar
            GeometryReader { geo in
                let viewport = currentViewport(size: geo.size)
                ZStack(alignment: .top) {
                    Theme.background
                    FloorPlanCanvas(plan: plan, overlay: overlay, style: .full, viewport: viewport)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(viewport: viewport))
                        .simultaneousGesture(pinchGesture)
                    Text(tool.hint)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                    if plan.isEmpty {
                        noScanNotice.padding(.top, 60)
                    }
                }
                .clipped()
            }
            bottomPanel
        }
        .fsScreen()
        .navigationTitle(location.map { "\($0.name) · Plan" } ?? "Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showRigSheet) { rigSheet }
        .alert("Save measurement", isPresented: $showSaveMeasurement) {
            TextField("Label (e.g. Living room width)", text: $measurementLabel)
            Button("Save") { saveMeasurement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(measureDistance.map { UnitsFormatter.distance($0, precise: true) } ?? "")
        }
        .onAppear { if scanID == nil { scanID = location?.primaryScan?.id } }
    }

    // MARK: Viewport & gestures

    private func currentViewport(size: CGSize) -> PlanViewport {
        var bounds = plan.isEmpty ? PlanRect(minX: -4, minZ: -4, maxX: 4, maxZ: 4) : plan.bounds
        if let location, let extra = PlanRect.enclosing(location.cameraPositions.map(\.rig.position) + location.shots.map(\.rig.position)) {
            bounds = bounds.union(extra)
        }
        let base = PlanViewport.fit(bounds, in: size, padding: 40)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = base.scale * zoom
        let offset = CGPoint(x: centre.x + (base.offset.x - centre.x) * zoom + pan.width,
                             y: centre.y + (base.offset.y - centre.y) * zoom + pan.height)
        return PlanViewport(scale: scale, offset: offset)
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoom = min(12, max(0.3, pinchBase * value)) }
            .onEnded { _ in pinchBase = zoom }
    }

    private func dragGesture(viewport: PlanViewport) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragTarget == nil {
                    dragTarget = hitTest(value.startLocation, viewport: viewport) ?? .canvas
                    panBase = pan
                }
                let world = viewport.toWorld(value.location)
                let moved = hypot(value.translation.width, value.translation.height) > 6
                guard moved else { return }
                switch dragTarget {
                case .camera(let id):
                    store.updateLocation(ref) { loc in
                        if let i = loc.cameraPositions.firstIndex(where: { $0.id == id }) { loc.cameraPositions[i].rig.position = world }
                    }
                case .shot(let id):
                    store.updateLocation(ref) { loc in
                        if let i = loc.shots.firstIndex(where: { $0.id == id }) { loc.shots[i].rig.position = world }
                    }
                case .subject(let id):
                    store.updateLocation(ref) { loc in
                        if let i = loc.shots.firstIndex(where: { $0.id == id }) { loc.shots[i].subject = world }
                    }
                default:
                    pan = CGSize(width: panBase.width + value.translation.width, height: panBase.height + value.translation.height)
                }
            }
            .onEnded { value in
                let wasTap = hypot(value.translation.width, value.translation.height) <= 6
                let target = dragTarget
                dragTarget = nil
                if wasTap { handleTap(at: value.location, viewport: viewport, hit: target) }
            }
    }

    private func hitTest(_ point: CGPoint, viewport: PlanViewport) -> DragTarget? {
        guard let location else { return nil }
        let radius: CGFloat = 26
        func near(_ p: PlanPoint) -> Bool {
            let s = viewport.toScreen(p)
            return hypot(s.x - point.x, s.y - point.y) < radius
        }
        for shot in location.shots {
            if let subject = shot.subject, near(subject) { return .subject(shot.id) }
        }
        for shot in location.shots where near(shot.rig.position) { return .shot(shot.id) }
        for cam in location.cameraPositions where near(cam.rig.position) { return .camera(cam.id) }
        return nil
    }

    private func handleTap(at point: CGPoint, viewport: PlanViewport, hit: DragTarget?) {
        let world = viewport.toWorld(point)
        switch tool {
        case .select:
            switch hit {
            case .camera(let id): selection = .camera(id)
            case .shot(let id), .subject(let id): selection = .shot(id)
            default: selection = nil
            }
        case .camera:
            addCamera(at: world)
            tool = .select
        case .aim:
            aimSelection(at: world)
        case .subject:
            guard case .shot(let id) = selection else { return }
            store.updateLocation(ref) { loc in
                if let i = loc.shots.firstIndex(where: { $0.id == id }) {
                    loc.shots[i].subject = world
                    loc.shots[i].rig.pan = PlanGeometry.bearing(from: loc.shots[i].rig.position, to: world)
                }
            }
        case .measure:
            let tolerance = Double(16 / viewport.scale)
            let snapped = PlanGeometry.snap(world, plan: plan, tolerance: tolerance).point
            if measurePoints.count >= 2 { measurePoints = [] }
            measurePoints.append(snapped)
            if measurePoints.count == 2 {
                measurementLabel = ""
                measurementKind = .wallToWall
            }
        }
    }

    // MARK: Overlay

    private var overlay: PlanOverlay {
        var o = PlanOverlay()
        o.showDimensions = showDimensions
        guard let location else { return o }
        let sid = scan?.id
        for cam in location.cameraPositions where cam.scanID == nil || cam.scanID == sid {
            o.cameras.append(PlanCameraMarker(id: cam.id, label: cam.name, rig: cam.rig,
                                              selected: selection == .camera(cam.id), reach: 4))
        }
        for shot in location.shots where shot.scanID == nil || shot.scanID == sid {
            o.cameras.append(PlanCameraMarker(id: shot.id, label: String(format: "S%02d", shot.number), rig: shot.rig,
                                              isShot: true, selected: selection == .shot(shot.id),
                                              reach: max(1.5, (shot.subjectDistance ?? 4) + 1)))
            if let subject = shot.subject {
                o.subjects.append(PlanSubjectMarker(id: shot.id, label: String(format: "S%02d", shot.number),
                                                    point: subject, selected: selection == .shot(shot.id)))
            }
        }
        for m in location.measurements where m.source == .plan && (m.scanID == nil || m.scanID == sid) {
            if let a = m.planA, let b = m.planB {
                o.measurements.append(PlanMeasureLine(a: a, b: b, label: m.label.isEmpty ? UnitsFormatter.distance(m.value) : "\(m.label) \(UnitsFormatter.distance(m.value))"))
            }
        }
        if measurePoints.count == 2 {
            o.measurements.append(PlanMeasureLine(a: measurePoints[0], b: measurePoints[1],
                                                  label: UnitsFormatter.distance(measurePoints[0].distance(to: measurePoints[1]), precise: true), live: true))
        } else if let first = measurePoints.first {
            o.measurements.append(PlanMeasureLine(a: first, b: first, label: "•", live: true))
        }
        o.photoPoses = location.photos.compactMap(\.pose).filter { $0.scanID == sid }
        if let north = scan?.northOffset {
            o.northWorldBearing = (360 - north).truncatingRemainder(dividingBy: 360)
        }
        return o
    }

    private var measureDistance: Double? {
        measurePoints.count == 2 ? measurePoints[0].distance(to: measurePoints[1]) : nil
    }

    // MARK: Actions

    private func addCamera(at point: PlanPoint) {
        guard let location else { return }
        var rig = location.cameraPositions.last?.rig ?? CameraRig()
        rig.position = point
        rig.pan = PlanGeometry.bearing(from: point, to: plan.isEmpty ? PlanPoint(x: point.x, z: point.z - 1) : plan.interiorCentroid)
        let name = "Camera \(Character(UnicodeScalar(65 + min(25, location.cameraPositions.count))!))"
        let cam = CameraPosition(name: name, rig: rig, scanID: scan?.id)
        store.updateLocation(ref) { $0.cameraPositions.append(cam) }
        selection = .camera(cam.id)
    }

    private func aimSelection(at point: PlanPoint) {
        switch selection {
        case .camera(let id):
            store.updateLocation(ref) { loc in
                if let i = loc.cameraPositions.firstIndex(where: { $0.id == id }) {
                    loc.cameraPositions[i].rig.pan = PlanGeometry.bearing(from: loc.cameraPositions[i].rig.position, to: point)
                }
            }
        case .shot(let id):
            store.updateLocation(ref) { loc in
                if let i = loc.shots.firstIndex(where: { $0.id == id }) {
                    loc.shots[i].rig.pan = PlanGeometry.bearing(from: loc.shots[i].rig.position, to: point)
                }
            }
        case nil:
            break
        }
    }

    private func saveMeasurement() {
        guard measurePoints.count == 2, let d = measureDistance else { return }
        let m = DistanceMeasurement(kind: measurementKind, label: measurementLabel, value: d, horizontal: d,
                                    source: .plan, planA: measurePoints[0], planB: measurePoints[1], scanID: scan?.id)
        store.updateLocation(ref) { $0.measurements.append(m) }
        measurePoints = []
    }

    private func createShot(from camera: CameraPosition) {
        guard let location else { return }
        let shot = Shot(number: location.nextShotNumber, rig: camera.rig, cameraPositionID: camera.id, scanID: camera.scanID)
        store.updateLocation(ref) { $0.shots.append(shot) }
        selection = .shot(shot.id)
    }

    // MARK: Chrome

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlanTool.allCases) { t in
                    Button { tool = t; if t != .measure { measurePoints = [] } } label: {
                        Label(t.label, systemImage: t.symbol)
                            .font(.system(size: 14, weight: .bold).width(.condensed))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .foregroundStyle(tool == t ? Color.black : Theme.textPrimary)
                            .background(tool == t ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled((t == .aim && selection == nil) || (t == .subject && !isShotSelected))
                    .opacity(((t == .aim && selection == nil) || (t == .subject && !isShotSelected)) ? 0.4 : 1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
    }

    private var isShotSelected: Bool {
        if case .shot = selection { return true }
        return false
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let location, location.scans.count > 1 {
                    Picker("Scan", selection: Binding(get: { scan?.id }, set: { scanID = $0 })) {
                        ForEach(location.scans) { s in Text(s.name).tag(Optional(s.id)) }
                    }
                }
                Toggle("Wall dimensions", isOn: $showDimensions)
                Button { zoom = 1; pinchBase = 1; pan = .zero } label: { Label("Fit to screen", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                if location?.primaryScan != nil {
                    Button { router.start(.virtualCamera(ref, cameraID: nil)) } label: { Label("3D walkthrough", systemImage: "cube") }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if tool == .measure {
            measurePanel
        } else if let selection, let location {
            switch selection {
            case .camera(let id):
                if let cam = location.cameraPositions.first(where: { $0.id == id }) {
                    selectionPanel(title: cam.name, rig: cam.rig, subjectDistance: nil,
                                   onRig: { newRig in updateCamera(id) { $0.rig = newRig } },
                                   extra: AnyView(HStack {
                                       Button { createShot(from: cam) } label: { Label("Make Shot", systemImage: "film") }
                                       Spacer()
                                       Button(role: .destructive) {
                                           store.updateLocation(ref) { $0.cameraPositions.removeAll { $0.id == id } }
                                           self.selection = nil
                                       } label: { Label("Delete", systemImage: "trash") }
                                   }))
                }
            case .shot(let id):
                if let shot = location.shots.first(where: { $0.id == id }) {
                    selectionPanel(title: "\(shot.code) \(shot.title)", rig: shot.rig, subjectDistance: shot.subjectDistance,
                                   onRig: { newRig in updateShot(id) { $0.rig = newRig } },
                                   extra: AnyView(HStack {
                                       Button { tool = .subject } label: { Label(shot.subject == nil ? "Set subject" : "Move subject", systemImage: "figure.stand") }
                                       Spacer()
                                       Button(role: .destructive) {
                                           store.updateLocation(ref) { $0.shots.removeAll { $0.id == id } }
                                           self.selection = nil
                                       } label: { Label("Delete", systemImage: "trash") }
                                   }))
                }
            }
        } else {
            HStack(spacing: 16) {
                StatView(label: "Cameras", value: "\(location?.cameraPositions.count ?? 0)")
                StatView(label: "Shots", value: "\(location?.shots.count ?? 0)")
                StatView(label: "Room", value: UnitsFormatter.dimensions(scan?.stats.width, scan?.stats.length))
            }
            .padding()
            .background(Theme.surface)
        }
    }

    private var measurePanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("PLAN MEASURE").font(.fsLabel).foregroundStyle(Theme.textSecondary)
                Text(measureDistance.map { UnitsFormatter.distance($0, precise: true) } ?? (measurePoints.isEmpty ? "Tap first point" : "Tap second point"))
                    .font(.fsValue)
            }
            Spacer()
            if measureDistance != nil {
                Menu {
                    ForEach(MeasurementKind.allCases) { k in
                        Button(k.label) { measurementKind = k }
                    }
                } label: {
                    Label(measurementKind.label, systemImage: measurementKind.symbol).font(.caption)
                }
                Button("Save") { showSaveMeasurement = true }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
            }
        }
        .padding()
        .background(Theme.surface)
    }

    private func selectionPanel(title: String, rig: CameraRig, subjectDistance: Double?,
                                onRig: @escaping (CameraRig) -> Void, extra: AnyView) -> some View {
        let rigBinding = Binding<CameraRig>(get: { rig }, set: onRig)
        let clear = PlanGeometry.clearances(for: rig, plan: plan)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(rig.lensSummary).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            LensPicker(focalLength: rigBinding.focalLength)
            HStack {
                StatView(label: "H-FOV", value: Optics.formatAngle(rig.horizontalFOV))
                StatView(label: "Height", value: UnitsFormatter.distance(rig.height))
                StatView(label: "Behind", value: UnitsFormatter.distance(clear.behind), highlight: (clear.behind ?? 99) < 1.2)
                if let subjectDistance {
                    StatView(label: "Subject", value: UnitsFormatter.distance(subjectDistance))
                } else {
                    StatView(label: "Front", value: UnitsFormatter.distance(clear.front))
                }
            }
            HStack {
                Button { showRigSheet = true } label: { Label("Details", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.bordered)
                if location?.primaryScan != nil, case .camera(let id)? = selection {
                    Button { router.start(.virtualCamera(ref, cameraID: id)) } label: { Label("Frame in 3D", systemImage: "camera.metering.center.weighted") }
                        .buttonStyle(.bordered)
                } else if location?.primaryScan != nil, case .shot(let id)? = selection {
                    Button { router.start(.virtualCamera(ref, cameraID: id)) } label: { Label("Frame in 3D", systemImage: "camera.metering.center.weighted") }
                        .buttonStyle(.bordered)
                }
            }
            extra
        }
        .padding()
        .background(Theme.surface)
    }

    @ViewBuilder
    private var rigSheet: some View {
        NavigationStack {
            Form {
                switch selection {
                case .camera(let id):
                    if let cam = location?.cameraPositions.first(where: { $0.id == id }) {
                        Section("Camera") {
                            TextField("Name", text: Binding(get: { cam.name }, set: { v in updateCamera(id) { $0.name = v } }))
                            TextField("Notes", text: Binding(get: { cam.notes }, set: { v in updateCamera(id) { $0.notes = v } }), axis: .vertical)
                        }
                        CameraRigForm(rig: Binding(get: { cam.rig }, set: { v in updateCamera(id) { $0.rig = v } }),
                                      clearances: PlanGeometry.clearances(for: cam.rig, plan: plan),
                                      ceilingHeight: scan?.stats.ceilingHeight)
                    }
                case .shot(let id):
                    if let shot = location?.shots.first(where: { $0.id == id }) {
                        ShotFields(shot: shot, ref: ref, update: { mutate in updateShot(id, mutate) })
                        CameraRigForm(rig: Binding(get: { shot.rig }, set: { v in updateShot(id) { $0.rig = v } }),
                                      subjectDistance: shot.subjectDistance,
                                      clearances: PlanGeometry.clearances(for: shot.rig, plan: plan),
                                      ceilingHeight: scan?.stats.ceilingHeight)
                    }
                case nil:
                    EmptyView()
                }
            }
            .fsScreen()
            .navigationTitle("Camera Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRigSheet = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func updateCamera(_ id: UUID, _ mutate: @escaping (inout CameraPosition) -> Void) {
        store.updateLocation(ref) { loc in
            if let i = loc.cameraPositions.firstIndex(where: { $0.id == id }) { mutate(&loc.cameraPositions[i]) }
        }
    }

    private func updateShot(_ id: UUID, _ mutate: @escaping (inout Shot) -> Void) {
        store.updateLocation(ref) { loc in
            if let i = loc.shots.firstIndex(where: { $0.id == id }) { mutate(&loc.shots[i]) }
        }
    }

    private var noScanNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.dashed").font(.title)
            Text("No scan for this location").font(.headline)
            Text("You can still place cameras on the grid (1 m squares).\(DeviceCapabilities.hasLiDAR ? " Scan the location to plan against real walls." : "")")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}
