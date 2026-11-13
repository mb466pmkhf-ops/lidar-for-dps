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
    @State private var sharedReport: SharedFile?
    @State private var reportError: String?

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
            // The room view starts with the plan. The figures are one small line under it, then one
            // list of where to go next, then the details you set once (address, tags, scans).
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    ScreenHeading(title: location.name)
                    if let project = store.project(ref.projectID) {
                        Text(project.name).font(.fsCaption).foregroundStyle(Theme.textTertiary)
                    }
                }
                planHero(location)
                goToList(location)
                if !captureRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ListSectionTitle(title: "Capture")
                        RowList(rows: captureRows)
                    }
                }
                photosCard(location)
                detailsCard(location)
                scansCard(location)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .fsScreen()
        .fsWrappingTitle(location.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = location.name; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button { router.open(.export(projectID: ref.projectID, location: ref)) } label: {
                        Label("Export Location…", systemImage: "square.and.arrow.up")
                    }
                    Button(action: shareReport) {
                        Label("Scout Report (PDF)", systemImage: "doc.richtext")
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Location", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").font(.system(size: 17, weight: .light)) }
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
        .sheet(item: $sharedReport) { file in ShareSheet(items: [file.url]) }
        .alert("Report failed", isPresented: Binding(get: { reportError != nil }, set: { if !$0 { reportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(reportError ?? "") }
    }

    // MARK: Sections

    /// The plan, big, at the top. Tapping it (or the button) opens the plan screen. Without a plan
    /// yet, the same spot says how to get one.
    @ViewBuilder
    private func planHero(_ location: Location) -> some View {
        if let scan = location.primaryScan, let plan = store.floorPlan(ref, scanID: scan.id) {
            VStack(alignment: .leading, spacing: 10) {
                Button { router.open(.lighting(ref)) } label: {
                    FloorPlanCanvas(plan: plan, overlay: previewOverlay(location, scan: scan), style: .full)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan of \(location.name)")
                .accessibilityHint("Opens the plan")
                figures(location, scan: scan)
                Button { router.open(.lighting(ref)) } label: {
                    Label(planButtonTitle(location), systemImage: "map")
                        .font(HomeStyle.button)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(HomePrimaryButtonStyle())
            }
        } else {
            noPlanYet(location)
        }
    }

    private func planButtonTitle(_ location: Location) -> String {
        location.lightFixtures.isEmpty && location.cameraPositions.isEmpty && location.previsCharacters.isEmpty
            ? "Start the plan" : "Open the plan"
    }

    /// Room size and what's on the plan, as two small lines. Provenance marks stay on the sizes.
    private func figures(_ location: Location, scan: ScanRecord) -> some View {
        let s = scan.stats
        var room = [s.marked(UnitsFormatter.dimensions(s.width, s.length), .roomSize, kind: scan.kind),
                    s.marked(UnitsFormatter.area(s.floorArea), .floorArea, kind: scan.kind)]
        if s.ceilingHeight != nil {
            room.append("ceiling \(s.marked(UnitsFormatter.distance(s.ceilingHeight), .ceilingHeight, kind: scan.kind))")
        }
        if s.doorCount + s.windowCount > 0 {
            room.append("\(s.doorCount) door\(s.doorCount == 1 ? "" : "s"), \(s.windowCount) window\(s.windowCount == 1 ? "" : "s")")
        }
        let planned = plannedLine(location)
        let low = (s.ceilingHeight ?? 9) < 2.7
        return VStack(alignment: .leading, spacing: 3) {
            Text(room.joined(separator: " · "))
                .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if low, let c = s.minCeilingHeight ?? s.ceilingHeight {
                Text("Low ceiling: lowest point \(UnitsFormatter.distance(c))").font(.fsCaption).foregroundStyle(Theme.textPrimary)
            }
            if !planned.isEmpty {
                Text(planned).font(.fsCaption).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func plannedLine(_ location: Location) -> String {
        func n(_ count: Int, _ one: String, _ many: String) -> String? { count == 0 ? nil : "\(count) \(count == 1 ? one : many)" }
        return [n(location.previsCharacters.count, "person", "people"),
                n(location.cameraPositions.count + location.shots.count, "camera", "cameras"),
                n(location.lightFixtures.count, "light", "lights")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// No scan or drawn plan yet: one card that says what to do, in the spot the plan will take.
    private func noPlanYet(_ location: Location) -> some View {
        let canScan = DeviceCapabilities.hasLiDAR
        return VStack(alignment: .leading, spacing: 10) {
            Text(canScan ? "Scan the room first" : "No plan yet").font(.fsHeadline)
            Text(canScan
                 ? "Walk the room slowly with the phone. The plan, the 3D view and the readings all build on the scan."
                 : "This phone can't scan. Lay out a plan by hand, or draw the room from Home with its sizes.")
                .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if canScan {
                Button { router.start(.scan(CaptureTarget(ref))) } label: {
                    Label("Scan this room", systemImage: "viewfinder")
                        .font(HomeStyle.button)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(HomePrimaryButtonStyle())
            }
            Button(canScan ? "Plan without a scan" : "Open the plan") { router.open(.lighting(ref)) }
                .buttonStyle(HairlineButtonStyle(prominent: !canScan))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Everything else about this room, as one list with the same rows as Home.
    private func goToList(_ location: Location) -> some View {
        let shots = location.shots.count
        let lastMeasure = location.measurements.last
        let firstNote = location.quickNotes.first?.text
            ?? [location.notes, location.lightingNotes, location.productionNotes].first(where: { !$0.isEmpty })
        return VStack(alignment: .leading, spacing: 8) {
            ListSectionTitle(title: "This location")
            RowList(rows: [
                RowItem(title: "Shots", subtitle: shots == 0 ? "Turn camera positions into a shot list" : nil,
                        systemImage: "film", trailing: shots == 0 ? nil : "\(shots)") { router.open(.shots(ref)) },
                RowItem(title: "Sun and daylight", subtitle: location.coordinate == nil ? "Needs the GPS position (in Details)" : "Sun path, golden hour, light through the windows",
                        systemImage: "sun.max") { router.open(.sun(ref)) },
                RowItem(title: "Measurements", subtitle: lastMeasure.map { "\($0.label.isEmpty ? $0.kind.label : $0.label) \(UnitsFormatter.distance($0.value))" },
                        systemImage: "ruler", trailing: location.measurements.isEmpty ? nil : "\(location.measurements.count)") { router.open(.measurements(ref)) },
                RowItem(title: "Notes", subtitle: firstNote.map { String($0.prefix(80)) } ?? "Power, access, lighting, production",
                        systemImage: "note.text") { router.open(.notes(ref)) },
            ])
        }
    }

    /// Camera tools this phone can run; the others are left out, as on Home.
    private var captureRows: [RowItem] {
        var rows: [RowItem] = []
        if DeviceCapabilities.hasLiDAR, store.location(ref)?.primaryScan != nil {
            rows.append(RowItem(title: "Scan again", subtitle: "A fresh scan; older ones stay under Scans", systemImage: "viewfinder") {
                router.start(.scan(CaptureTarget(ref)))
            })
        }
        if DeviceCapabilities.supportsWorldTracking {
            rows.append(RowItem(title: "Measure", subtitle: DeviceCapabilities.hasLiDAR ? "Tape measure in AR" : "Tape measure in AR, estimated without LiDAR",
                                systemImage: "ruler") { router.start(.measure(CaptureTarget(ref))) })
        }
        return rows
    }

    /// Address, GPS and tags: set once, so they sit below the things you use every time.
    private func detailsCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ListSectionTitle(title: "Details")
            VStack(alignment: .leading, spacing: 10) {
                TextField("Address / general location", text: store.binding(for: ref).address, axis: .vertical)
                    .font(.fsBody)
                HStack(spacing: 12) {
                    Label(location.dateScanned.map { "Scanned \(UnitsFormatter.shortDate($0))" } ?? "Not scanned yet",
                          systemImage: "calendar")
                    if let c = location.coordinate {
                        Label(String(format: "%.4f, %.4f", c.latitude, c.longitude), systemImage: "location")
                    }
                }
                .font(.fsCaption)
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
                        .font(.fsCaptionStrong)
                        .frame(minHeight: 36)
                }
                .disabled(locator.isLocating)
                if let error = locator.lastError {
                    Text(error).font(.fsCaption).foregroundStyle(Theme.danger)
                }
                Divider()
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
    }

    /// The plan preview shows what's been placed (cameras, lights, people) without labels or beams.
    private func previewOverlay(_ location: Location, scan: ScanRecord) -> PlanOverlay {
        var o = PlanOverlay()
        o.showGrid = false
        o.showLightLabels = false
        o.showPeopleLabels = false
        o.showAllBeams = false
        let inScan: (UUID?) -> Bool = { $0 == nil || $0 == scan.id }
        for c in location.cameraPositions where inScan(c.scanID) {
            o.cameras.append(PlanCameraMarker(id: c.id, label: c.name, rig: c.rig, reach: 3))
        }
        for s in location.shots where inScan(s.scanID) {
            o.cameras.append(PlanCameraMarker(id: s.id, label: String(format: "S%02d", s.number), rig: s.rig, isShot: true, reach: 3))
        }
        for light in location.lightFixtures where inScan(light.scanID) {
            var marker = PlanLightMarker(light: light)
            if light.kind.emits { marker.tint = light.photometrics.color }
            o.lights.append(marker)
        }
        for c in location.previsCharacters where inScan(c.scanID) {
            let p = c.proportions
            o.people.append(PlanPersonMarker(id: c.id, name: c.name, position: c.position, facing: c.facing,
                                             shoulderWidth: p.shoulderWidth, depth: p.chestDepth, headRadius: p.headWidth / 2,
                                             skin: c.skinTone.rgb, reading: nil))
        }
        if let north = scan.northOffset { o.northWorldBearing = 360 - north }
        return o
    }

    private func photosCard(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ListSectionTitle(title: location.photos.isEmpty ? "Photos" : "Photos (\(location.photos.count))")
                Spacer()
                if !location.photos.isEmpty {
                    Button("See all") { router.open(.photos(ref)) }
                        .font(.fsCaptionStrong).foregroundStyle(Theme.accent)
                        .frame(minHeight: 36)
                }
            }
            if !location.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(location.photos.suffix(12).reversed())) { photo in
                            StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 300)
                                .frame(width: 110, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                                .onTapGesture { router.open(.photos(ref)) }
                        }
                    }
                }
            }
            HStack {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                    .buttonStyle(HairlineButtonStyle())
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                if DeviceCapabilities.hasCamera {
                    Button { router.start(.viewfinder(CaptureTarget(ref))) } label: { Label("Framed", systemImage: "camera.aperture") }
                        .buttonStyle(HairlineButtonStyle())
                        .accessibilityLabel("Take a framed photo through your lens")
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                    Label("Import", systemImage: "photo.badge.plus")
                }
                .buttonStyle(HairlineButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func scansCard(_ location: Location) -> some View {
        // Only worth a section once there's a scan to look at; "scan this room" sits in the plan's spot.
        if !location.scans.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            ListSectionTitle(title: location.scans.count == 1 ? "Scan" : "Scans (\(location.scans.count))")
            VStack(spacing: 0) {
            ForEach(Array(location.scans.enumerated()), id: \.element.id) { i, scan in
                if i > 0 { Divider().padding(.leading, 36) }
                Button { router.open(.scanDetail(ref, scanID: scan.id)) } label: {
                    HStack {
                        Image(systemName: scan.kind == .room ? "cube.transparent" : "square.stack.3d.down.forward")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(scan.name).foregroundStyle(Theme.textPrimary)
                            Text("\(scan.kind.label) · \(scan.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if scan.id == location.primaryScan?.id {
                            Text("In use").font(.fsCaption).foregroundStyle(Theme.textTertiary)
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(minHeight: HomeStyle.minTap)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            }
            .homeCard()
        }
        }
    }

    private func shareReport() {
        guard let data = ScoutReportData.load(ref, store: store) else { return }
        do {
            sharedReport = SharedFile(url: try ScoutReport.renderToTemporaryFile(data))
        } catch {
            reportError = error.localizedDescription
        }
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
