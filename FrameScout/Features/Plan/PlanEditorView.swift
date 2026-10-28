import SwiftUI

enum PlanSelection: Hashable {
    case camera(UUID)
    case shot(UUID)
    case light(UUID)
}

enum PlanTool: String, CaseIterable, Identifiable {
    case select, camera, light, aim, subject, measure

    var id: String { rawValue }
    var label: String {
        switch self {
        case .select: return "Select"
        case .camera: return "+ Camera"
        case .light: return "+ Light"
        case .aim: return "Aim"
        case .subject: return "Subject"
        case .measure: return "Measure"
        }
    }
    var symbol: String {
        switch self {
        case .select: return "hand.point.up.left"
        case .camera: return "video.badge.plus"
        case .light: return "lightbulb"
        case .aim: return "scope"
        case .subject: return "figure.stand"
        case .measure: return "ruler"
        }
    }
    var hint: String {
        switch self {
        case .select: return "Tap a camera or light to select. Drag to move. Pinch to zoom."
        case .camera: return "Tap where the camera goes."
        case .light: return "Tap where the unit goes. It points at the nearest subject or the room centre."
        case .aim: return "Tap where the selected camera or light should point."
        case .subject: return "Tap the actor's mark for the selected shot."
        case .measure: return "Tap two points. Snaps to walls and corners."
        }
    }
}

/// Top-down planning surface for a location: camera positions, shots, subjects, lighting units and
/// plan measurements. With the 3D view on, the scan is shown above the plan and both show the
/// same cameras and lights, so a change in one appears in the other.
struct PlanEditorView: View {
    let ref: LocationRef
    var focusShots = false
    /// Opened as the lighting diagram: lights and the 3D view first.
    var lightingMode = false

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
    @State private var showCameras = true
    @State private var showLights = true
    @State private var show3D = false
    @State private var newLightKind: LightKind = .fresnel
    @State private var sharedDiagram: SharedFile?
    @StateObject private var scene3D = VirtualSceneModel()
    @State private var scene3DLoaded = false
    /// Bounds the view is fitted to. Frozen once shown so dragging a camera past the plan edge
    /// doesn't refit (and shift) the whole plan under the user's finger.
    @State private var fittedBounds: PlanRect?

    private enum DragTarget: Equatable {
        case camera(UUID), shot(UUID), subject(UUID), light(UUID), canvas
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
            if show3D, scan != nil {
                scenePreview
            }
            GeometryReader { geo in
                let viewport = currentViewport(size: geo.size)
                ZStack(alignment: .top) {
                    Theme.background
                    FloorPlanCanvas(plan: plan, overlay: overlay, style: .full, viewport: viewport)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(viewport: viewport))
                        .simultaneousGesture(pinchGesture)
                    Text(tool.hint)
                        .font(.fsCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(8)
                        .background(Color.black.opacity(0.6), in: Rectangle())
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
        .toolbar {
            // "Plan" stays readable; the location name goes underneath and shortens instead.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Plan").font(.fsHeadline)
                    if let location {
                        Text(location.name).font(.fsMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            toolbarContent
        }
        .sheet(isPresented: $showRigSheet) { rigSheet }
        .alert("Save measurement", isPresented: $showSaveMeasurement) {
            TextField("Label (e.g. Living room width)", text: $measurementLabel)
            Button("Save") { saveMeasurement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(measureDistance.map { UnitsFormatter.distance($0, precise: true) } ?? "")
        }
        .sheet(item: $sharedDiagram) { file in ShareSheet(items: [file.url]) }
        .onAppear {
            if scanID == nil { scanID = location?.primaryScan?.id }
            if fittedBounds == nil { fittedBounds = contentBounds() }
            if lightingMode {
                if location?.primaryScan != nil { show3D = true }
                if location?.lightFixtures.isEmpty ?? true { tool = .light }
            }
        }
        .onChange(of: scanID) { _, _ in fittedBounds = contentBounds(); scene3DLoaded = false; if show3D { load3D() } }
        .onChange(of: show3D) { _, on in if on { load3D() } }
        .onChange(of: location) { _, _ in sync3D() }
        .onChange(of: selection) { _, _ in sync3D() }
    }

    // MARK: 3D view (same data as the plan)

    private var scenePreview: some View {
        SceneKitContainer(model: scene3D, orbit: true)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .overlay {
                if !scene3D.loaded {
                    if let error = scene3D.error {
                        Text(error).font(.fsCaption).foregroundStyle(Theme.textSecondary).padding()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                Text("3D · drag to orbit, pinch to zoom")
                    .font(.fsMicro).tracking(Theme.tracking)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(6)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func load3D() {
        guard !scene3DLoaded, let scan else { return }
        scene3DLoaded = true
        scene3D.load(scan: scan, ref: ref, floorY: plan.floorY)
        sync3D()
    }

    /// Pushes cameras, subjects and lights to the 3D view; cheap enough to run on every edit.
    private func sync3D() {
        guard show3D, let location else { return }
        let sid = scan?.id
        var viewpoints: [VirtualViewpoint] = []
        if showCameras {
            viewpoints += location.cameraPositions.filter { $0.scanID == nil || $0.scanID == sid }.map {
                VirtualViewpoint(id: $0.id, kind: .camera, label: $0.name, rig: $0.rig, subject: nil, subjectHeight: 1.75)
            }
            viewpoints += location.shots.filter { $0.scanID == nil || $0.scanID == sid }.map {
                VirtualViewpoint(id: $0.id, kind: .shot, label: $0.code, rig: $0.rig, subject: $0.subject, subjectHeight: $0.subjectHeight)
            }
        }
        scene3D.setMarkers(viewpoints: viewpoints, selected: nil)
        let lights = showLights ? location.lightFixtures.filter { $0.scanID == nil || $0.scanID == sid } : []
        var selectedLight: UUID?
        if case .light(let id)? = selection { selectedLight = id }
        scene3D.setLights(lights, selected: selectedLight)
    }

    // MARK: Viewport & gestures

    private func contentBounds() -> PlanRect {
        var bounds = plan.isEmpty ? PlanRect(minX: -4, minZ: -4, maxX: 4, maxZ: 4) : plan.bounds
        if let location, let extra = PlanRect.enclosing(location.cameraPositions.map(\.rig.position) + location.shots.map(\.rig.position)
                                                         + location.lightFixtures.map(\.position)) {
            bounds = bounds.union(extra)
        }
        return bounds
    }

    private func currentViewport(size: CGSize) -> PlanViewport {
        let base = PlanViewport.fit(fittedBounds ?? contentBounds(), in: size, padding: 40)
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
                case .light(let id):
                    updateLight(id) { $0.position = world }
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
        if showCameras {
            for shot in location.shots {
                if let subject = shot.subject, near(subject) { return .subject(shot.id) }
            }
            for shot in location.shots where near(shot.rig.position) { return .shot(shot.id) }
            for cam in location.cameraPositions where near(cam.rig.position) { return .camera(cam.id) }
        }
        if showLights {
            for light in location.lightFixtures where near(light.position) { return .light(light.id) }
        }
        return nil
    }

    private func handleTap(at point: CGPoint, viewport: PlanViewport, hit: DragTarget?) {
        let world = viewport.toWorld(point)
        switch tool {
        case .select:
            switch hit {
            case .camera(let id): selection = .camera(id)
            case .shot(let id), .subject(let id): selection = .shot(id)
            case .light(let id): selection = .light(id)
            default: selection = nil
            }
        case .camera:
            addCamera(at: world)
            tool = .select
        case .light:
            if case .light(let id)? = hit {
                selection = .light(id)
            } else {
                addLight(at: world)
            }
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
        if showLights {
            for light in location.lightFixtures where light.scanID == nil || light.scanID == sid {
                o.lights.append(PlanLightMarker(light: light, selected: selection == .light(light.id)))
            }
        }
        guard showCameras else { return o }
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
        case .light(let id):
            updateLight(id) { light in
                light.pan = PlanGeometry.bearing(from: light.position, to: point)
            }
        case nil:
            break
        }
    }

    private func addLight(at point: PlanPoint) {
        guard let location else { return }
        // Point it at the nearest subject, else the middle of the room.
        let subjects = location.shots.compactMap(\.subject)
        let aim = subjects.min { $0.distance(to: point) < $1.distance(to: point) }
            ?? (plan.isEmpty ? PlanPoint(x: point.x, z: point.z - 1) : plan.interiorCentroid)
        let emitting = location.lightFixtures.filter { $0.kind.emits }.count
        let name = newLightKind.emits ? "L\(emitting + 1)" : newLightKind.label
        var light = LightFixture(name: name, kind: newLightKind, position: point,
                                 pan: PlanGeometry.bearing(from: point, to: aim), scanID: scan?.id)
        // Start from the last unit of the same kind so a row of lights is quick to place.
        if let last = location.lightFixtures.last(where: { $0.kind == newLightKind }) {
            light.power = last.power
            light.colorTemperature = last.colorTemperature
            light.height = last.height
            light.beamAngle = last.beamAngle
            light.width = last.width
            light.modifier = last.modifier
        }
        store.updateLocation(ref) { $0.lightFixtures.append(light) }
        selection = .light(light.id)
    }

    private func updateLight(_ id: UUID, _ mutate: @escaping (inout LightFixture) -> Void) {
        store.updateLocation(ref) { loc in
            var lights = loc.lightFixtures
            if let i = lights.firstIndex(where: { $0.id == id }) {
                mutate(&lights[i])
                loc.lightFixtures = lights
            }
        }
    }

    /// Renders the plan with cameras and lights as a PNG for sharing.
    @MainActor
    private func shareDiagram() {
        let canvas = FloorPlanCanvas(plan: plan, overlay: overlay, style: .full)
            .frame(width: 1200, height: 1200)
            .background(Theme.background)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else { return }
        let name = (location?.name ?? "Location").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) – lighting diagram.png")
        do {
            try png.write(to: url)
            sharedDiagram = SharedFile(url: url)
        } catch {}
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
                            .font(.fsLabel).tracking(Theme.tracking)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .foregroundStyle(tool == t ? Color.black : Theme.textPrimary)
                            .background(tool == t ? Theme.accent : Theme.surfaceRaised, in: Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled((t == .aim && selection == nil) || (t == .subject && !isShotSelected))
                    .opacity(((t == .aim && selection == nil) || (t == .subject && !isShotSelected)) ? 0.4 : 1)
                    .accessibilityAddTraits(tool == t ? .isSelected : [])
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

    private var isLightSelected: Bool {
        if case .light = selection { return true }
        return false
    }

    /// Choose what the next tap places.
    private var newLightPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT UNIT").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(LightKind.allCases) { kind in
                        TagChip(text: kind.label, selected: newLightKind == kind) { newLightKind = kind }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
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
                Toggle("Cameras and shots", isOn: $showCameras)
                Toggle("Lights", isOn: $showLights)
                if location?.primaryScan != nil {
                    Toggle("3D view above plan", isOn: $show3D)
                }
                Button { shareDiagram() } label: { Label("Share diagram (PNG)", systemImage: "square.and.arrow.up") }
                Button { zoom = 1; pinchBase = 1; pan = .zero; panBase = .zero; fittedBounds = contentBounds() } label: { Label("Fit to screen", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
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
        } else if tool == .light, selection == nil || !isLightSelected {
            newLightPanel
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
            case .light(let id):
                if let light = location.lightFixtures.first(where: { $0.id == id }) {
                    LightPanel(light: light, update: { mutate in updateLight(id, mutate) },
                               onDetails: { showRigSheet = true },
                               onDuplicate: {
                                   var copy = light
                                   copy.id = UUID()
                                   copy.name = light.name + "′"
                                   copy.position = light.position + PlanPoint(x: 0.5, z: 0.5)
                                   store.updateLocation(ref) { $0.lightFixtures.append(copy) }
                                   self.selection = .light(copy.id)
                               },
                               onDelete: {
                                   store.updateLocation(ref) { $0.lightFixtures.removeAll { $0.id == id } }
                                   self.selection = nil
                               })
                }
            }
        } else {
            HStack(spacing: 16) {
                StatView(label: "Cameras", value: "\(location?.cameraPositions.count ?? 0)")
                StatView(label: "Shots", value: "\(location?.shots.count ?? 0)")
                StatView(label: "Lights", value: "\(location?.lightFixtures.count ?? 0)")
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
                    Label(measurementKind.label, systemImage: measurementKind.symbol).font(.fsCaption)
                }
                Button("Save") { showSaveMeasurement = true }
                    .buttonStyle(HairlineButtonStyle(prominent: true))
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
                Text(title).font(.fsHeadline)
                Spacer()
                Text(rig.lensSummary).font(.fsCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
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
                    .buttonStyle(HairlineButtonStyle())
                if location?.primaryScan != nil, case .camera(let id)? = selection {
                    Button { router.start(.virtualCamera(ref, cameraID: id)) } label: { Label("Frame in 3D", systemImage: "camera.metering.center.weighted") }
                        .buttonStyle(HairlineButtonStyle())
                } else if location?.primaryScan != nil, case .shot(let id)? = selection {
                    Button { router.start(.virtualCamera(ref, cameraID: id)) } label: { Label("Frame in 3D", systemImage: "camera.metering.center.weighted") }
                        .buttonStyle(HairlineButtonStyle())
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
                case .light(let id):
                    if let light = location?.lightFixtures.first(where: { $0.id == id }) {
                        LightForm(light: Binding(get: { light }, set: { v in updateLight(id) { $0 = v } }))
                    }
                case nil:
                    EmptyView()
                }
            }
            .fsScreen()
            .navigationTitle(isLightSelected ? "Light" : "Camera Setup")
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
            Image(systemName: "square.dashed").font(.system(size: 26, weight: .ultraLight))
            Text("No scan for this location").font(.fsHeadline)
            Text("You can still place cameras on the grid (1 m squares).\(DeviceCapabilities.hasLiDAR ? " Scan the location to plan against real walls." : "")")
                .font(.fsCaption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .background(Color.black.opacity(0.6), in: Rectangle())
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}
