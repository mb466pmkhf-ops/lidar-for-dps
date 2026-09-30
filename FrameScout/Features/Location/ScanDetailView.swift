import SwiftUI

struct ScanDetailView: View {
    let ref: LocationRef
    let scanID: UUID
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = VirtualSceneModel()
    @State private var confirmDelete = false

    private var scan: ScanRecord? { store.location(ref)?.scans.first { $0.id == scanID } }

    var body: some View {
        if let scan {
            content(scan)
        } else {
            EmptyStateView(systemImage: "cube.transparent", title: "Scan not found", message: "").fsScreen()
        }
    }

    private func content(_ scan: ScanRecord) -> some View {
        let s = scan.stats
        return Form {
            Section {
                ZStack {
                    SceneKitContainer(model: preview, orbit: true)
                    if !preview.loaded {
                        if let error = preview.error { Text(error).font(.caption).foregroundStyle(Theme.danger) } else { ProgressView() }
                    }
                }
                .frame(height: 300)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Drag to orbit, pinch to zoom. This is the geometry that will be exported.")
            }

            Section("Figures") {
                LabeledContent("Type", value: scan.kind.label)
                LabeledContent("Captured", value: scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Room", value: UnitsFormatter.dimensions(s.width, s.length))
                LabeledContent("Floor area", value: UnitsFormatter.area(s.floorArea) + (s.floorAreaIsEstimate ? " (est.)" : ""))
                LabeledContent("Ceiling", value: UnitsFormatter.distance(s.ceilingHeight))
                if scan.kind == .room {
                    LabeledContent("Walls", value: "\(s.wallCount)")
                    LabeledContent("Doors", value: "\(s.doorCount)")
                    LabeledContent("Windows", value: "\(s.windowCount)")
                    LabeledContent("Openings", value: "\(s.openingCount)")
                    LabeledContent("Floors", value: "\(s.floorCount)")
                    LabeledContent("Objects", value: "\(s.objectCount)")
                    if let c = s.completeness { LabeledContent("Completeness (est.)", value: "\(Int(c * 100))%") }
                    LabeledContent("Segments", value: "\(scan.segmentCount)")
                } else {
                    LabeledContent("Triangles", value: "\(s.meshFaceCount)")
                    LabeledContent("Vertices", value: "\(s.meshVertexCount)")
                }
                LabeledContent("North (compass)", value: scan.northOffset.map { String(format: "%.0f°", $0) } ?? "—")
                LabeledContent("Device", value: scan.deviceModel)
            }

            if !s.doors.isEmpty || !s.windows.isEmpty {
                Section("Openings") {
                    ForEach(Array(s.doors.enumerated()), id: \.offset) { i, d in
                        LabeledContent("Door \(i + 1)", value: "\(UnitsFormatter.distance(d.width)) × \(UnitsFormatter.distance(d.height))")
                    }
                    ForEach(Array(s.windows.enumerated()), id: \.offset) { i, w in
                        LabeledContent("Window \(i + 1)", value: "\(UnitsFormatter.distance(w.width)) × \(UnitsFormatter.distance(w.height)) · sill \(UnitsFormatter.distance(w.sillHeight))")
                    }
                }
            }

            Section {
                TextField("Scan name", text: Binding(get: { scan.name }, set: { v in updateScan { $0.name = v } }))
                TextField("Notes", text: Binding(get: { scan.notes }, set: { v in updateScan { $0.notes = v } }), axis: .vertical)
                if store.location(ref)?.primaryScan?.id != scan.id {
                    Button("Make primary scan") { store.updateLocation(ref) { $0.primaryScanID = scan.id } }
                }
                Button { router.open(.export(projectID: ref.projectID, location: ref)) } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                Button("Delete scan", role: .destructive) { confirmDelete = true }
            }
        }
        .fsScreen()
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !preview.loaded else { return }
            preview.load(scan: scan, ref: ref, floorY: store.floorPlan(ref, scanID: scan.id)?.floorY ?? 0)
        }
        .confirmationDialog("Delete this scan? Photos, notes and cameras are kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) {
                store.deleteScan(scanID, from: ref)
                dismiss()
            }
        }
    }

    private func updateScan(_ mutate: @escaping (inout ScanRecord) -> Void) {
        store.updateLocation(ref) { loc in
            if let i = loc.scans.firstIndex(where: { $0.id == scanID }) { mutate(&loc.scans[i]) }
        }
    }
}
