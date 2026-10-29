import SceneKit
import SwiftUI
import UIKit

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
    @State private var rigLightsOn = true

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
                            .font(.fsCaptionStrong)
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
            updateMarkers()
        }
        .onChange(of: orbit) { _, _ in updateMarkers(); updateRigLights(); updatePeople() }
        .onChange(of: location?.characters) { _, _ in updatePeople() }
        .onChange(of: location?.display) { _, _ in applyDisplay() }
        .onChange(of: sunOn) { _, _ in updateSun() }
        .onChange(of: location?.lightFixtures) { _, _ in updateRigLights() }
        .onChange(of: rigLightsOn) { _, _ in updateRigLights() }
        .onChange(of: model.loaded) { _, _ in applyDisplay() }
        .onChange(of: sunMinutes) { _, _ in updateSun() }
    }

    private func setup() {
        guard let location, let scan = location.primaryScan else { return }
        let plan = store.floorPlan(ref, scanID: scan.id)
        model.load(scan: scan, ref: ref, floorY: plan?.floorY ?? 0, plan: plan)
        model.applyAlignment(scan.alignmentValue)
        selectedID = initialCameraID ?? viewpoints.first?.id
        if let vp = selected { model.apply(vp) }
        orbit = viewpoints.isEmpty
        updateMarkers()
        updateRigLights()
        updatePeople()
        applyDisplay()
    }

    private func updateMarkers() {
        let showLabels = location?.displaySettings.showsLabels(.cameras) ?? true
        model.setMarkers(viewpoints: viewpoints, selected: selected?.id, showLabels: showLabels, hideSelected: !orbit,
                         hiddenSubjects: !(location?.previsCharacters.isEmpty ?? true))
    }

    private func updatePeople() {
        let sid = location?.primaryScan?.id
        model.setPeople((location?.previsCharacters ?? []).filter { $0.scanID == nil || $0.scanID == sid }, selected: nil,
                        showLabels: orbit && (location?.displaySettings.showsLabels(.people) ?? true))
    }

    private func applyDisplay() {
        guard let location else { return }
        model.applyDisplay(location.displaySettings)
        if model.loaded { model.applyAlignment(location.primaryScan?.alignmentValue ?? .identity) }
    }

    private func updateRigLights() {
        let sid = location?.primaryScan?.id
        let display = location?.displaySettings ?? SceneDisplay()
        let lights = rigLightsOn && !display.isHidden(group: .lights)
            ? (location?.lightFixtures ?? []).filter { $0.scanID == nil || $0.scanID == sid } : []
        // Looking through the camera: no beam volumes or labels in the frame.
        model.setLights(lights, selected: nil, showLabels: false, showBeams: orbit, hideGrip: display.isHidden(group: .grip))
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
                        TagChip(text: vp.label, selected: !orbit && selected?.id == vp.id) {
                            orbit = false
                            selectedID = vp.id
                        }
                    }
                }
            }
            if !(location?.lightFixtures.isEmpty ?? true) {
                OverlayButton(systemImage: rigLightsOn ? "lightbulb.fill" : "lightbulb", tint: rigLightsOn ? Theme.sun : .white, size: 44) {
                    rigLightsOn.toggle()
                }
                .accessibilityLabel(rigLightsOn ? "Hide lighting units" : "Show lighting units")
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
                .font(.fsCaption)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.6), in: Rectangle())
    }

    private func compactSlider(_ title: String, value: Double, range: ClosedRange<Double>,
                               format: @escaping (Double) -> String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.fsLabel).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(value)).font(.fsMono)
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
