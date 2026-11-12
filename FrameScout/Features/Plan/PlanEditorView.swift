import SwiftUI

enum PlanSelection: Hashable {
    case camera(UUID)
    case shot(UUID)
    case light(UUID)
    case character(UUID)
    case meter(UUID)
    /// A set piece: from the scan, or placed by hand. Moves on the plan once selected.
    case object(UUID)
    /// A door, window or opening in a wall. Slides along the walls on the plan once selected.
    case opening(UUID)

    /// Can be dragged in the 3D view and aimed. Set pieces and openings move on the plan only.
    var isMovable: Bool {
        switch self {
        case .object, .opening: return false
        default: return true
        }
    }
}

/// Which "My presets" sheet is open.
enum PresetSheet: Identifiable, Hashable {
    case save(UUID)
    case manage
    var id: String {
        switch self {
        case .save(let id): return "save-\(id)"
        case .manage: return "manage"
        }
    }
}

enum PlanTool: String, CaseIterable, Identifiable {
    case select, add, aim, subject, measure

    /// Subject is reached from a shot's panel, not the tool row.
    static let toolRow: [PlanTool] = [.select, .add, .aim, .measure]

    var id: String { rawValue }
    var label: String {
        switch self {
        case .select: return "Select"
        case .add: return "Add"
        case .aim: return "Aim"
        case .subject: return "Subject"
        case .measure: return "Measure"
        }
    }
    var symbol: String {
        switch self {
        case .select: return "hand.point.up.left"
        case .add: return "plus.circle"
        case .aim: return "scope"
        case .subject: return "figure.stand"
        case .measure: return "ruler"
        }
    }
    var hint: String {
        switch self {
        case .select: return "Tap to select. Drag to move. Pinch to zoom."
        case .add: return "Tap where it goes."
        case .aim: return "Tap where the selected item should point or face."
        case .subject: return "Tap the actor's mark for the selected shot."
        case .measure: return "Tap two points. Snaps to walls and corners."
        }
    }
    var hint3D: String {
        switch self {
        case .select: return "Drag to look round · two fingers to slide · double-tap to centre · hold an item to move it"
        case .add: return "Tap the floor where it goes"
        case .aim: return "Tap where the selected item should point"
        case .subject: return "Tap the actor's mark on the floor"
        case .measure: return "Measure on the plan"
        }
    }
}

/// Extra information on the 2D plan, added on top of the essentials (room, units, people, cameras).
/// The selected item always shows its own beam or view. Stored per device.
enum PlanInfoLayer: String, CaseIterable, Identifiable {
    case beams, views, readings, dimensions, names

    var id: String { rawValue }
    var label: String {
        switch self {
        case .beams: return "Beams"
        case .views: return "Camera views"
        case .readings: return "Readings"
        case .dimensions: return "Dimensions"
        case .names: return "Set-piece names"
        }
    }
}

/// Plan only, plan with the 3D view above it, or the 3D view on its own.
enum PlanLayout: String, CaseIterable, Identifiable {
    case plan, split, scene
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plan: return "Plan"
        case .split: return "Split"
        case .scene: return "3D"
        }
    }
    var symbol: String {
        switch self {
        case .plan: return "square.grid.3x3"
        case .split: return "rectangle.split.1x2"
        case .scene: return "cube"
        }
    }
}

/// What the Add tool places next.
enum PlanAddItem: Hashable {
    case camera
    case light(String)
    case grip(LightKind)
    case person(CharacterType)
    case meter
    /// A door, window or opening (`SetPieces.openings` id), placed in the nearest wall.
    case opening(String)
    /// Furniture (`SetPieces.furniture` id).
    case furniture(String)

    var label: String {
        switch self {
        case .camera: return "Camera"
        case .light: return "Light"
        case .grip: return "Grip"
        case .person: return "Person"
        case .meter: return "Meter"
        case .opening: return "Door · window"
        case .furniture: return "Furniture"
        }
    }
    var symbol: String {
        switch self {
        case .camera: return "video"
        case .light: return "lightbulb"
        case .grip: return "rectangle.portrait"
        case .person: return "figure.stand"
        case .meter: return "gauge.with.dots.needle.50percent"
        case .opening: return "door.left.hand.open"
        case .furniture: return "sofa"
        }
    }
}

/// Lighting worked out once per update and shared by the plan, the 3D view and the panels.
private struct LightingAnalysis {
    var context = LightingContext()
    var readings: [MeterPoint.Source: LightingCalculator.Reading] = [:]
    var scene = LightingCalculator.Scene(lights: [])

    func reading(_ s: MeterPoint.Source) -> LightingCalculator.Reading? { readings[s] }
}

/// One undo step: the location and the scan's 2D plan (doors, windows, set pieces) as they were.
struct EditSnapshot {
    var location: Location
    var plan: FloorPlan?
}

/// Undo history for the editor: whole-location snapshots. Edits within a moment of each other
/// (a drag, a slider) collapse into one step.
@MainActor
final class EditHistory: ObservableObject {
    @Published private(set) var undoStack: [EditSnapshot] = []
    @Published private(set) var redoStack: [EditSnapshot] = []
    private var lastEdit = Date.distantPast
    private let limit = 60

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call with the location and plan as they are before an edit.
    func willEdit(_ current: EditSnapshot) {
        let now = Date()
        if now.timeIntervalSince(lastEdit) > 0.8 {
            undoStack.append(current)
            if undoStack.count > limit { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastEdit = now
    }

    func undo(from current: EditSnapshot) -> EditSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        lastEdit = .distantPast
        return previous
    }

    func redo(from current: EditSnapshot) -> EditSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        lastEdit = .distantPast
        return next
    }
}

/// Top-down planning surface for a location: cameras, shots, lighting units, people and meters,
/// with the 3D view beside it. Both show the same data, so a change in one appears in the other.
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
    @State private var layout: PlanLayout = .plan
    @State private var addItem: PlanAddItem = .light("cob-600-d")
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var dragTarget: DragTarget?
    @State private var measurePoints: [PlanPoint] = []
    @State private var showRigSheet = false
    @State private var showSaveMeasurement = false
    @State private var showLayers = false
    @State private var showStage = false
    @State private var showExposure = false
    @State private var showAlignment = false
    @State private var showFixturePicker = false
    /// "My presets": saving the lights round this person, or editing the saved ones.
    @State private var presetSheet: PresetSheet?
    @ObservedObject private var presetLibrary = LightingPresetLibrary.shared
    @State private var measurementKind: MeasurementKind = .wallToWall
    @State private var measurementLabel = ""
    @State private var sharedDiagram: SharedFile?
    @StateObject private var scene3D = VirtualSceneModel()
    @StateObject private var history = EditHistory()
    /// Short result of the last one-tap action (e.g. a lighting setup), shown above the panel.
    @State private var notice: String?
    @State private var scene3DLoaded = false
    /// Bounds the view is fitted to. Frozen once shown so dragging a camera past the plan edge
    /// doesn't refit (and shift) the whole plan under the user's finger.
    @State private var fittedBounds: PlanRect?
    /// Information layers switched on above the essentials ("beams,readings"…).
    @AppStorage("plan.infoLayers") private var infoLayersRaw = ""
    @AppStorage(ReadingExtra.key) private var readingExtra = ReadingExtra.off
    @State private var showInfoBar = false

    private enum DragTarget: Equatable {
        case item(PlanSelection), subject(UUID), canvas
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
    private var display: SceneDisplay { location?.displaySettings ?? SceneDisplay() }
    private var exposure: ExposureSettings { location?.exposureSettings ?? ExposureSettings() }
    /// Camera settings for this location: every camera here shares them, and every reading follows them.
    private var exposureBinding: Binding<ExposureSettings> {
        Binding(get: { exposure }, set: { v in edit { $0.exposureSettings = v } })
    }

    private var shows3D: Bool { layout != .plan && scan != nil }
    private var showsPlan: Bool { layout != .scene || scan == nil || scene3D.error != nil }

    private func inScan(_ id: UUID?) -> Bool { id == nil || id == scan?.id }

    var body: some View {
        let analysis = makeAnalysis()
        VStack(spacing: 0) {
            toolBar
            if shows3D {
                if let error = scene3D.error {
                    // Don't give up a third of the screen to a view that can't load.
                    Label(error, systemImage: "cube.transparent")
                        .font(.fsCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                } else if layout == .split {
                    scenePreview.frame(height: 260)
                } else {
                    scenePreview.frame(maxHeight: .infinity)
                }
            }
            if showsPlan {
                planArea(analysis)
            }
            if let notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.textSecondary)
                    Text(notice).font(.fsCaption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { self.notice = nil } label: { Image(systemName: "xmark").font(.fsCaption) }
                        .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Theme.surfaceRaised)
            }
            bottomPanel(analysis)
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
        .sheet(isPresented: $showLayers) {
            LayersSheet(plan: plan, display: displayBinding, hasScan3D: scan != nil,
                        onAlign: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openAlignment() } })
        }
        .sheet(isPresented: $showStage) {
            if let location {
                StageSheet(location: Binding(get: { self.location ?? location }, set: { v in edit { $0.studio = v.studio; $0.daylight = v.daylight } }),
                           plan: plan.isEmpty ? nil : plan, scan: scan)
            }
        }
        .sheet(isPresented: $showExposure) {
            ExposureSheet(exposure: Binding(get: { exposure }, set: { v in edit { $0.exposureSettings = v } }))
        }
        .sheet(isPresented: $showAlignment) {
            AlignmentSheet(model: scene3D, alignment: Binding(get: { scan?.alignmentValue ?? .identity }, set: { setAlignment($0) }))
        }
        .sheet(isPresented: $showFixturePicker) {
            NavigationStack {
                FixturePicker(selectedID: currentAddProfileID) { p in addItem = .light(p.id) }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Save measurement", isPresented: $showSaveMeasurement) {
            TextField("Label (e.g. Living room width)", text: $measurementLabel)
            Button("Save") { saveMeasurement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(measureDistance.map { UnitsFormatter.distance($0, precise: true) } ?? "")
        }
        .sheet(item: $sharedDiagram) { file in ShareSheet(items: [file.url]) }
        .sheet(item: $presetSheet) { sheet in presetSheetView(sheet) }
        .onAppear {
            if scanID == nil { scanID = location?.primaryScan?.id }
            if fittedBounds == nil { fittedBounds = contentBounds() }
            if lightingMode {
                if location?.primaryScan != nil { layout = .split }
                if location?.lightFixtures.isEmpty ?? true { tool = .add }
            }
            #if DEBUG
            if DemoContent.isEnabled {
                switch DemoContent.screen {
                case .previs:
                    layout = .scene
                    selection = location?.previsCharacters.first.map { PlanSelection.character($0.id) }
                case .lightpanel:
                    selection = location?.lightFixtures.first.map { PlanSelection.light($0.id) }
                default: break
                }
            }
            #endif
            if shows3D { load3D() }
        }
        .onChange(of: scanID) { _, _ in
            fittedBounds = contentBounds()
            scene3DLoaded = false
            if shows3D { load3D() }
        }
        .onChange(of: layout) { _, _ in if shows3D { load3D() } }
        .onChange(of: location) { _, _ in sync3D() }
        .onChange(of: selection) { _, _ in sync3D() }
        .onChange(of: scene3D.loaded) { _, _ in scene3D.showPlanEdits(plan); sync3D() }
        .onChange(of: plan) { _, newPlan in
            scene3D.showPlanEdits(newPlan)
            sync3D()
        }
    }

    // MARK: Lighting

    private var sceneLights: [LightFixture] {
        (location?.lightFixtures ?? []).filter { inScan($0.scanID) }
    }

    /// Readings at every meter and face, from the photometric model (never from viewport brightness).
    /// Hidden units still count: hiding changes the view, switching off changes the light.
    private func makeAnalysis() -> LightingAnalysis {
        guard let location else { return LightingAnalysis() }
        let lights = sceneLights
        let calcPlan: FloorPlan? = plan.isEmpty ? nil : plan
        let wt = location.displaySettings.windowTransmissionValue
        // Sun, sky and an LED wall, when the location has them (see `Stage`).
        let env = location.environment(plan: calcPlan, scan: scan)
        let scene = LightingCalculator.Scene(lights: lights, plan: calcPlan, windowTransmission: wt, environment: env)
        let meters = location.meterPoints(scanID: scan?.id)
        var readings: [MeterPoint.Source: LightingCalculator.Reading] = [:]
        for m in meters {
            readings[m.source] = LightingCalculator.reading(at: m.point, normal: m.normal, scene: scene)
        }
        let context = LightingContext(
            exposure: location.exposureSettings,
            meters: meters,
            reading: { m in readings[m.source] ?? LightingCalculator.reading(at: m.point, normal: m.normal, scene: scene) },
            solve: { light, m, lux in
                LightingCalculator.solveOutput(for: light, target: lux, at: m.point, normal: m.normal,
                                               allLights: lights, plan: calcPlan, windowTransmission: wt, environment: env)
            })
        return LightingAnalysis(context: context, readings: readings, scene: scene)
    }

    /// One line under the exposure summary saying what the readings mean.
    private var keyLine: String {
        let key = "key ≈ \(ReadingExtra.luxText(exposure.keyLux))"
        return readingExtra == .off ? "Readings are the stop a light meter would show" : "Stop a meter would show, then light level · \(key)"
    }

    private func readingText(_ r: LightingCalculator.Reading?) -> String? {
        guard let r, !sceneLights.isEmpty else { return nil }
        return ReadingFormat.value(lux: r.lux, exposure: exposure, extra: readingExtra)
    }

    /// False-colour map of stops against key at face height (1.5 m), metered towards camera.
    private func luxMap(_ analysis: LightingAnalysis) -> PlanLuxMap? {
        guard display.luxMapOn, let location, !sceneLights.isEmpty else { return nil }
        let bounds = plan.isEmpty ? contentBounds() : plan.bounds
        let cell = max(0.2, max(bounds.width, bounds.depth) / 36)
        let columns = max(4, Int((bounds.width / cell).rounded(.up)))
        let rows = max(4, Int((bounds.depth / cell).rounded(.up)))
        let cams = location.meterCameras
        let key = exposure.keyLux
        let values = LightingCalculator.grid(bounds: bounds, columns: columns, rows: rows, height: 1.5, scene: analysis.scene) { p in
            cams.isEmpty ? LightingCalculator.Point(x: 0, y: 1, z: 0) : MeterGeometry.normal(for: .camera, bearing: 0, at: p, cameras: cams)
        }
        return PlanLuxMap(bounds: bounds, columns: columns, rows: rows, stops: values.map { $0 > 0 ? log2($0 / key) : -10 })
    }

    // MARK: 3D view (same data as the plan)

    private var scenePreview: some View {
        SceneKitContainer(model: scene3D, orbit: true,
                          onSelect: { selection = $0 },
                          onMove: { item, p in move(item, to: p) },
                          onRotate: { item, deg in rotate(item, by: deg) },
                          dragHeight: { item in position(of: item)?.height ?? 0 },
                          onTap: { item, p in handle3DTap(item, p) })
            .frame(maxWidth: .infinity)
            .overlay {
                if !scene3D.loaded && scene3D.error == nil {
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.hint3D)
                        .font(.fsMicro).tracking(Theme.tracking)
                        .foregroundStyle(.white.opacity(0.8))
                    if scene3D.builtFromPlan {
                        Text("BUILT FROM THE PLAN").font(.fsMicro).tracking(Theme.tracking).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(8)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    viewButton("arrow.counterclockwise", "Reset view") { scene3D.resetView() }
                    viewButton("square.dashed", "View from above") { scene3D.topView() }
                    viewButton("figure.stand", "Eye level") { scene3D.eyeLevelView() }

                    if let selection, let p = position(of: selection) {
                        viewButton("scope", "Focus on selection") { scene3D.focus(on: p.point, height: p.height) }
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 6) {
                    viewButton("minus", "Zoom out") { scene3D.zoomBy(1 / 1.4, animated: true) }
                    viewButton("plus", "Zoom in") { scene3D.zoomBy(1.4, animated: true) }
                }
                .padding(8)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func viewButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .light))
                .frame(width: 40, height: 40)
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func load3D() {
        guard !scene3DLoaded, let scan else { return }
        scene3DLoaded = true
        scene3D.load(scan: scan, ref: ref, floorY: plan.floorY, plan: plan)
        scene3D.applyAlignment(scan.alignmentValue)
        sync3D()
    }

    private func openAlignment() {
        guard scan != nil else { return }
        if layout == .plan { layout = .split }
        load3D()
        showAlignment = true
    }

    private func setAlignment(_ a: ScanAlignment) {
        guard let id = scan?.id else { return }
        edit { loc in
            if let i = loc.scans.firstIndex(where: { $0.id == id }) { loc.scans[i].alignment = a.isIdentity ? nil : a }
        }
    }

    /// Pushes cameras, people, meters and lights to the 3D view; cheap enough to run on every edit.
    private func sync3D() {
        guard shows3D, let location else { return }
        let d = location.displaySettings
        var viewpoints: [VirtualViewpoint] = location.cameraPositions.filter { inScan($0.scanID) }.map {
            VirtualViewpoint(id: $0.id, kind: .camera, label: $0.name, rig: $0.rig, subject: nil, subjectHeight: 1.75)
        }
        viewpoints += location.shots.filter { inScan($0.scanID) }.map {
            VirtualViewpoint(id: $0.id, kind: .shot, label: $0.code, rig: $0.rig, subject: $0.subject, subjectHeight: $0.subjectHeight)
        }
        var selectedCamera: UUID?, selectedLight: UUID?, selectedPerson: UUID?, selectedMeter: UUID?
        switch selection {
        case .camera(let id)?, .shot(let id)?: selectedCamera = id
        case .light(let id)?: selectedLight = id
        case .character(let id)?: selectedPerson = id
        case .meter(let id)?: selectedMeter = id
        default: break
        }
        let people = location.previsCharacters.filter { inScan($0.scanID) }
        scene3D.setMarkers(viewpoints: viewpoints, selected: selectedCamera, showLabels: d.showsLabels(.cameras),
                           hiddenSubjects: !people.isEmpty)
        scene3D.setPeople(people, selected: selectedPerson, showLabels: d.showsLabels(.people))
        let analysis = makeAnalysis()
        let meters = location.lightMeters.filter { inScan($0.scanID) }.map { m in
            (id: m.id, name: m.name, point: LightingCalculator.Point(m.position, height: m.height),
             text: readingText(analysis.reading(.meter(m.id))) ?? m.name)
        }
        scene3D.setMeters(meters, selected: selectedMeter, showLabels: d.showsLabels(.meters))
        let lights = sceneLights.filter { $0.kind.emits ? !d.isHidden(group: .lights) : !d.isHidden(group: .grip) }
        scene3D.setLights(lights, selected: selectedLight, showLabels: d.showsLabels(.lights), showBeams: true, plan: plan)
        scene3D.setStage(stageVisuals(location))
        scene3D.applyDisplay(d)
        if scene3D.loaded, let scan { scene3D.applyAlignment(scan.alignmentValue) }
        scene3D.showSelection(at: selection.flatMap { position(of: $0)?.point })
    }

    /// Backdrop, floor, curtains and daylight for the 3D view, or nil when there are none.
    private func stageVisuals(_ location: Location) -> StageVisuals? {
        guard !plan.isEmpty else { return nil }
        var v = StageVisuals()
        v.backdrop = Stage.backdropPlacement(location, plan: plan)
        if let st = location.studio {
            v.ledNits = st.nits ?? Stage.ledDefaultNits
            v.ledKelvin = st.kelvin ?? 5600
            v.floor = Stage.floor(st.floor)
            v.floorColour = st.floorColour
        }
        v.curtains = plan.windows.compactMap { w in
            w.curtain.map { StageVisuals.Curtain(window: w, kind: $0, inward: Stage.inwardNormal(w.a, w.b, plan: plan)) }
        }
        v.floorPolygons = plan.floorPolygons
        if v.floorPolygons.isEmpty {
            let b = plan.bounds
            v.floorPolygons = [[PlanPoint(x: b.minX, z: b.minZ), PlanPoint(x: b.maxX, z: b.minZ), PlanPoint(x: b.maxX, z: b.maxZ), PlanPoint(x: b.minX, z: b.maxZ)]]
        }
        v.floorY = plan.floorY
        v.ceiling = plan.walls.map { $0.bottom + $0.height }.max() ?? 2.6
        if location.daylight?.isOn == true {
            let sun = Stage.sunPlacement(location, scan: scan)
            let sky = location.daylight?.sky ?? .clear
            let levels = Stage.daylightLevels(sky, elevation: sun.elevation)
            v.daylight = StageVisuals.Daylight(sky: sky, bearing: sun.bearing, elevation: sun.elevation, directNormal: levels.directNormal,
                                               windowLuminance: Stage.windowViewLuminance(levels, elevation: sun.elevation))
        }
        if v.backdrop == nil && v.floor == nil && v.curtains.isEmpty && v.daylight == nil { return nil }
        return v
    }

    private func handle3DTap(_ item: PlanSelection?, _ point: PlanPoint?) {
        switch tool {
        case .select, .measure:
            selection = item
        case .add:
            if let item {
                selection = item
                tool = .select
            } else if let point {
                add(at: point)
            }
        case .aim:
            if let target = item.flatMap({ position(of: $0)?.point }) ?? point { aimSelection(at: target) }
        case .subject:
            if let point { setSubject(at: point) }
        }
    }

    // MARK: Plan

    private func planArea(_ analysis: LightingAnalysis) -> some View {
        GeometryReader { geo in
            let viewport = currentViewport(size: geo.size)
            let o = overlay(analysis)
            ZStack(alignment: .top) {
                Theme.background
                FloorPlanCanvas(plan: visiblePlan, overlay: o, style: .full, viewport: viewport)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(viewport: viewport))
                    .simultaneousGesture(pinchGesture)
                infoBar
                if (layout == .plan || !shows3D) && tool != .select {
                Text(tool.hint)
                    .font(.fsCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .padding(8)
                    .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    // Below the Show bar, clear of the north arrow, and never blocks a tap.
                    .padding(.top, 52)
                    .padding(.horizontal, 44)
                    .allowsHitTesting(false)
                }
                if plan.isEmpty {
                    noScanNotice.padding(.top, 60)
                }
                if o.luxMap != nil && geo.size.height > 300 {
                    luxLegend.frame(maxHeight: .infinity, alignment: .bottom).padding(8)
                }
            }
            .clipped()
        }
    }

    /// "Show" bar: the plan starts with the essentials; each chip adds one layer of information.
    private var infoBar: some View {
        HStack(spacing: 6) {
            Button { withAnimation(.snappy) { showInfoBar.toggle() } } label: {
                HStack(spacing: 4) {
                    Text("SHOW").font(.fsLabel).tracking(Theme.tracking)
                    let count = infoLayers.count + (display.luxMapOn ? 1 : 0)
                    if count > 0 && !showInfoBar { Text("+\(count)").font(.fsLabel) }
                    Image(systemName: showInfoBar ? "chevron.left" : "chevron.right").font(.fsMicro)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10).frame(minHeight: 32)
                .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showInfoBar ? "Hide information layers" : "Show more information on the plan")
            if showInfoBar {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PlanInfoLayer.allCases) { layer in
                            infoChip(layer.label, on: infoLayers.contains(layer)) { toggle(layer) }
                        }
                        if !sceneLights.isEmpty {
                            infoChip("Exposure map", on: display.luxMapOn) {
                                let v = !display.luxMapOn
                                updateDisplay { $0.showLuxMap = v ? true : nil }
                            }
                        }
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func infoChip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.fsLabel).tracking(Theme.tracking)
                .foregroundStyle(on ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, 10).frame(minHeight: 32)
                .background(on ? Theme.accent : Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The plan without the set pieces that are hidden.
    private var visiblePlan: FloorPlan {
        var p = plan
        let d = display
        if d.isHidden(group: .furniture) {
            p.objects = []
        } else {
            p.objects.removeAll { d.isHidden(object: $0.id, category: $0.category) }
        }
        return p
    }

    private var luxLegend: some View {
        HStack(spacing: 0) {
            ForEach(Array(PlanLuxMap.legend.enumerated()), id: \.offset) { pair in
                let entry = pair.element
                Text(entry.0)
                    .font(.fsMicro)
                    .foregroundStyle(Theme.onAccent)
                    .frame(minWidth: 30, minHeight: 18)
                    .background(PlanLuxMap.color(entry.1) ?? .clear)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("STOPS AT \(ExposureSettings.stopLabel(exposure.tStop)) · 1.5 M · ESTIMATE")
                .font(.fsMicro).tracking(Theme.tracking).foregroundStyle(Theme.textSecondary)
                .offset(y: -16)
        }
        .padding(.top, 16)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure map legend, from three stops under to two over key. Estimated.")
    }

    // MARK: Viewport & gestures

    private func contentBounds() -> PlanRect {
        var bounds = plan.isEmpty ? PlanRect(minX: -4, minZ: -4, maxX: 4, maxZ: 4) : plan.bounds
        if let location, let extra = PlanRect.enclosing(location.cameraPositions.map(\.rig.position) + location.shots.map(\.rig.position)
                                                         + location.lightFixtures.map(\.position)
                                                         + location.previsCharacters.map(\.position)
                                                         + location.lightMeters.map(\.position)) {
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
                case .item(let item):
                    move(item, to: world)
                case .subject(let id):
                    edit { loc in
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
        let d = display
        let radius: CGFloat = 26
        func near(_ p: PlanPoint) -> Bool {
            let s = viewport.toScreen(p)
            return hypot(s.x - point.x, s.y - point.y) < radius
        }
        if !d.isHidden(group: .people) {
            for c in location.previsCharacters where inScan(c.scanID) && near(c.position) { return .item(.character(c.id)) }
        }
        if !d.isHidden(group: .meters) {
            for m in location.lightMeters where inScan(m.scanID) && near(m.position) { return .item(.meter(m.id)) }
        }
        if !d.isHidden(group: .cameras) {
            for shot in location.shots {
                if let subject = shot.subject, near(subject) { return .subject(shot.id) }
            }
            for shot in location.shots where near(shot.rig.position) { return .item(.shot(shot.id)) }
            for cam in location.cameraPositions where near(cam.rig.position) { return .item(.camera(cam.id)) }
        }
        for light in sceneLights where near(light.position) {
            if light.kind.emits ? !d.isHidden(group: .lights) : !d.isHidden(group: .grip) { return .item(.light(light.id)) }
        }
        // Set pieces and openings drag only once selected, so a finger on a sofa still pans the plan.
        let world = viewport.toWorld(point)
        switch selection {
        case .object(let id)?:
            if object(at: world)?.id == id { return .item(.object(id)) }
        case .opening(let id)?:
            if opening(at: world, viewport: viewport)?.id == id { return .item(.opening(id)) }
        default: break
        }
        return nil
    }

    /// Door, window or opening under a plan point (within a finger's width), if it's shown.
    private func opening(at p: PlanPoint, viewport: PlanViewport) -> PlanSegment? {
        let d = display
        let reach = Double(18 / viewport.scale)
        let shown = (d.isHidden(group: .windows) ? [] : plan.windows) + (d.isHidden(group: .doors) ? [] : plan.doors + plan.openings)
        return shown.filter { LightingCalculator.distance(p, toSegment: $0.a, $0.b) < reach }
            .min { LightingCalculator.distance(p, toSegment: $0.a, $0.b) < LightingCalculator.distance(p, toSegment: $1.a, $1.b) }
    }

    /// Set piece under a plan point, if it's shown.
    private func object(at p: PlanPoint) -> PlanObject? {
        visiblePlan.objects.first { o in
            let dx = p.x - o.center.x, dz = p.z - o.center.z
            let c = cos(-o.rotation), s = sin(-o.rotation)
            let lx = dx * c - dz * s, lz = dx * s + dz * c
            return abs(lx) <= o.width / 2 && abs(lz) <= o.depth / 2
        }
    }

    private func handleTap(at point: CGPoint, viewport: PlanViewport, hit: DragTarget?) {
        let world = viewport.toWorld(point)
        switch tool {
        case .select:
            switch hit {
            case .item(let item): selection = item
            case .subject(let id): selection = .shot(id)
            default:
                selection = opening(at: world, viewport: viewport).map { PlanSelection.opening($0.id) }
                    ?? object(at: world).map { PlanSelection.object($0.id) }
            }
        case .add:
            if case .item(let item)? = hit {
                selection = item
                tool = .select
            } else {
                add(at: world)
            }
        case .aim:
            aimSelection(at: world)
        case .subject:
            setSubject(at: world)
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

    private var infoLayers: Set<PlanInfoLayer> {
        Set(infoLayersRaw.split(separator: ",").compactMap { PlanInfoLayer(rawValue: String($0)) })
    }

    private func toggle(_ layer: PlanInfoLayer) {
        var set = infoLayers
        if set.contains(layer) { set.remove(layer) } else { set.insert(layer) }
        infoLayersRaw = PlanInfoLayer.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }

    private func overlay(_ analysis: LightingAnalysis) -> PlanOverlay {
        var o = PlanOverlay()
        let d = display
        let info = infoLayers
        let readings = info.contains(.readings)
        o.showAllBeams = info.contains(.beams)
        o.showAllCameraViews = info.contains(.views)
        o.showDimensions = d.showsLabels(.dimensions) && info.contains(.dimensions)
        o.showObjectLabels = d.showsLabels(.objects) && info.contains(.names)
        o.showCameraLabels = d.showsLabels(.cameras)
        o.showLightLabels = d.showsLabels(.lights)
        o.showPeopleLabels = d.showsLabels(.people)
        o.showMeterLabels = d.showsLabels(.meters)
        if case .object(let id)? = selection { o.selectedObject = id }
        if case .opening(let id)? = selection { o.selectedSegment = id }
        guard let location else { return o }
        let sid = scan?.id
        o.luxMap = luxMap(analysis)
        let key = exposure.keyLux
        for light in sceneLights {
            guard light.kind.emits ? !d.isHidden(group: .lights) : !d.isHidden(group: .grip) else { continue }
            var marker = PlanLightMarker(light: light, selected: selection == .light(light.id))
            if light.kind.emits {
                let pm = light.photometrics
                // Wedge length: where this unit alone falls two stops under key.
                marker.reach = pm.distance(forLux: key / 4).map { min(max($0, 1), 12) }
                let half = min(pm.beamAngle, 170) / 2
                let doors = light.barnDoorSettings
                marker.leftHalf = min(half, doors.left)
                marker.rightHalf = min(half, doors.right)
                marker.tint = pm.color
                marker.label = !light.isOn ? "\(light.name) · off" : readings ? "\(light.name) · \(Int((light.dimmer * 100).rounded())) %" : light.name
            }
            o.lights.append(marker)
        }
        if !d.isHidden(group: .people) {
            for c in location.previsCharacters where inScan(c.scanID) {
                let p = c.proportions
                o.people.append(PlanPersonMarker(id: c.id, name: c.name, position: c.position, facing: c.facing,
                                                 shoulderWidth: p.shoulderWidth, depth: p.chestDepth, headRadius: p.headWidth / 2,
                                                 skin: c.skinTone.rgb, reading: readings || selection == .character(c.id) ? readingText(analysis.reading(.character(c.id))) : nil,
                                                 selected: selection == .character(c.id)))
            }
        }
        if !d.isHidden(group: .meters) {
            for m in location.lightMeters where inScan(m.scanID) {
                let r = analysis.reading(.meter(m.id))
                let stops = r.map { log2(max($0.lux, 1e-6) / (m.targetLux ?? key)) }
                o.meters.append(PlanMeterMarker(id: m.id, name: m.name, position: m.position,
                                                reading: readings || selection == .meter(m.id) ? readingText(r) ?? "—" : "",
                                                onKey: stops.map { abs($0) <= 1.0 / 3 } ?? false,
                                                selected: selection == .meter(m.id)))
            }
        }
        for mm in location.measurements where mm.source == .plan && (mm.scanID == nil || mm.scanID == sid) {
            if let a = mm.planA, let b = mm.planB {
                o.measurements.append(PlanMeasureLine(a: a, b: b, label: mm.label.isEmpty ? UnitsFormatter.distance(mm.value) : "\(mm.label) \(UnitsFormatter.distance(mm.value))"))
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
        o.backdrop = plan.isEmpty ? nil : Stage.backdropPlacement(location, plan: plan)
        if location.daylight?.isOn == true {
            // Where the sun is, and which bare windows it comes in through.
            let sun = Stage.sunPlacement(location, scan: scan)
            o.sunWorldBearing = sun.bearing
            o.sunElevation = sun.elevation
            if sun.elevation > 0 && !plan.isEmpty {
                let toward = PlanPoint.unit(bearing: sun.bearing)
                o.litWindows = Set(plan.windows.filter { w in
                    let n = Stage.inwardNormal(w.a, w.b, plan: plan)
                    return w.curtain == nil && toward.x * n.x + toward.z * n.z < 0
                }.map(\.id))
            }
        }
        guard !d.isHidden(group: .cameras) else { return o }
        let hasPeople = !location.previsCharacters.filter { inScan($0.scanID) }.isEmpty && !d.isHidden(group: .people)
        for cam in location.cameraPositions where inScan(cam.scanID) {
            o.cameras.append(PlanCameraMarker(id: cam.id, label: cam.name, rig: cam.rig,
                                              selected: selection == .camera(cam.id), reach: 4))
        }
        for shot in location.shots where inScan(shot.scanID) {
            o.cameras.append(PlanCameraMarker(id: shot.id, label: String(format: "S%02d", shot.number), rig: shot.rig,
                                              isShot: true, selected: selection == .shot(shot.id),
                                              reach: max(1.5, (shot.subjectDistance ?? 4) + 1)))
            if let subject = shot.subject, !hasPeople || selection == .shot(shot.id) {
                o.subjects.append(PlanSubjectMarker(id: shot.id, label: String(format: "S%02d", shot.number),
                                                    point: subject, selected: selection == .shot(shot.id)))
            }
        }
        return o
    }

    private var measureDistance: Double? {
        measurePoints.count == 2 ? measurePoints[0].distance(to: measurePoints[1]) : nil
    }

    // MARK: Items

    /// Plan position and height above the floor of a selectable item.
    private func position(of item: PlanSelection) -> (point: PlanPoint, height: Double)? {
        guard let location else { return nil }
        switch item {
        case .camera(let id):
            return location.cameraPositions.first { $0.id == id }.map { (point: $0.rig.position, height: $0.rig.height) }
        case .shot(let id):
            return location.shots.first { $0.id == id }.map { (point: $0.rig.position, height: $0.rig.height) }
        case .light(let id):
            return location.lightFixtures.first { $0.id == id }.map { (point: $0.position, height: $0.height) }
        case .character(let id):
            return location.previsCharacters.first { $0.id == id }.map { (point: $0.position, height: 0.0) }
        case .meter(let id):
            return location.lightMeters.first { $0.id == id }.map { (point: $0.position, height: $0.height) }
        case .object(let id):
            return plan.objects.first { $0.id == id }.map { (point: $0.center, height: $0.height / 2) }
        case .opening(let id):
            return plan.segment(id).map { (point: $0.midpoint, height: $0.bottom + $0.height / 2) }
        }
    }

    private func move(_ item: PlanSelection, to p: PlanPoint) {
        switch item {
        case .camera(let id): updateCamera(id) { $0.rig.position = p }
        case .shot(let id): updateShot(id) { $0.rig.position = p }
        case .light(let id): updateLight(id) { $0.position = p }
        case .character(let id): updateCharacter(id) { $0.position = p }
        case .meter(let id): updateMeter(id) { $0.position = p }
        case .object(let id):
            editPlan { plan in
                guard var o = plan.objects.first(where: { $0.id == id }) else { return }
                o.center = PlanPoint(x: (p.x * 100).rounded() / 100, z: (p.z * 100).rounded() / 100)
                o.byHand = true
                plan.replace(o)
            }
        case .opening(let id):
            editPlan { plan in
                guard let seg = plan.segment(id) else { return }
                plan.replace(SetPieces.slide(seg, to: p, in: plan))
            }
        }
    }

    /// Turns an item by `degrees` (clockwise seen from above).
    private func rotate(_ item: PlanSelection, by degrees: Double) {
        func wrap(_ v: Double) -> Double { (v.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
        switch item {
        case .camera(let id): updateCamera(id) { $0.rig.pan = wrap($0.rig.pan + degrees) }
        case .shot(let id): updateShot(id) { $0.rig.pan = wrap($0.rig.pan + degrees) }
        case .light(let id): updateLight(id) { $0.pan = wrap($0.pan + degrees) }
        case .character(let id): updateCharacter(id) { $0.facing = wrap($0.facing + degrees) }
        case .meter(let id):
            updateMeter(id) { m in
                if m.facing != .bearing { m.facing = .bearing }
                m.bearing = wrap(m.bearing + degrees)
            }
        case .object(let id):
            editPlan { plan in
                guard let o = plan.objects.first(where: { $0.id == id }) else { return }
                plan.replace(SetPieces.turned(o, by: degrees * .pi / 180))
            }
        case .opening: break
        }
    }

    // MARK: Actions

    private var currentAddProfileID: String {
        if case .light(let id) = addItem { return id }
        return "cob-600-d"
    }

    private func add(at point: PlanPoint) {
        switch addItem {
        case .camera: addCamera(at: point)
        case .light(let id): addLight(FixtureLibrary.profile(id: id) ?? FixtureLibrary.defaultProfile(for: .fresnel), at: point)
        case .grip(let kind): addGrip(kind, at: point)
        case .person(let type): addPerson(type, at: point)
        case .meter: addMeter(at: point)
        case .opening(let id):
            guard let preset = SetPieces.opening(id), let seg = SetPieces.placeOpening(plan.isEmpty ? nil : plan, at: point, preset: preset) else {
                // Missed the walls: keep the tool so the next tap can try again.
                notice = plan.walls.isEmpty ? "This plan has no walls to put a door or window in." : "Tap on a wall, or within a metre of one."
                return
            }
            editPlan { $0.add(seg) }
            selection = .opening(seg.id)
            notice = nil
        case .furniture(let id):
            guard let preset = SetPieces.furniturePreset(id) else { return }
            let o = SetPieces.placeFurniture(plan.isEmpty ? nil : plan, at: point, preset: preset)
            editPlan { $0.objects.append(o) }
            selection = .object(o.id)
        }
        tool = .select
    }

    /// Where a new unit or person should face: the nearest person or subject, else the room centre.
    private func defaultAim(from point: PlanPoint) -> PlanPoint {
        guard let location else { return point }
        let subjects = location.previsCharacters.filter { inScan($0.scanID) }.map(\.position) + location.shots.compactMap(\.subject)
        return subjects.filter { $0.distance(to: point) > 0.3 }.min { $0.distance(to: point) < $1.distance(to: point) }
            ?? (plan.isEmpty ? PlanPoint(x: point.x, z: point.z - 1) : plan.interiorCentroid)
    }

    private func addCamera(at point: PlanPoint) {
        guard let location else { return }
        var rig = location.cameraPositions.last?.rig ?? CameraRig()
        rig.position = point
        rig.pan = PlanGeometry.bearing(from: point, to: defaultAim(from: point))
        let name = "Camera \(Character(UnicodeScalar(65 + min(25, location.cameraPositions.count))!))"
        let cam = CameraPosition(name: name, rig: rig, scanID: scan?.id)
        edit { $0.cameraPositions.append(cam) }
        selection = .camera(cam.id)
    }

    private func addLight(_ profile: FixtureProfile, at point: PlanPoint) {
        guard let location else { return }
        let emitting = location.lightFixtures.filter { $0.kind.emits }.count
        var light = LightFixture(name: "L\(emitting + 1)", kind: profile.kind, position: point,
                                 pan: PlanGeometry.bearing(from: point, to: defaultAim(from: point)), scanID: scan?.id)
        light.apply(profile: profile)
        // Start from the last unit of the same type so a row of lights is quick to place.
        if let last = location.lightFixtures.last(where: { $0.profile.id == profile.id }) {
            light.dimmer = last.dimmer
            light.colorTemperature = last.colorTemperature
            light.height = last.height
            light.tilt = last.tilt
            light.beamAngle = last.beamAngle
            light.modifierID = last.modifierID
        }
        edit { $0.lightFixtures.append(light) }
        selection = .light(light.id)
    }

    private func addGrip(_ kind: LightKind, at point: PlanPoint) {
        guard let location else { return }
        let count = location.lightFixtures.filter { $0.kind == kind }.count
        var board = LightFixture(name: count == 0 ? kind.label : "\(kind.label) \(count + 1)", kind: kind, position: point,
                                 pan: PlanGeometry.bearing(from: point, to: defaultAim(from: point)), scanID: scan?.id)
        if let last = location.lightFixtures.last(where: { $0.kind == kind }) {
            board.width = last.width
            board.height = last.height
            board.boardHeight = last.boardHeight
        }
        edit { $0.lightFixtures.append(board) }
        selection = .light(board.id)
    }

    private func addPerson(_ type: CharacterType, at point: PlanPoint) {
        guard let location else { return }
        let count = location.previsCharacters.filter { $0.type == type }.count
        // Face the nearest camera, as an actor on a mark would.
        let cams = location.meterCameras.map(\.position)
        let look = cams.min { $0.distance(to: point) < $1.distance(to: point) } ?? defaultAim(from: point)
        var person = PrevisCharacter(name: count == 0 ? type.label : "\(type.label) \(count + 1)", type: type, position: point,
                                     facing: PlanGeometry.bearing(from: point, to: look), scanID: scan?.id)
        if let last = location.previsCharacters.last(where: { $0.type == type }) {
            person.skinTone = last.skinTone
        }
        edit { $0.previsCharacters.append(person) }
        selection = .character(person.id)
    }

    private func addMeter(at point: PlanPoint) {
        guard let location else { return }
        let meter = LightMeter(name: "Meter \(location.lightMeters.count + 1)", position: point, scanID: scan?.id)
        edit { $0.lightMeters.append(meter) }
        selection = .meter(meter.id)
    }

    private func setSubject(at point: PlanPoint) {
        guard case .shot(let id) = selection else { return }
        edit { loc in
            if let i = loc.shots.firstIndex(where: { $0.id == id }) {
                loc.shots[i].subject = point
                loc.shots[i].rig.pan = PlanGeometry.bearing(from: loc.shots[i].rig.position, to: point)
            }
        }
    }

    private func aimSelection(at point: PlanPoint) {
        guard let selection, let from = position(of: selection)?.point, from.distance(to: point) > 0.05 else { return }
        let bearing = PlanGeometry.bearing(from: from, to: point)
        switch selection {
        case .camera(let id): updateCamera(id) { $0.rig.pan = bearing }
        case .shot(let id): updateShot(id) { $0.rig.pan = bearing }
        case .light(let id): updateLight(id) { $0.pan = bearing }
        case .character(let id): updateCharacter(id) { $0.facing = bearing }
        case .meter(let id):
            updateMeter(id) { m in
                m.facing = .bearing
                m.bearing = bearing
            }
        case .object, .opening: break
        }
    }

    private var snapshot: EditSnapshot? {
        location.map { EditSnapshot(location: $0, plan: scan == nil ? nil : plan) }
    }

    /// Every change made in the editor goes through here so it can be undone.
    private func edit(_ mutate: (inout Location) -> Void) {
        if let snapshot { history.willEdit(snapshot) }
        store.updateLocation(ref, mutate)
    }

    /// Changes the scan's 2D plan by hand: doors, windows, set pieces. Undoable like `edit`.
    private func editPlan(_ mutate: (inout FloorPlan) -> Void) {
        guard let scan else { return }
        var next = plan
        mutate(&next)
        guard next != plan else { return }
        if let snapshot { history.willEdit(snapshot) }
        store.setFloorPlan(next, ref, scanID: scan.id)
    }

    private func restore(_ s: EditSnapshot) {
        store.updateLocation(ref) { $0 = s.location }
        if let p = s.plan, let scan, p != plan { store.setFloorPlan(p, ref, scanID: scan.id) }
    }

    private func undo() {
        guard let current = snapshot, let previous = history.undo(from: current) else { return }
        restore(previous)
        notice = nil
    }

    private func redo() {
        guard let current = snapshot, let next = history.redo(from: current) else { return }
        restore(next)
    }

    /// Places a lighting setup round a person, set for the camera's exposure.
    private func light(_ person: PrevisCharacter, with setup: LightingSetup) {
        guard let location else { return }
        let camera = MeterGeometry.camera(seeing: person.position, from: location.meterCameras)?.position
        let result = setup.build(for: person, camera: camera, exposure: exposure, plan: plan.isEmpty ? nil : plan,
                                 windowTransmission: display.windowTransmissionValue)
        guard !result.lights.isEmpty else { return }
        edit { $0.lightFixtures.append(contentsOf: result.lights) }
        selection = .light(result.lights[0].id)
        notice = "\(setup.label) for \(person.name)\(camera == nil ? " (no camera yet: lit from where they face)" : ""). "
            + result.notes.joined(separator: " · ") + ". Undo removes it."
    }

    /// Places one of the user's own presets round a person (or at the window nearest them).
    private func light(_ person: PrevisCharacter, with preset: LightingPreset) {
        guard let location else { return }
        let camera = MeterGeometry.camera(seeing: person.position, from: location.meterCameras)?.position
        let result = preset.build(for: person, camera: camera, exposure: exposure, plan: plan.isEmpty ? nil : plan,
                                  windowTransmission: display.windowTransmissionValue)
        guard !result.lights.isEmpty else {
            notice = "\(preset.name): \(result.notes.joined(separator: " · "))."
            return
        }
        edit { $0.lightFixtures.append(contentsOf: result.lights) }
        selection = .light(result.lights[0].id)
        let how = preset.anchor == .window ? " (at the nearest window)" : camera == nil ? " (no camera yet: lit from where they face)" : ""
        notice = "\(preset.name)\(how). " + result.notes.joined(separator: " · ") + ". Undo removes it."
    }

    @ViewBuilder
    private func presetSheetView(_ sheet: PresetSheet) -> some View {
        switch sheet {
        case .manage:
            ManagePresetsSheet()
        case .save(let id):
            if let location, let person = location.previsCharacters.first(where: { $0.id == id }) {
                SavePresetSheet(person: person, lights: sceneLights,
                                camera: MeterGeometry.camera(seeing: person.position, from: location.meterCameras)?.position,
                                exposure: exposure, plan: plan.isEmpty ? nil : plan,
                                windowTransmission: display.windowTransmissionValue) { saved in
                    notice = "Saved “\(saved.name)” with \(saved.units.count) unit\(saved.units.count == 1 ? "" : "s"). It is in every person's Light menu."
                }
            }
        }
    }

    private func updateLight(_ id: UUID, _ mutate: @escaping (inout LightFixture) -> Void) {
        edit { loc in
            var lights = loc.lightFixtures
            if let i = lights.firstIndex(where: { $0.id == id }) {
                mutate(&lights[i])
                loc.lightFixtures = lights
            }
        }
    }

    private func updateCharacter(_ id: UUID, _ mutate: @escaping (inout PrevisCharacter) -> Void) {
        edit { loc in
            var list = loc.previsCharacters
            if let i = list.firstIndex(where: { $0.id == id }) {
                mutate(&list[i])
                loc.previsCharacters = list
            }
        }
    }

    private func updateMeter(_ id: UUID, _ mutate: @escaping (inout LightMeter) -> Void) {
        edit { loc in
            var list = loc.lightMeters
            if let i = list.firstIndex(where: { $0.id == id }) {
                mutate(&list[i])
                loc.lightMeters = list
            }
        }
    }

    private var displayBinding: Binding<SceneDisplay> {
        Binding(get: { display }, set: { v in edit { $0.displaySettings = v } })
    }

    private func updateDisplay(_ mutate: @escaping (inout SceneDisplay) -> Void) {
        edit { loc in
            var d = loc.displaySettings
            mutate(&d)
            loc.displaySettings = d
        }
    }

    /// Renders the plan with cameras and lights as a PNG for sharing.
    @MainActor
    private func shareDiagram() {
        let canvas = FloorPlanCanvas(plan: visiblePlan, overlay: overlay(makeAnalysis()), style: .full)
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
        edit { $0.measurements.append(m) }
        measurePoints = []
    }

    private func createShot(from camera: CameraPosition) {
        guard let location else { return }
        let shot = Shot(number: location.nextShotNumber, rig: camera.rig, cameraPositionID: camera.id, scanID: camera.scanID)
        edit { $0.shots.append(shot) }
        selection = .shot(shot.id)
    }

    // MARK: Chrome

    private var toolBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlanTool.toolRow) { t in
                        let disabled = t == .aim && (selection == nil || selection?.isMovable == false)
                        Button { tool = t; if t != .measure { measurePoints = [] } } label: {
                            Label(t.label, systemImage: t.symbol)
                                .font(.fsLabel).tracking(Theme.tracking)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .foregroundStyle(tool == t ? Theme.onAccent : Theme.textPrimary)
                                .background(tool == t ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                        .opacity(disabled ? 0.4 : 1)
                        .accessibilityAddTraits(tool == t ? .isSelected : [])
                    }
                }
                .padding(.leading)
            }
            if scan != nil {
                Picker("Layout", selection: $layout) {
                    ForEach(PlanLayout.allCases) { l in
                        Image(systemName: l.symbol).accessibilityLabel(l.label).tag(l)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 128)
                .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    /// Choose what the next tap places.
    private var addPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    addChip(.camera, selected: addItem == .camera)
                    addChip(.light(currentAddProfileID), selected: { if case .light = addItem { return true }; return false }())
                    addChip(.grip(.bounce), selected: { if case .grip = addItem { return true }; return false }())
                    addChip(.person(.woman), selected: { if case .person = addItem { return true }; return false }())
                    addChip(.meter, selected: addItem == .meter)
                    if scan != nil {
                        addChip(.opening("door"), selected: { if case .opening = addItem { return true }; return false }())
                        addChip(.furniture("sofa"), selected: { if case .furniture = addItem { return true }; return false }())
                    }
                }
            }
            switch addItem {
            case .light(let id):
                Button { showFixturePicker = true } label: {
                    HStack {
                        Text((FixtureLibrary.profile(id: id) ?? FixtureLibrary.defaultProfile(for: .fresnel)).name).font(.fsBody)
                        Spacer()
                        Text("Change").font(.fsCaption).foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.right").font(.fsCaption).foregroundStyle(Theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .grip(let kind):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([LightKind.bounce, .negative, .flag, .diffusion], id: \.self) { k in
                            TagChip(text: k.label, selected: kind == k) { addItem = .grip(k) }
                        }
                    }
                }
            case .person(let type):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(CharacterType.allCases) { t in
                            TagChip(text: t.label, selected: type == t) { addItem = .person(t) }
                        }
                    }
                }
            case .camera:
                Text("A camera position. Make it a shot from its panel.").font(.fsCaption).foregroundStyle(Theme.textTertiary)
            case .meter:
                Text("Reads the light at a point, 1.5 m up, towards camera. Estimated.").font(.fsCaption).foregroundStyle(Theme.textTertiary)
            case .opening(let id):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SetPieces.openings) { o in TagChip(text: o.label, selected: id == o.id) { addItem = .opening(o.id) } }
                    }
                }
                Text("Tap a wall to put it in. Typical size; change it after.").font(.fsCaption).foregroundStyle(Theme.textTertiary)
            case .furniture(let id):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SetPieces.furniture) { f in TagChip(text: f.label, selected: id == f.id) { addItem = .furniture(f.id) } }
                    }
                }
                Text("Tap where it goes. Near a wall it backs onto it. Typical size; change it after.").font(.fsCaption).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }

    private func addChip(_ item: PlanAddItem, selected: Bool) -> some View {
        Button {
            if !selected { addItem = item }
        } label: {
            Label(item.label, systemImage: item.symbol)
                .font(.fsLabel).tracking(Theme.tracking)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .background(selected ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!history.canUndo)
                .accessibilityLabel("Undo")
            if history.canRedo {
                Button(action: redo) { Image(systemName: "arrow.uturn.forward") }
                    .accessibilityLabel("Redo")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showLayers = true } label: {
                Image(systemName: display.hiddenCount > 0 ? "eye.slash" : "square.3.layers.3d")
            }
            .accessibilityLabel(display.hiddenCount > 0 ? "Show and hide, \(display.hiddenCount) hidden" : "Show and hide")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let location, location.scans.count > 1 {
                    Picker("Scan", selection: Binding(get: { scan?.id }, set: { scanID = $0 })) {
                        ForEach(location.scans) { s in Text(s.name).tag(Optional(s.id)) }
                    }
                }
                Button { showExposure = true } label: { Label("Camera settings…", systemImage: "camera.aperture") }
                Toggle("Exposure map", isOn: Binding(get: { display.luxMapOn }, set: { v in updateDisplay { $0.showLuxMap = v ? true : nil } }))
                Button { showStage = true } label: { Label("Daylight and studio set…", systemImage: "sun.horizon") }
                if scan != nil {
                    Button { openAlignment() } label: { Label("Level and align scan…", systemImage: "level") }
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
    private func bottomPanel(_ analysis: LightingAnalysis) -> some View {
        if tool == .measure {
            measurePanel
        } else if tool == .add {
            addPanel
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
                                           edit { $0.cameraPositions.removeAll { $0.id == id } }
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
                                           edit { $0.shots.removeAll { $0.id == id } }
                                           self.selection = nil
                                       } label: { Label("Delete", systemImage: "trash") }
                                   }))
                }
            case .light(let id):
                if let light = location.lightFixtures.first(where: { $0.id == id }) {
                    LightPanel(light: light, context: analysis.context, update: { mutate in updateLight(id, mutate) },
                               onDetails: { showRigSheet = true },
                               onDuplicate: {
                                   var copy = light
                                   copy.id = UUID()
                                   copy.name = light.name + "′"
                                   copy.position = light.position + PlanPoint(x: 0.5, z: 0.5)
                                   edit { $0.lightFixtures.append(copy) }
                                   self.selection = .light(copy.id)
                               },
                               onDelete: {
                                   edit { $0.lightFixtures.removeAll { $0.id == id } }
                                   self.selection = nil
                               })
                }
            case .character(let id):
                if let person = location.previsCharacters.first(where: { $0.id == id }) {
                    let r = analysis.reading(.character(id))
                    CharacterPanel(character: person,
                                   reading: sceneLights.isEmpty ? nil : r.map { (lux: $0.lux, stops: exposure.stops(forLux: $0.lux)) },
                                   exposure: exposure,
                                   update: { mutate in updateCharacter(id, mutate) },
                                   onAim: { tool = .aim },
                                   onDuplicate: {
                                       var copy = person
                                       copy.id = UUID()
                                       copy.name = person.name + "′"
                                       copy.position = person.position + PlanPoint(x: 0.6, z: 0)
                                       edit { $0.previsCharacters.append(copy) }
                                       self.selection = .character(copy.id)
                                   },
                                   onDelete: {
                                       edit { $0.previsCharacters.removeAll { $0.id == id } }
                                       self.selection = nil
                                   },
                                   onLight: { setup in light(person, with: setup) },
                                   presets: presetLibrary.presets,
                                   onPreset: { preset in light(person, with: preset) },
                                   onSavePreset: { presetSheet = .save(person.id) },
                                   onManagePresets: { presetSheet = .manage })
                }
            case .meter(let id):
                if let meter = location.lightMeters.first(where: { $0.id == id }) {
                    MeterPanel(meter: meter, reading: analysis.reading(.meter(id)) ?? .zero, exposure: exposure,
                               lightName: { lid in location.lightFixtures.first { $0.id == lid }?.name ?? Stage.ambientName(lid) ?? "Unit" },
                               update: { mutate in updateMeter(id, mutate) },
                               onDelete: {
                                   edit { $0.lightMeters.removeAll { $0.id == id } }
                                   self.selection = nil
                               })
                }
            case .object(let id):
                if let object = plan.objects.first(where: { $0.id == id }) {
                    SetPiecePanel(object: object, plan: plan, display: display, updateDisplay: updateDisplay,
                                  update: { next in editPlan { $0.replace(next) } },
                                  onDuplicate: {
                                      var copy = object
                                      copy.id = UUID()
                                      copy.center = object.center + PlanPoint(x: 0.3, z: 0.3)
                                      copy.byHand = true
                                      editPlan { $0.objects.append(copy) }
                                      self.selection = .object(copy.id)
                                  },
                                  onDelete: {
                                      editPlan { $0.removeObject(id) }
                                      self.selection = nil
                                  },
                                  onClose: { self.selection = nil })
                }
            case .opening(let id):
                if let seg = plan.segment(id) {
                    OpeningPanel(segment: seg, plan: plan,
                                 update: { next in editPlan { $0.replace(next) } },
                                 onDelete: {
                                     editPlan { $0.removeSegment(id) }
                                     self.selection = nil
                                 })
                }
            }
        } else {
            overviewPanel(analysis)
        }
    }

    /// Nothing placed yet on this scan.
    private var isBlank: Bool {
        guard let location else { return false }
        return location.cameraPositions.filter { inScan($0.scanID) }.isEmpty && location.shots.filter { inScan($0.scanID) }.isEmpty
            && sceneLights.isEmpty && location.previsCharacters.filter { inScan($0.scanID) }.isEmpty
    }

    /// Three steps to a first lighting plan, each one tap away.
    private var firstSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("START HERE").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textSecondary)
            stepButton(1, "Place a person", "figure.stand") { addItem = .person(.woman); tool = .add }
            stepButton(2, "Place the camera", "video") { addItem = .camera; tool = .add }
            Text("3  Select the person, then Light this person for a starting setup.")
                .font(.fsCaption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func stepButton(_ n: Int, _ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(n)").font(.fsMono).foregroundStyle(Theme.textTertiary)
                Image(systemName: symbol)
                Text(title).font(.fsBody)
                Spacer()
                Image(systemName: "chevron.right").font(.fsCaption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func overviewPanel(_ analysis: LightingAnalysis) -> some View {
        // Room size gets its own row: four across truncates it on a phone.
        VStack(alignment: .leading, spacing: 12) {
            if isBlank { firstSteps }
            HStack(spacing: 16) {
                StatView(label: "Cameras", value: "\((location?.cameraPositions.count ?? 0) + (location?.shots.count ?? 0))")
                StatView(label: "Lights", value: "\(location?.lightFixtures.count ?? 0)")
                StatView(label: "People", value: "\(location?.previsCharacters.count ?? 0)")
            }
            StatView(label: "Room", value: UnitsFormatter.dimensions(scan?.stats.width, scan?.stats.length),
                     provenance: scan.map { $0.stats.provenance(of: .roomSize, kind: $0.kind) })
            Button { showExposure = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.aperture").foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exposure.summary).font(.fsMono).lineLimit(1).minimumScaleFactor(0.7)
                        Text(keyLine).font(.fsCaption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.fsCaption).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens camera exposure settings")
            ExposureQuickBar(exposure: exposureBinding)
            let points = analysis.context.meters
            if !points.isEmpty && !sceneLights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("READINGS").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                        Menu {
                            Picker("After the stop", selection: $readingExtra) {
                                ForEach(ReadingExtra.allCases) { unit in Text(unit == .off ? "Stop only" : "Stop + \(unit.label.lowercased())").tag(unit) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(readingExtra == .off ? "Stop only" : "Stop + \(readingExtra.label.lowercased())")
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.fsCaption)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Theme.surfaceRaised, in: Capsule())
                        }
                        .accessibilityLabel("Readings: \(readingExtra == .off ? "stop only" : "stop and \(readingExtra.label.lowercased())")")
                        Spacer()
                        ProvenanceBadge(provenance: .estimated)
                    }
                    ForEach(points.prefix(4)) { m in
                        HStack {
                            Text(m.name).font(.fsCaption).lineLimit(1)
                            Spacer()
                            Text(readingText(analysis.reading(m.source)) ?? "—").font(.fsMono)
                        }
                    }
                }
            }
            if display.hiddenCount > 0 {
                Button { showLayers = true } label: {
                    Label("\(display.hiddenCount) hidden · Show and hide", systemImage: "eye.slash").font(.fsCaption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
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
                    .foregroundStyle(Theme.onAccent)
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
            ExposureQuickBar(exposure: exposureBinding) { showExposure = true }
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
                        LightForm(light: Binding(get: { light }, set: { v in updateLight(id) { $0 = v } }), context: makeAnalysis().context)
                    }
                default:
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

    private var isLightSelected: Bool {
        if case .light = selection { return true }
        return false
    }

    private func updateCamera(_ id: UUID, _ mutate: @escaping (inout CameraPosition) -> Void) {
        edit { loc in
            if let i = loc.cameraPositions.firstIndex(where: { $0.id == id }) { mutate(&loc.cameraPositions[i]) }
        }
    }

    private func updateShot(_ id: UUID, _ mutate: @escaping (inout Shot) -> Void) {
        edit { loc in
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
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}
