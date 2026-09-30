import SwiftUI

/// Export hub: location package, whole-project package, raw scan formats, and project backup.
struct ExportView: View {
    let projectID: UUID?
    let locationRef: LocationRef?

    @EnvironmentObject private var store: ProjectStore
    @AppStorage("exportOptions") private var optionsData: Data = Data()
    @State private var options = ExportOptions()
    @State private var selectedProject: UUID?
    @State private var selectedLocation: LocationRef?
    @State private var busy = false
    @State private var share: SharedFile?
    @State private var error: String?
    @State private var showUnrealInfo = false

    var body: some View {
        Form {
            Section("What to export") {
                Picker("Project", selection: $selectedProject) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(store.recentProjects) { Text($0.name).tag(Optional($0.id)) }
                }
                if let pid = selectedProject, let project = store.project(pid) {
                    Picker("Location", selection: $selectedLocation) {
                        Text("Whole project").tag(LocationRef?.none)
                        ForEach(project.locations) { loc in
                            Text(loc.name).tag(Optional(LocationRef(projectID: pid, locationID: loc.id)))
                        }
                    }
                }
                if let ref = selectedLocation, let loc = store.location(ref) {
                    if let scan = loc.primaryScan {
                        LabeledContent("Scan", value: "\(scan.name) · \(scan.kind.label)")
                    } else {
                        Text("This location has no scan — the package will contain photos, notes, measurements and cameras only.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Section {
                Toggle("Unreal Engine preset", isOn: $options.unrealPreset)
                Button { showUnrealInfo = true } label: { Label("What does the Unreal export contain?", systemImage: "info.circle") }
            } header: {
                Text("Unreal Engine")
            } footer: {
                Text("Adds an Unreal folder: centimetre/Z-up OBJ, CineCamera CSV (positions, rotation, focal length, filmback) and an import guide. GLB is the recommended file for Unreal 5.1+.")
            }

            Section("3D formats") {
                Toggle("USDZ (FrameScout, metres, Y-up)", isOn: $options.usdz)
                Toggle("USDA (text USD)", isOn: $options.usda)
                Toggle("GLB / glTF 2.0", isOn: $options.glb)
                Toggle("OBJ + MTL", isOn: $options.obj)
                Toggle("Apple RoomPlan USDZ (single-room scans)", isOn: $options.includeRoomPlanNative)
            }

            Section("Content") {
                Toggle("Furniture / objects", isOn: $options.includeFurniture)
                Toggle("Estimated ceiling (room scans)", isOn: $options.includeCeiling)
                Toggle("Camera positions & shots as cameras (GLB)", isOn: $options.includeCameras)
                Toggle("Reference photos", isOn: $options.includePhotos)
            }

            Section {
                Button(action: exportPackage) {
                    Label(selectedLocation == nil ? "Export Project Package (ZIP)" : "Export Location Package (ZIP)",
                          systemImage: "shippingbox")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .disabled(busy || selectedProject == nil)

                Button(action: exportBackup) {
                    Label("Export Project Backup (re-importable)", systemImage: "externaldrive")
                }
                .disabled(busy || selectedProject == nil)
            } footer: {
                Text("Packages are saved in Files › On My iPhone › FrameScout › Exports and can be shared via AirDrop, Mail or Save to Files. Backups can be imported on another device from the home screen menu.")
            }

            if busy {
                Section { HStack { ProgressView(); Text("Building export…") } }
            }
            if let error {
                Section { Text(error).foregroundStyle(Theme.danger) }
            }

            Section("Package layout") {
                Text("""
                LOCATION_NAME/
                  Scan/  location.usdz · location.glb · location.obj · Unreal/
                  Photos/
                  Measurements/  measurements.json · .csv
                  Camera_Positions/  camera_positions.json · shots.json
                  Notes/  notes.txt
                  Metadata/  metadata.json · location.json · floor_plan.json
                """)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .fsScreen()
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { file in ShareSheet(items: [file.url]) }
        .sheet(isPresented: $showUnrealInfo) { UnrealInfoSheet() }
        .onAppear {
            if let decoded = try? JSONDecoder().decode(ExportOptions.self, from: optionsData) { options = decoded }
            selectedProject = projectID ?? locationRef?.projectID ?? store.recentProjects.first?.id
            selectedLocation = locationRef
        }
        .onChange(of: options) { _, value in
            optionsData = (try? JSONEncoder().encode(value)) ?? Data()
        }
        .onChange(of: selectedProject) { _, pid in
            if selectedLocation?.projectID != pid { selectedLocation = nil }
        }
    }

    private func exportPackage() {
        guard let pid = selectedProject, let project = store.project(pid) else { return }
        store.flush()
        busy = true
        error = nil
        let options = self.options
        let locationRef = selectedLocation
        let location = locationRef.flatMap { store.location($0) }
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    if let location, let locationRef {
                        return try ExportService.buildLocationPackage(project: project, location: location,
                                                                      ref: locationRef, options: options)
                    }
                    return try ExportService.buildProjectPackage(project: project, options: options)
                }.value
                share = SharedFile(url: url)
            } catch {
                self.error = "Export failed: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func exportBackup() {
        guard let pid = selectedProject, let project = store.project(pid) else { return }
        store.flush()
        busy = true
        error = nil
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try ExportService.buildProjectBackup(project: project)
                }.value
                share = SharedFile(url: url)
            } catch {
                self.error = "Backup failed: \(error.localizedDescription)"
            }
            busy = false
        }
    }
}

struct UnrealInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        Text("What gets exported").font(.headline)
                        Text("• **Geometry** — room scans export RoomPlan's parametric model: walls with real door/window openings cut out, floor polygons, glass panes, door leaves and furniture boxes. Mesh scans export the raw LiDAR surface split by type (walls, floor, ceiling, seats…).")
                        Text("• **Scale** — true metres. GLB/USD carry units so Unreal converts to centimetres automatically.")
                        Text("• **Orientation** — Y-up for GLB/USD/OBJ (Unreal converts). The Unreal-preset OBJ is already Z-up, X-forward, centimetres. The compass bearing of the scan is in metadata.json.")
                        Text("• **Hierarchy** — Walls / Doors / Windows / Floors / Furniture groups with sequential names (Wall_01…). Metadata such as sizes travels as glTF extras / USD customData.")
                        Text("• **Materials** — flat PBR colours per surface type. RoomPlan and ARKit do not capture textures, so there are no photo textures; reference photos are included separately.")
                        Text("• **Cameras** — camera positions and shots become glTF cameras with correct field of view, plus a CSV with CineCameraActor values (location, rotation, focal length, filmback).")
                    }
                    Group {
                        Text("Recommended workflow").font(.headline)
                        Text("1. AirDrop or save the ZIP to your computer and unzip.\n2. In Unreal 5.1+, drag **Scan/location.glb** into the Content Browser (or use Import Into Level to keep the hierarchy and cameras).\n3. Or enable the **USD Importer** plugin and open **location.usdz / .usda** in a USD Stage.\n4. For older engines use **Scan/Unreal/location_unreal_cm_zup.obj** with Import Uniform Scale 1.0.\n5. Place CineCameraActors from **cameras_unreal.csv** if you imported a format without cameras.")
                    }
                    Group {
                        Text("Known limitations").font(.headline)
                        Text("• iOS has no FBX writer and no Unreal SDK, so FrameScout produces standard interchange files rather than a .uasset/.umap.\n• RoomPlan doesn't detect ceilings; an estimated flat ceiling can be added in export options.\n• Very large mesh scans (> 1M triangles) are best decimated in a DCC before import.")
                    }
                }
                .font(.subheadline)
                .padding()
            }
            .fsScreen()
            .navigationTitle("Unreal Engine Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
