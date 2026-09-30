import PhotosUI
import SwiftUI
import UIKit

/// SHOT 01, SHOT 02… with a top-down overview. Tapping a shot highlights it on the plan.
struct ShotListView: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @State private var selectedShot: UUID?
    @State private var editingShot: UUID?

    private var location: Location? { store.location(ref) }

    var body: some View {
        if let location {
            content(location)
        } else {
            EmptyStateView(systemImage: "film", title: "Location not found", message: "").fsScreen()
        }
    }

    private func content(_ location: Location) -> some View {
        let shots = location.shots.sorted { $0.number < $1.number }
        return VStack(spacing: 0) {
            overview(location, shots: shots)
                .frame(height: 280)
                .background(Theme.surface)
            if shots.count > 1 {
                shotSwitcher(shots)
            }
            List {
                if shots.isEmpty {
                    EmptyStateView(systemImage: "film.stack", title: "No shots yet",
                                   message: "Add a shot, then place the camera and subject on the plan. Or turn a saved camera position into a shot.")
                        .listRowBackground(Color.clear)
                }
                ForEach(shots) { shot in
                    ShotRow(shot: shot, ref: ref, selected: selectedShot == shot.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedShot = shot.id }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.updateLocation(ref) { $0.shots.removeAll { $0.id == shot.id } }
                            } label: { Label("Delete", systemImage: "trash") }
                            Button { editingShot = shot.id } label: { Label("Edit", systemImage: "pencil") }
                                .tint(Theme.info)
                        }
                        .listRowBackground(selectedShot == shot.id ? Theme.surfaceRaised : Theme.surface)
                }
                if !location.cameraPositions.isEmpty {
                    Section("Create shot from camera position") {
                        ForEach(location.cameraPositions) { cam in
                            Button { addShot(from: cam) } label: {
                                Label("\(cam.name) · \(Optics.formatFocal(cam.rig.focalLength))", systemImage: "plus.circle")
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped)
        }
        .fsScreen()
        .navigationTitle("Shots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addShot(from: nil) } label: { Label("Add Shot", systemImage: "plus") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.open(.plan(ref)) } label: { Label("Plan", systemImage: "map") }
            }
        }
        .sheet(item: Binding(get: { editingShot.map(IdentifiedUUID.init) }, set: { editingShot = $0?.id })) { item in
            ShotEditorSheet(ref: ref, shotID: item.id)
        }
    }

    private func overview(_ location: Location, shots: [Shot]) -> some View {
        let plan = location.primaryScan.flatMap { store.floorPlan(ref, scanID: $0.id) } ?? .empty
        var overlay = PlanOverlay()
        overlay.showDimensions = false
        for shot in shots {
            overlay.cameras.append(PlanCameraMarker(id: shot.id, label: String(format: "S%02d", shot.number), rig: shot.rig,
                                                    isShot: true, selected: selectedShot == shot.id,
                                                    reach: max(1.5, (shot.subjectDistance ?? 3) + 0.8)))
            if let s = shot.subject {
                overlay.subjects.append(PlanSubjectMarker(id: shot.id, label: String(format: "S%02d", shot.number),
                                                          point: s, selected: selectedShot == shot.id))
            }
        }
        if let north = location.primaryScan?.northOffset { overlay.northWorldBearing = 360 - north }
        return FloorPlanCanvas(plan: plan, overlay: overlay, style: .full)
            .onTapGesture { router.open(.plan(ref)) }
    }

    private func shotSwitcher(_ shots: [Shot]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shots) { shot in
                    TagChip(text: shot.code, selected: selectedShot == shot.id) { selectedShot = shot.id }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
    }

    private func addShot(from camera: CameraPosition?) {
        guard let location else { return }
        var rig = camera?.rig ?? location.shots.last?.rig ?? CameraRig()
        if camera == nil, let plan = location.primaryScan.flatMap({ store.floorPlan(ref, scanID: $0.id) }), !plan.isEmpty {
            rig.position = plan.interiorCentroid
        }
        let shot = Shot(number: location.nextShotNumber, rig: rig, cameraPositionID: camera?.id,
                        scanID: camera?.scanID ?? location.primaryScan?.id)
        store.updateLocation(ref) { $0.shots.append(shot) }
        selectedShot = shot.id
        editingShot = shot.id
    }
}

struct IdentifiedUUID: Identifiable {
    let id: UUID
}

struct ShotRow: View {
    let shot: Shot
    let ref: LocationRef
    var selected: Bool
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Theme.surfaceRaised
                if let photoID = shot.photoID, let photo = store.location(ref)?.photos.first(where: { $0.id == photoID }) {
                    StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 200)
                } else {
                    Text(String(format: "%02d", shot.number)).font(.fsValue).foregroundStyle(Theme.info)
                }
            }
            .frame(width: 64, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(shot.code)\(shot.title.isEmpty ? "" : " · \(shot.title)")").font(.headline)
                Text("\(Optics.formatFocal(shot.rig.focalLength)) · \(shot.rig.sensor.name) · h \(UnitsFormatter.distance(shot.rig.height))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                if let d = shot.subjectDistance {
                    Text("Subject \(UnitsFormatter.distance(d)) · frame \(UnitsFormatter.distance(Optics.frameSize(atDistance: d, size: shot.rig.imageArea.width, focalLength: shot.rig.focalLength))) wide")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                if !shot.notes.isEmpty {
                    Text(shot.notes).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Name, notes and reference photo for a shot (used inside forms).
struct ShotFields: View {
    let shot: Shot
    let ref: LocationRef
    var update: (@escaping (inout Shot) -> Void) -> Void
    @EnvironmentObject private var store: ProjectStore
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        Section(shot.code) {
            TextField("Title (e.g. Wide master)", text: Binding(get: { shot.title }, set: { v in update { $0.title = v } }))
            TextField("Notes", text: Binding(get: { shot.notes }, set: { v in update { $0.notes = v } }), axis: .vertical)
                .lineLimit(2...6)
            if let d = shot.subjectDistance {
                LabeledContent("Camera → subject", value: UnitsFormatter.distance(d))
            }
            SliderRow(title: "Subject eye height", value: Binding(get: { shot.subjectHeight }, set: { v in update { $0.subjectHeight = v } }),
                      range: 0.3...2.2, step: 0.05, format: { UnitsFormatter.distance($0) })
        }
        Section("Reference photo") {
            let photos = store.location(ref)?.photos ?? []
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(photos) { photo in
                            StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 200)
                                .frame(width: 72, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(shot.photoID == photo.id ? Theme.accent : .clear, lineWidth: 3))
                                .onTapGesture { update { $0.photoID = photo.id } }
                        }
                    }
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Import from library", systemImage: "photo.on.rectangle")
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = UIImage(data: data)?.downsampled(maxPixel: 3000)?.jpegData(compressionQuality: 0.85),
                   let photo = store.addPhoto(jpeg, to: ref, source: .library, caption: shot.code) {
                    update { $0.photoID = photo.id }
                }
                pickerItem = nil
            }
        }
    }
}

struct ShotEditorSheet: View {
    let ref: LocationRef
    let shotID: UUID
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let shot = store.location(ref)?.shots.first(where: { $0.id == shotID }) {
                    ShotFields(shot: shot, ref: ref, update: update)
                    CameraRigForm(rig: Binding(get: { shot.rig }, set: { v in update { $0.rig = v } }),
                                  subjectDistance: shot.subjectDistance,
                                  ceilingHeight: store.location(ref)?.primaryScan?.stats.ceilingHeight)
                }
            }
            .fsScreen()
            .navigationTitle("Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func update(_ mutate: @escaping (inout Shot) -> Void) {
        store.updateLocation(ref) { loc in
            if let i = loc.shots.firstIndex(where: { $0.id == shotID }) { mutate(&loc.shots[i]) }
        }
    }
}
