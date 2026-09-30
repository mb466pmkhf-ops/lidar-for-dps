import PhotosUI
import SwiftUI
import UIKit

struct LocationDetailView: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = LocationProvider()
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var showCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        if let location = store.location(ref) {
            content(location)
        } else {
            EmptyStateView(systemImage: "mappin.slash", title: "Location not found", message: "It may have been deleted.")
                .fsScreen()
        }
    }

    private func content(_ location: Location) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(location)
                toolGrid(location)
                keyFigures(location)
                planCard(location)
                tagsCard(location)
                photosCard(location)
                measurementsCard(location)
                camerasCard(location)
                notesCard(location)
                scansCard(location)
            }
            .padding()
        }
        .fsScreen()
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = location.name; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button { router.open(.export(projectID: ref.projectID, location: ref)) } label: {
                        Label("Export Location…", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Location", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Rename Location", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.updateLocation(ref) { $0.name = name } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this location, its scans and photos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteLocation(ref)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            SystemCameraPicker { image in
                if let jpeg = image.downsampled(maxPixel: 4000)?.jpegData(compressionQuality: 0.85) {
                    store.addPhoto(jpeg, to: ref, source: .camera)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in importPhotos(items) }
    }

    // MARK: Sections

    private func header(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = store.project(ref.projectID) {
                Text(project.name.uppercased()).font(.fsLabel).tracking(1.2).foregroundStyle(Theme.accent)
            }
            TextField("Address / general location", text: store.binding(for: ref).address, axis: .vertical)
                .font(.subheadline)
            HStack(spacing: 12) {
                Label(location.dateScanned.map { "Scanned \(UnitsFormatter.shortDate($0))" } ?? "Not scanned yet",
                      systemImage: "calendar")
                if let c = location.coordinate {
                    Label(String(format: "%.4f, %.4f", c.latitude, c.longitude), systemImage: "location")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            Button {
                Task {
                    if let fix = await locator.currentFix() {
                        store.updateLocation(ref) { loc in
                            loc.coordinate = fix.coordinate
                            if loc.address.isEmpty, let a = fix.address { loc.address = a }
                            if let tz = fix.timeZoneIdentifier { loc.timeZoneIdentifier = tz }
                        }
                    }
                }
            } label: {
                Label(locator.isLocating ? "Locating…" : (location.coordinate == nil ? "Use current GPS position" : "Update GPS position"),
                      systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
            }
            .disabled(locator.isLocating)
            if let error = locator.lastError {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    private func toolGrid(_ location: Location) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            SmallTool(title: "Scan", symbol: "viewfinder.circle", disabled: !DeviceCapabilities.hasLiDAR) {
                router.start(.scan(CaptureTarget(ref)))
            }
            SmallTool(title: "Measure", symbol: "ruler", disabled: !DeviceCapabilities.supportsWorldTracking) {
                router.start(.measure(CaptureTarget(ref)))
            }
            SmallTool(title: "Viewfinder", symbol: "camera.viewfinder", disabled: !DeviceCapabilities.hasCamera) {
                router.start(.viewfinder(CaptureTarget(ref)))
            }
            SmallTool(title: "Plan", symbol: "map") { router.open(.plan(ref)) }
            SmallTool(title: "Shots", symbol: "film") { router.open(.shots(ref)) }
            SmallTool(title: "Sun", symbol: "sun.max") { router.open(.sun(ref)) }
            SmallTool(title: "3D View", symbol: "cube", disabled: location.primaryScan == nil) {
                router.start(.virtualCamera(ref, cameraID: nil))
            }
            SmallTool(title: "Notes", symbol: "note.text") { router.open(.notes(ref)) }
            SmallTool(title: "Export", symbol: "square.and.arrow.up") {
                router.open(.export(projectID: ref.projectID, location: ref))
            }
        }
    }

    @ViewBuilder
    private func keyFigures(_ location: Location) -> some View {
        if let s = location.primaryScan?.stats {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Key figures", systemImage: "ruler")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatView(label: "Room", value: UnitsFormatter.dimensions(s.width, s.length))
                        StatView(label: "Floor area", value: UnitsFormatter.area(s.floorArea), detail: s.floorAreaIsEstimate ? "estimated" : nil)
                    }
                    GridRow {
                        StatView(label: "Ceiling", value: UnitsFormatter.distance(s.ceilingHeight),
                                 detail: s.minCeilingHeight.map { "lowest \(UnitsFormatter.distance($0))" },
                                 highlight: (s.ceilingHeight ?? 9) < 2.7)
                        StatView(label: "Doors · Windows", value: "\(s.doorCount) · \(s.windowCount)")
                    }
                }
                if !s.objectCategories.isEmpty {
                    Text(s.objectCategories.sorted { $0.key < $1.key }.map { "\($0.value)× \($0.key)" }.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func planCard(_ location: Location) -> some View {
        if let scan = location.primaryScan, let plan = store.floorPlan(ref, scanID: scan.id) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Plan", systemImage: "map")
                FloorPlanCanvas(plan: plan, overlay: miniOverlay(location, scan: scan), style: .full)
                    .frame(height: 260)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { router.open(.plan(ref)) }
                Text("Tap to place cameras, shots and measure on the plan.").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .card()
        }
    }

    private func miniOverlay(_ location: Location, scan: ScanRecord) -> PlanOverlay {
        var o = PlanOverlay()
        o.showGrid = false
        for c in location.cameraPositions where c.scanID == nil || c.scanID == scan.id {
            o.cameras.append(PlanCameraMarker(id: c.id, label: c.name, rig: c.rig, reach: 3))
        }
        for s in location.shots where s.scanID == nil || s.scanID == scan.id {
            o.cameras.append(PlanCameraMarker(id: s.id, label: String(format: "S%02d", s.number), rig: s.rig, isShot: true, reach: 3))
        }
        if let north = scan.northOffset { o.northWorldBearing = 360 - north }
        return o
    }

    private func tagsCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tags", systemImage: "tag")
            FlowLayout(spacing: 8) {
                ForEach(LocationTag.allCases) { tag in
                    TagChip(text: tag.label, selected: location.tags.contains(tag)) {
                        store.updateLocation(ref) { loc in
                            if loc.tags.contains(tag) { loc.tags.remove(tag) } else { loc.tags.insert(tag) }
                        }
                    }
                }
            }
        }
        .card()
    }

    private func photosCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Photos (\(location.photos.count))", systemImage: "photo.on.rectangle",
                          action: { router.open(.photos(ref)) }, actionLabel: "All")
            if !location.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(location.photos.suffix(12).reversed())) { photo in
                            StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 300)
                                .frame(width: 110, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { router.open(.photos(ref)) }
                        }
                    }
                }
            }
            HStack {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                    .buttonStyle(.bordered)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label("Import", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
    }

    private func measurementsCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Measurements (\(location.measurements.count))", systemImage: "ruler",
                          action: { router.open(.measurements(ref)) }, actionLabel: "All")
            ForEach(Array(location.measurements.suffix(5).reversed())) { m in
                HStack {
                    Image(systemName: m.kind.symbol).foregroundStyle(Theme.accent).frame(width: 24)
                    Text(m.label.isEmpty ? m.kind.label : m.label)
                    Spacer()
                    Text(UnitsFormatter.distance(m.value)).font(.body.monospacedDigit().weight(.semibold))
                }
            }
            if location.measurements.isEmpty {
                Text("Use Measure (AR), measure on the plan, or generate room measurements from the scan.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private func camerasCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cameras & shots", systemImage: "video", action: { router.open(.plan(ref)) }, actionLabel: "Plan")
            ForEach(location.cameraPositions) { c in
                HStack {
                    Image(systemName: "video.fill").foregroundStyle(Theme.accent).frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(c.name)
                        Text("\(c.rig.lensSummary) · h \(UnitsFormatter.distance(c.rig.height))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { router.start(.virtualCamera(ref, cameraID: c.id)) } label: { Image(systemName: "cube") }
                        .disabled(location.primaryScan == nil)
                }
            }
            if !location.shots.isEmpty {
                Button { router.open(.shots(ref)) } label: {
                    Label("\(location.shots.count) shots planned", systemImage: "film")
                }
            }
            if location.cameraPositions.isEmpty && location.shots.isEmpty {
                Text("Open the plan and tap “+ Camera” to place a camera position.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private func notesCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Notes", systemImage: "note.text", action: { router.open(.notes(ref)) }, actionLabel: "Edit")
            ForEach(location.quickNotes.prefix(6)) { note in
                Label(note.text, systemImage: note.category.symbol).font(.subheadline)
            }
            ForEach([("General", location.notes), ("Lighting", location.lightingNotes), ("Production", location.productionNotes)], id: \.0) { title, text in
                if !text.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased()).font(.fsLabel).foregroundStyle(Theme.textSecondary)
                        Text(text).font(.subheadline).lineLimit(4)
                    }
                }
            }
            if location.quickNotes.isEmpty && location.notes.isEmpty && location.lightingNotes.isEmpty && location.productionNotes.isEmpty {
                Text("Nothing yet — add lighting, power, access and production notes.").font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private func scansCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Scans (\(location.scans.count))", systemImage: "cube.transparent")
            ForEach(location.scans) { scan in
                Button { router.open(.scanDetail(ref, scanID: scan.id)) } label: {
                    HStack {
                        Image(systemName: scan.kind == .room ? "cube.transparent" : "square.stack.3d.down.forward")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(scan.name).foregroundStyle(Theme.textPrimary)
                            Text("\(scan.kind.label) · \(scan.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if scan.id == location.primaryScan?.id {
                            Text("PRIMARY").font(.fsLabel).foregroundStyle(Theme.accent)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            if location.scans.isEmpty {
                Text(DeviceCapabilities.hasLiDAR ? "No scan yet. Tap Scan to capture the space with LiDAR."
                                                 : "This device has no LiDAR, so it cannot scan. Scans made on a LiDAR iPhone/iPad can be imported via a project backup.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpeg = UIImage(data: data)?.downsampled(maxPixel: 4000)?.jpegData(compressionQuality: 0.85) {
                    store.addPhoto(jpeg, to: ref, source: .library)
                }
            }
            pickerItems = []
        }
    }
}

struct SmallTool: View {
    var title: String
    var symbol: String
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(title.uppercased()).font(.system(size: 12, weight: .heavy).width(.condensed))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
