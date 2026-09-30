import ARKit
import Combine
import RealityKit
import SwiftUI

enum ARMeasureMode: String, CaseIterable, Identifiable {
    case tape, range, height

    var id: String { rawValue }
    var label: String {
        switch self {
        case .tape: return "Tape"
        case .range: return "Rangefinder"
        case .height: return "Height"
        }
    }
    var hint: String {
        switch self {
        case .tape: return "Aim the centre at a point and tap + to drop it. Two points give a distance."
        case .range: return "Stand at the camera position and aim at the subject or background."
        case .height: return "Drop a point on the floor, then aim at the ceiling or top edge."
        }
    }
}

@MainActor
final class ARMeasureModel: ObservableObject {
    @Published var mode: ARMeasureMode = .tape
    @Published var reticleHit = false
    @Published var reticleDistance: Double?
    @Published var points: [SIMD3<Float>] = []
    @Published var trackingMessage: String?
    @Published var labelPosition: CGPoint?

    weak var view: ARMeasureARView?

    var liveEnd: SIMD3<Float>?

    var measured: (total: Double, horizontal: Double, vertical: Double)? {
        guard let a = points.first else { return nil }
        guard let b = points.count >= 2 ? points[1] : liveEnd else { return nil }
        let d = b - a
        let horizontal = Double(simd_length(SIMD2<Float>(d.x, d.z)))
        return (Double(simd_length(d)), horizontal, Double(abs(d.y)))
    }

    var isComplete: Bool { points.count >= 2 }

    func addPoint() {
        guard let hit = liveEnd else { return }
        if points.count >= 2 { reset() }
        points.append(hit)
        view?.syncMarkers(points: points)
    }

    func reset() {
        points = []
        view?.syncMarkers(points: [])
    }

    func undo() {
        guard !points.isEmpty else { return }
        points.removeLast()
        view?.syncMarkers(points: points)
    }
}

/// ARView subclass doing LiDAR-assisted raycasts from the screen centre every frame.
final class ARMeasureARView: ARView, ARSessionDelegate {
    weak var model: ARMeasureModel?
    private var updateSubscription: Cancellable?
    private let markerAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private var liveLine: ModelEntity?
    private let reticle = ModelEntity(mesh: .generateSphere(radius: 0.006),
                                      materials: [UnlitMaterial(color: .white)])

    required init(frame frameRect: CGRect) {
        super.init(frame: frameRect, cameraMode: .ar, automaticallyConfigureSession: false)
    }

    required init?(coder decoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func start() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            // LiDAR mesh makes raycasts land on real surfaces, not just detected planes.
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .none
        session.delegate = self
        session.run(config)
        scene.addAnchor(markerAnchor)
        let reticleAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        reticleAnchor.addChild(reticle)
        scene.addAnchor(reticleAnchor)
        updateSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.frameUpdate()
        }
    }

    func stop() {
        updateSubscription?.cancel()
        session.pause()
    }

    private func frameUpdate() {
        guard let model else { return }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        var hitPoint: SIMD3<Float>?
        if let result = raycast(from: centre, allowing: .estimatedPlane, alignment: .any).first {
            let c = result.worldTransform.columns.3
            hitPoint = SIMD3(c.x, c.y, c.z)
        }
        reticle.isEnabled = hitPoint != nil
        if let hitPoint { reticle.setPosition(hitPoint, relativeTo: nil) }

        var liveEnd = hitPoint
        var rangeDistance: Double?
        if model.mode == .range, let hitPoint, let cam = session.currentFrame?.camera.transform.columns.3 {
            rangeDistance = Double(simd_distance(hitPoint, SIMD3(cam.x, cam.y, cam.z)))
        }
        if model.mode == .height, let first = model.points.first, model.points.count == 1, let hitPoint {
            // Height mode measures straight up from the first point.
            liveEnd = SIMD3(first.x, hitPoint.y, first.z)
        }

        Task { @MainActor in
            model.reticleHit = hitPoint != nil
            model.liveEnd = liveEnd
            model.reticleDistance = rangeDistance
            if model.points.count == 1, let end = liveEnd, let start = model.points.first {
                self.drawLiveLine(from: start, to: end)
                let mid = (start + end) / 2
                model.labelPosition = self.project(mid)
            } else if model.points.count >= 2 {
                self.liveLine?.isEnabled = false
                model.labelPosition = self.project((model.points[0] + model.points[1]) / 2)
            } else {
                self.liveLine?.isEnabled = false
                model.labelPosition = nil
            }
            model.objectWillChange.send()
        }
    }

    func syncMarkers(points: [SIMD3<Float>]) {
        markerAnchor.children.removeAll()
        for p in points {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.01), materials: [UnlitMaterial(color: .systemYellow)])
            dot.position = p
            markerAnchor.addChild(dot)
        }
        if points.count >= 2 {
            markerAnchor.addChild(line(from: points[0], to: points[1], color: .systemYellow))
        }
    }

    private func drawLiveLine(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        liveLine?.removeFromParent()
        let l = line(from: a, to: b, color: .white)
        markerAnchor.addChild(l)
        liveLine = l
    }

    private func line(from a: SIMD3<Float>, to b: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let length = max(simd_distance(a, b), 0.0001)
        let entity = ModelEntity(mesh: .generateBox(width: 0.003, height: 0.003, depth: length),
                                 materials: [UnlitMaterial(color: color)])
        entity.position = (a + b) / 2
        if length > 0.001 {
            // Box depth runs along +Z; rotate it onto the segment (works for vertical lines too).
            entity.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(b - a))
        }
        return entity
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String?
        switch camera.trackingState {
        case .normal: message = nil
        case .notAvailable: message = "Tracking unavailable"
        case .limited(.initializing): message = "Move the phone slowly to start"
        case .limited(.excessiveMotion): message = "Slow down"
        case .limited(.insufficientFeatures): message = "Aim at a more detailed surface"
        case .limited: message = "Tracking limited"
        }
        Task { @MainActor [weak self] in self?.model?.trackingMessage = message }
    }
}

struct ARMeasureContainer: UIViewRepresentable {
    let model: ARMeasureModel

    func makeUIView(context: Context) -> ARMeasureARView {
        let view = ARMeasureARView(frame: .zero)
        view.model = model
        model.view = view
        view.start()
        return view
    }

    func updateUIView(_ view: ARMeasureARView, context: Context) {}

    static func dismantleUIView(_ view: ARMeasureARView, coordinator: ()) {
        view.stop()
    }
}

struct ARMeasureView: View {
    let target: CaptureTarget
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ARMeasureModel()
    @State private var showSave = false
    @State private var savedCount = 0

    var body: some View {
        ZStack {
            ARMeasureContainer(model: model).ignoresSafeArea()
            reticle
            if let pos = model.labelPosition, let m = model.measured {
                Text(UnitsFormatter.distance(m.total, precise: true))
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accent, in: Capsule())
                    .position(pos)
            }
            VStack {
                topBar
                Spacer()
                readout
                controls
            }
            .padding()
        }
        .statusBarHidden()
        .sheet(isPresented: $showSave) {
            SaveMeasurementSheet(target: target, reading: currentReading, mode: model.mode) {
                savedCount += 1
                model.reset()
            }
        }
    }

    private var currentReading: (total: Double, horizontal: Double?, vertical: Double?)? {
        if model.mode == .range, let d = model.reticleDistance { return (d, nil, nil) }
        guard let m = model.measured else { return nil }
        return (m.total, m.horizontal, m.vertical)
    }

    private var reticle: some View {
        ZStack {
            Circle().stroke(model.reticleHit ? Theme.accent : .white.opacity(0.5), lineWidth: 2).frame(width: 34, height: 34)
            Rectangle().fill(.white).frame(width: 2, height: 12)
            Rectangle().fill(.white).frame(width: 12, height: 2)
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                OverlayButton(systemImage: "xmark", size: 44) { dismiss() }
                Spacer()
                Picker("Mode", selection: $model.mode) {
                    ForEach(ARMeasureMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .onChange(of: model.mode) { _, _ in model.reset() }
                Spacer()
                if savedCount > 0 {
                    Text("\(savedCount) saved").font(.caption.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                }
            }
            Text(model.trackingMessage ?? model.mode.hint)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            if !DeviceCapabilities.hasLiDAR {
                Text("No LiDAR: accuracy depends on detected planes (typically ±2–5 cm at short range).")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var readout: some View {
        Group {
            if model.mode == .range {
                VStack(spacing: 2) {
                    Text("CAMERA → TARGET").font(.fsLabel).foregroundStyle(Theme.textSecondary)
                    Text(UnitsFormatter.distance(model.reticleDistance, precise: true)).font(.fsBigValue)
                }
            } else if let m = model.measured {
                VStack(spacing: 2) {
                    Text(UnitsFormatter.distance(model.mode == .height ? m.vertical : m.total, precise: true)).font(.fsBigValue)
                    if model.mode == .tape {
                        Text("horizontal \(UnitsFormatter.distance(m.horizontal)) · vertical \(UnitsFormatter.distance(m.vertical))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var controls: some View {
        HStack(alignment: .bottom) {
            OverlayButton(systemImage: "arrow.uturn.backward", label: "Undo") { model.undo() }
                .opacity(model.points.isEmpty ? 0.4 : 1)
            Spacer()
            if model.mode == .range {
                OverlayButton(systemImage: "square.and.arrow.down", label: "Save", tint: Theme.accent, filled: true, size: 76) {
                    showSave = true
                }
                .disabled(model.reticleDistance == nil)
            } else {
                OverlayButton(systemImage: "plus", label: model.isComplete ? "New" : "Point", tint: Theme.accent, filled: true, size: 76) {
                    model.addPoint()
                }
                .disabled(!model.reticleHit)
            }
            Spacer()
            OverlayButton(systemImage: "checkmark", label: "Save", tint: Theme.success, filled: true) { showSave = true }
                .disabled(currentReading == nil || (model.mode != .range && !model.isComplete))
                .opacity(currentReading == nil || (model.mode != .range && !model.isComplete) ? 0.4 : 1)
        }
    }
}

struct SaveMeasurementSheet: View {
    let target: CaptureTarget
    let reading: (total: Double, horizontal: Double?, vertical: Double?)?
    let mode: ARMeasureMode
    var onSaved: () -> Void

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MeasurementKind = .custom
    @State private var label = ""
    @State private var notes = ""
    @State private var destination: LocationRef?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(UnitsFormatter.distance(value, precise: true)).font(.fsBigValue)
                }
                Section("What is it?") {
                    Picker("Type", selection: $kind) {
                        ForEach(MeasurementKind.allCases) { k in Label(k.label, systemImage: k.symbol).tag(k) }
                    }
                    TextField("Label (e.g. Kitchen doorway)", text: $label)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if target.locationRef == nil {
                    Section("Save to") {
                        LocationPickerRows(selection: $destination)
                    }
                }
            }
            .fsScreen()
            .navigationTitle("Save Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear {
                destination = target.locationRef
                switch mode {
                case .range: kind = .cameraToSubject
                case .height: kind = .ceilingHeight
                case .tape: kind = .wallToWall
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var value: Double {
        guard let reading else { return 0 }
        return mode == .height ? (reading.vertical ?? reading.total) : reading.total
    }

    private func save() {
        guard let reading else { return }
        let ref = destination ?? {
            let pid = store.quickScanProjectID()
            return store.addLocation(to: pid, name: "Measurements \(Date().formatted(date: .abbreviated, time: .omitted))")
        }()
        guard let ref else { return }
        let m = DistanceMeasurement(kind: kind, label: label, value: value,
                                    vertical: reading.vertical, horizontal: reading.horizontal,
                                    source: .ar, notes: notes)
        store.updateLocation(ref) { $0.measurements.append(m) }
        onSaved()
        dismiss()
    }
}

/// Lists every location across projects for choosing a save destination.
struct LocationPickerRows: View {
    @Binding var selection: LocationRef?
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        if store.allLocationRefs.isEmpty {
            Text("A new location will be created in “\(ProjectStore.quickScanProjectName)”.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        ForEach(store.allLocationRefs, id: \.location.id) { pair in
            let ref = LocationRef(projectID: pair.project.id, locationID: pair.location.id)
            Button {
                selection = ref
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(pair.location.name).foregroundStyle(Theme.textPrimary)
                        Text(pair.project.name).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if selection == ref { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
        }
        if !store.allLocationRefs.isEmpty {
            Button {
                selection = nil
            } label: {
                HStack {
                    Text("New location in “\(ProjectStore.quickScanProjectName)”")
                    Spacer()
                    if selection == nil { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                }
            }
        }
    }
}
