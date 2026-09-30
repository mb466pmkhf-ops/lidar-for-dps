import SceneKit
import SwiftUI
import UIKit

/// Builds SceneKit content from FrameScout's format-neutral geometry.
enum SceneKitBuilder {
    static func node(for geometry: SceneGeometry) -> SCNNode {
        func build(_ n: SceneNode) -> SCNNode {
            let node = SCNNode()
            node.name = n.name
            node.simdPosition = n.translation
            if let mesh = n.mesh, !mesh.isEmpty {
                node.geometry = scnGeometry(mesh)
            }
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

    /// Stand-in actor: capsule with a head-height marker.
    static func subjectNode(height: Double) -> SCNNode {
        let h = CGFloat(max(0.5, height + 0.1))
        let capsule = SCNCapsule(capRadius: 0.2, height: h)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 1, green: 0.36, blue: 0.32, alpha: 1)
        capsule.materials = [m]
        let node = SCNNode(geometry: capsule)
        node.position = SCNVector3(0, Float(h / 2), 0)
        let holder = SCNNode()
        holder.addChildNode(node)
        return holder
    }

    static func cameraMarker(color: UIColor) -> SCNNode {
        let box = SCNBox(width: 0.12, height: 0.12, length: 0.22, chamferRadius: 0.01)
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .constant
        box.materials = [m]
        return SCNNode(geometry: box)
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

@MainActor
final class VirtualSceneModel: ObservableObject {
    @Published var loaded = false
    @Published var error: String?
    let scene = SCNScene()
    let panNode = SCNNode()
    let tiltNode = SCNNode()
    let cameraNode = SCNNode()
    let orbitCameraNode = SCNNode()
    let sunNode = SCNNode()
    private let markers = SCNNode()
    private(set) var floorY: Double = 0
    private(set) var roomCentre = SIMD3<Float>(0, 1, 0)

    init() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.03
        cameraNode.camera?.zFar = 500
        cameraNode.camera?.projectionDirection = .horizontal
        tiltNode.addChildNode(cameraNode)
        panNode.addChildNode(tiltNode)
        scene.rootNode.addChildNode(panNode)

        orbitCameraNode.camera = SCNCamera()
        orbitCameraNode.camera?.zNear = 0.05
        orbitCameraNode.camera?.zFar = 500
        scene.rootNode.addChildNode(orbitCameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        scene.rootNode.addChildNode(ambient)

        sunNode.light = SCNLight()
        sunNode.light?.type = .directional
        sunNode.light?.intensity = 900
        sunNode.light?.castsShadow = true
        sunNode.light?.shadowMode = .deferred
        sunNode.light?.shadowColor = UIColor.black.withAlphaComponent(0.6)
        sunNode.simdPosition = SIMD3(3, 10, 4)
        sunNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(sunNode)
        scene.rootNode.addChildNode(markers)
        scene.background.contents = UIColor(white: 0.05, alpha: 1)
    }

    func load(scan: ScanRecord, ref: LocationRef, floorY: Double) {
        self.floorY = floorY
        Task {
            do {
                let geometry = try await Task.detached(priority: .userInitiated) {
                    try ScanAssets.geometry(for: scan, ref: ref, options: .init(includeCeiling: false, includeObjects: true))
                }.value
                let node = SceneKitBuilder.node(for: geometry)
                scene.rootNode.addChildNode(node)
                let (lo, hi) = node.boundingBox
                roomCentre = SIMD3(Float(lo.x + hi.x) / 2, Float(floorY) + 1, Float(lo.z + hi.z) / 2)
                let span = max(Float(hi.x - lo.x), Float(hi.z - lo.z), 3)
                orbitCameraNode.simdPosition = roomCentre + SIMD3(0, span * 1.1, span * 0.9)
                orbitCameraNode.simdLook(at: roomCentre)
                loaded = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func apply(_ vp: VirtualViewpoint) {
        let rig = vp.rig
        panNode.simdPosition = SIMD3(Float(rig.position.x), Float(floorY + rig.height), Float(rig.position.z))
        panNode.simdEulerAngles = SIMD3(0, Float(-rig.pan * .pi / 180), 0)
        tiltNode.simdEulerAngles = SIMD3(Float(rig.tilt * .pi / 180), 0, 0)
        cameraNode.camera?.fieldOfView = CGFloat(rig.horizontalFOV)
    }

    func setMarkers(viewpoints: [VirtualViewpoint], selected: UUID?) {
        markers.childNodes.forEach { $0.removeFromParentNode() }
        for vp in viewpoints {
            if vp.id != selected {
                let m = SceneKitBuilder.cameraMarker(color: vp.kind == .shot ? UIColor.systemBlue : UIColor.systemYellow)
                m.simdPosition = SIMD3(Float(vp.rig.position.x), Float(floorY + vp.rig.height), Float(vp.rig.position.z))
                m.simdEulerAngles = SIMD3(0, Float(-vp.rig.pan * .pi / 180), 0)
                markers.addChildNode(m)
            }
            if let s = vp.subject {
                let actor = SceneKitBuilder.subjectNode(height: vp.subjectHeight)
                actor.simdPosition = SIMD3(Float(s.x), Float(floorY), Float(s.z))
                markers.addChildNode(actor)
            }
        }
    }

    /// Points the directional light from the sun's world direction.
    func setSun(worldBearing: Double?, elevation: Double?) {
        guard let worldBearing, let elevation else {
            sunNode.simdPosition = roomCentre + SIMD3(3, 10, 4)
            sunNode.simdLook(at: roomCentre)
            sunNode.light?.intensity = 900
            return
        }
        let b = worldBearing * .pi / 180, e = max(elevation, 0) * .pi / 180
        let towardsSun = SIMD3<Float>(Float(sin(b) * cos(e)), Float(sin(e)), Float(-cos(b) * cos(e)))
        sunNode.simdPosition = roomCentre + towardsSun * 20
        sunNode.simdLook(at: roomCentre)
        sunNode.light?.intensity = elevation > 0 ? CGFloat(400 + 1400 * sin(e)) : 0
    }
}

struct SceneKitContainer: UIViewRepresentable {
    let model: VirtualSceneModel
    var orbit: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = model.scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.pointOfView = orbit ? model.orbitCameraNode : model.cameraNode
        view.allowsCameraControl = orbit
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let pov = orbit ? model.orbitCameraNode : model.cameraNode
        if view.pointOfView !== pov { view.pointOfView = pov }
        view.allowsCameraControl = orbit
    }
}

/// "Can I get a 32 mm wide shot from here?" — frames the scanned room through a virtual cinema camera.
struct VirtualCameraView: View {
    let ref: LocationRef
    let initialCameraID: UUID?

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = VirtualSceneModel()
    @State private var selectedID: UUID?
    @State private var orbit = false
    @State private var sunOn = false
    @State private var sunMinutes: Double = 16 * 60
    @State private var sunDate = Date()

    private var location: Location? { store.location(ref) }

    private var viewpoints: [VirtualViewpoint] {
        guard let location else { return [] }
        let cams = location.cameraPositions.map {
            VirtualViewpoint(id: $0.id, kind: .camera, label: $0.name, rig: $0.rig, subject: nil, subjectHeight: 1.75)
        }
        let shots = location.shots.sorted { $0.number < $1.number }.map {
            VirtualViewpoint(id: $0.id, kind: .shot, label: $0.code, rig: $0.rig, subject: $0.subject, subjectHeight: $0.subjectHeight)
        }
        return cams + shots
    }

    private var selected: VirtualViewpoint? {
        viewpoints.first { $0.id == selectedID } ?? viewpoints.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if orbit || selected == nil {
                SceneKitContainer(model: model, orbit: true).ignoresSafeArea()
            } else if let vp = selected {
                let area = vp.rig.imageArea
                SceneKitContainer(model: model, orbit: false)
                    .aspectRatio(area.width / area.height, contentMode: .fit)
                    .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1.5))
                    .overlay(alignment: .topLeading) {
                        Text("\(vp.label) · \(vp.rig.lensSummary) · H \(Optics.formatAngle(vp.rig.horizontalFOV))")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.accent)
                            .padding(6)
                    }
            }
            if !model.loaded {
                if let error = model.error {
                    RequirementBanner(title: "Could not load scan", message: error).padding()
                } else {
                    ProgressView("Loading scan…").tint(.white)
                }
            }
            VStack {
                topBar
                Spacer()
                if selected != nil && !orbit { adjustPanel }
            }
            .padding(10)
        }
        .statusBarHidden()
        .onAppear(perform: setup)
        .onChange(of: selected) { _, vp in
            if let vp { model.apply(vp) }
            model.setMarkers(viewpoints: viewpoints, selected: vp?.id)
        }
        .onChange(of: sunOn) { _, _ in updateSun() }
        .onChange(of: sunMinutes) { _, _ in updateSun() }
    }

    private func setup() {
        guard let location, let scan = location.primaryScan else { return }
        let floorY = store.floorPlan(ref, scanID: scan.id)?.floorY ?? 0
        model.load(scan: scan, ref: ref, floorY: floorY)
        selectedID = initialCameraID ?? viewpoints.first?.id
        if let vp = selected { model.apply(vp) }
        model.setMarkers(viewpoints: viewpoints, selected: selected?.id)
        orbit = viewpoints.isEmpty
    }

    private var sunAvailable: Bool {
        location?.coordinate != nil && location?.primaryScan?.northOffset != nil
    }

    private func updateSun() {
        guard sunOn, let location, let coordinate = location.coordinate, let north = location.primaryScan?.northOffset else {
            model.setSun(worldBearing: nil, elevation: nil)
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let date = calendar.startOfDay(for: sunDate).addingTimeInterval(sunMinutes * 60)
        let sun = SolarCalculator.position(date: date, latitude: coordinate.latitude, longitude: coordinate.longitude)
        model.setSun(worldBearing: sun.azimuth - north, elevation: sun.elevation)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            OverlayButton(systemImage: "xmark", size: 44) { dismiss() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    TagChip(text: "ORBIT", selected: orbit) { orbit = true }
                    ForEach(viewpoints) { vp in
                        TagChip(text: vp.label.uppercased(), selected: !orbit && selected?.id == vp.id) {
                            orbit = false
                            selectedID = vp.id
                        }
                    }
                }
            }
            if sunAvailable {
                OverlayButton(systemImage: sunOn ? "sun.max.fill" : "sun.max", tint: sunOn ? Theme.sun : .white, size: 44) {
                    sunOn.toggle()
                }
            }
        }
    }

    private var adjustPanel: some View {
        VStack(spacing: 8) {
            if let vp = selected {
                LensPicker(focalLength: Binding(get: { vp.rig.focalLength }, set: { v in update(vp) { $0.focalLength = v } }))
                HStack(spacing: 14) {
                    compactSlider("H", value: vp.rig.height, range: 0.1...4, format: { UnitsFormatter.distance($0) }) { v in update(vp) { $0.height = v } }
                    compactSlider("PAN", value: vp.rig.pan, range: 0...360, format: { String(format: "%.0f°", $0) }) { v in update(vp) { $0.pan = v } }
                    compactSlider("TILT", value: vp.rig.tilt, range: -60...60, format: { String(format: "%+.0f°", $0) }) { v in update(vp) { $0.tilt = v } }
                }
            }
            if sunOn {
                HStack {
                    Image(systemName: "sun.max").foregroundStyle(Theme.sun)
                    Slider(value: $sunMinutes, in: 0...1439, step: 5)
                    Text(String(format: "%02d:%02d", Int(sunMinutes) / 60, Int(sunMinutes) % 60)).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func compactSlider(_ title: String, value: Double, range: ClosedRange<Double>,
                               format: @escaping (Double) -> String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.fsLabel).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit())
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: set), in: range)
        }
    }

    private func update(_ vp: VirtualViewpoint, _ mutate: @escaping (inout CameraRig) -> Void) {
        store.updateLocation(ref) { loc in
            switch vp.kind {
            case .camera:
                if let i = loc.cameraPositions.firstIndex(where: { $0.id == vp.id }) { mutate(&loc.cameraPositions[i].rig) }
            case .shot:
                if let i = loc.shots.firstIndex(where: { $0.id == vp.id }) { mutate(&loc.shots[i].rig) }
            }
        }
    }
}
