import SwiftUI
import UIKit

/// Full-screen scan flow: choose mode → capture → review & save.
struct ScanFlowView: View {
    let target: CaptureTarget
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ScanKind?

    var body: some View {
        Group {
            switch mode {
            case .none:
                ScanModePicker(target: target, onSelect: { mode = $0 }, onClose: { dismiss() })
            case .room:
                RoomScanScreen(target: target, onClose: close)
            case .mesh:
                MeshScanScreen(target: target, onClose: close)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func close(_ saved: LocationRef?) {
        dismiss()
        if let saved {
            // Take the user straight to the location page with the new scan.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                router.popToRoot()
                router.open(.project(saved.projectID))
                router.open(.location(saved))
            }
        }
    }
}

struct ScanModePicker: View {
    let target: CaptureTarget
    var onSelect: (ScanKind) -> Void
    var onClose: () -> Void
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ref = target.locationRef, let loc = store.location(ref) {
                        Text("Scanning into **\(loc.name)**")
                            .foregroundStyle(Theme.textSecondary)
                    } else if target.projectID == nil {
                        Text("Quick scan — saved to “\(ProjectStore.quickScanProjectName)”. You can move it later by exporting/importing.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if !DeviceCapabilities.hasLiDAR {
                        RequirementBanner(
                            title: "LiDAR required for 3D scanning",
                            message: "This \(UIDevice.current.model) has no LiDAR sensor. 3D scanning needs an iPhone 12 Pro or later Pro model, or an iPad Pro (2020 or later). You can still create locations, take photos and notes, use the AR measure tool (plane-based, less accurate), the lens viewfinder, sun planning and plan camera positions on a blank grid.",
                            systemImage: "sensor.tag.radiowaves.forward")
                    }

                    modeCard(kind: .room,
                             title: "ROOM SCAN",
                             symbol: "cube.transparent",
                             bullets: ["Walls, doors, windows, openings, floor, furniture",
                                       "Accurate room dimensions and ceiling height",
                                       "Clean parametric model — best for Unreal and floor plans",
                                       "Pause to move between rooms; segments are merged"],
                             note: "Interiors only. Needs RoomPlan (LiDAR + iOS 17).",
                             enabled: DeviceCapabilities.supportsRoomPlan)

                    modeCard(kind: .mesh,
                             title: "MESH SCAN",
                             symbol: "square.stack.3d.down.forward",
                             bullets: ["Raw LiDAR surface mesh of whatever you point at",
                                       "Exteriors, courtyards, stages, irregular spaces",
                                       "Surfaces classified as wall / floor / ceiling / seat…",
                                       "Range about 5 m — walk the space"],
                             note: "Needs LiDAR.",
                             enabled: DeviceCapabilities.hasLiDAR)
                }
                .padding()
            }
            .fsScreen()
            .navigationTitle("New Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    private func modeCard(kind: ScanKind, title: String, symbol: String, bullets: [String],
                          note: String, enabled: Bool) -> some View {
        Button { onSelect(kind) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.title).foregroundStyle(Theme.accent)
                    Text(title).font(.fsButton).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
                }
                ForEach(bullets, id: \.self) { b in
                    Label(b, systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(enabled ? note : "Not available on this device. \(note)")
                    .font(.caption)
                    .foregroundStyle(enabled ? Theme.textTertiary : Theme.danger)
            }
            .card()
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Capture screens

struct RoomScanScreen: View {
    let target: CaptureTarget
    var onClose: (LocationRef?) -> Void
    @StateObject private var model = RoomScanModel()
    @State private var confirmCancel = false

    var body: some View {
        ZStack {
            RoomCaptureContainer(model: model).ignoresSafeArea()
            ScanHUD(phase: model.phase, info: model.info, kind: .room, hint: model.instruction,
                    photoCount: model.photos.count,
                    canPause: model.canPause, canResume: model.canResume, canFinish: model.canFinish,
                    onPause: model.pause, onResume: model.resume, onFinish: model.finish,
                    onPhoto: model.snapPhoto, onCancel: { confirmCancel = true })
        }
        .statusBarHidden()
        .confirmationDialog("Discard this scan?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard Scan", role: .destructive) { model.cancel(); onClose(nil) }
        }
        .sheet(isPresented: .constant(model.phase == .finished)) {
            if let result = model.result {
                ScanSaveView(target: target, result: result, stats: model.info.stats,
                             photos: model.photos, northOffset: model.info.northOffset,
                             segmentCount: model.segmentCount,
                             onDone: onClose)
                    .interactiveDismissDisabled()
            }
        }
    }
}

struct MeshScanScreen: View {
    let target: CaptureTarget
    var onClose: (LocationRef?) -> Void
    @StateObject private var model = MeshScanModel()
    @State private var confirmCancel = false

    var body: some View {
        ZStack {
            MeshCaptureContainer(model: model).ignoresSafeArea()
            ScanHUD(phase: model.phase, info: model.info, kind: .mesh, hint: model.trackingMessage,
                    photoCount: model.photos.count,
                    canPause: model.canPause, canResume: model.canResume, canFinish: model.canFinish,
                    onPause: model.pause, onResume: model.resume, onFinish: model.finish,
                    onPhoto: model.snapPhoto, onCancel: { confirmCancel = true })
        }
        .statusBarHidden()
        .confirmationDialog("Discard this scan?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard Scan", role: .destructive) { model.cancel(); onClose(nil) }
        }
        .sheet(isPresented: .constant(model.phase == .finished)) {
            if let result = model.result {
                ScanSaveView(target: target, result: result, stats: model.info.stats,
                             photos: model.photos, northOffset: model.info.northOffset,
                             segmentCount: 1,
                             onDone: onClose)
                    .interactiveDismissDisabled()
            }
        }
    }
}

/// Unobtrusive overlay: stats strip on top, big controls at the bottom within thumb reach.
struct ScanHUD: View {
    var phase: ScanPhase
    var info: LiveScanInfo
    var kind: ScanKind
    var hint: String?
    var photoCount: Int
    var canPause: Bool
    var canResume: Bool
    var canFinish: Bool
    var onPause: () -> Void
    var onResume: () -> Void
    var onFinish: () -> Void
    var onPhoto: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            topBar
            if let hint, phase == .scanning {
                Text(hint)
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.black)
            }
            Spacer()
            statusBanner
            controls
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(phase == .finalizing)

            ScanStatsStrip(info: info, kind: kind)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .processing, .finalizing:
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(phase == .processing ? "Processing segment…" : "Building model…").font(.headline)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: Capsule())
        case .paused:
            Text(kind == .room ? "PAUSED — walk to the next area, then resume" : "PAUSED — resume from the same spot")
                .font(.fsLabel)
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: onCancel).buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom) {
            OverlayButton(systemImage: "camera", label: photoCount > 0 ? "Photo (\(photoCount))" : "Photo", action: onPhoto)
                .disabled(!(phase == .scanning))
                .opacity(phase == .scanning ? 1 : 0.4)
            Spacer()
            if canResume {
                OverlayButton(systemImage: "play.fill", label: "Resume", tint: Theme.accent, filled: true, size: 76, action: onResume)
            } else {
                OverlayButton(systemImage: "pause.fill", label: "Pause", tint: .white, size: 76, action: onPause)
                    .disabled(!canPause)
                    .opacity(canPause ? 1 : 0.4)
            }
            Spacer()
            OverlayButton(systemImage: "checkmark", label: "Finish", tint: Theme.success, filled: true, action: onFinish)
                .disabled(!canFinish)
                .opacity(canFinish ? 1 : 0.4)
        }
        .padding(.horizontal, 12)
    }
}

struct ScanStatsStrip: View {
    var info: LiveScanInfo
    var kind: ScanKind

    var body: some View {
        let s = info.stats
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                figure("TIME", timeString(info.elapsed))
                figure("AREA", UnitsFormatter.area(s.floorArea))
                figure("SIZE", UnitsFormatter.dimensions(s.width, s.length))
                figure("CEILING", UnitsFormatter.distance(s.ceilingHeight))
            }
            HStack(spacing: 14) {
                if kind == .room {
                    figure("WALLS", "\(s.wallCount)")
                    figure("DOORS", "\(s.doorCount)")
                    figure("WINDOWS", "\(s.windowCount)")
                    figure("OBJECTS", "\(s.objectCount)")
                    if let c = s.completeness {
                        figure("COMPLETE*", "\(Int(c * 100))%")
                    }
                } else {
                    figure("TRIANGLES", s.meshFaceCount > 0 ? "\(s.meshFaceCount / 1000)k" : "—")
                    figure("NORTH", info.northOffset.map { String(format: "%.0f°", $0) } ?? "…")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .bold).width(.condensed)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Save

struct ScanSaveView: View {
    let target: CaptureTarget
    let result: ScanResult
    let stats: ScanStats
    let photos: [PendingPhoto]
    let northOffset: Double?
    let segmentCount: Int
    var onDone: (LocationRef?) -> Void

    @EnvironmentObject private var store: ProjectStore
    @State private var locationName = ""
    @State private var scanName = ""
    @State private var notes = ""
    @State private var projectID: UUID?
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDiscard = false

    private var existingLocation: Location? { target.locationRef.flatMap { store.location($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Result") {
                    LabeledContent("Type", value: result.kind.label)
                    LabeledContent("Floor area", value: UnitsFormatter.area(stats.floorArea) + (stats.floorAreaIsEstimate ? " (est.)" : ""))
                    LabeledContent("Room", value: UnitsFormatter.dimensions(stats.width, stats.length))
                    LabeledContent("Ceiling", value: UnitsFormatter.distance(stats.ceilingHeight))
                    if result.kind == .room {
                        LabeledContent("Walls / doors / windows", value: "\(stats.wallCount) / \(stats.doorCount) / \(stats.windowCount)")
                        LabeledContent("Objects", value: "\(stats.objectCount)")
                        LabeledContent("Segments", value: "\(segmentCount)")
                    } else {
                        LabeledContent("Triangles", value: "\(stats.meshFaceCount)")
                    }
                    LabeledContent("North", value: northOffset.map { String(format: "%.0f° (compass, approx.)", $0) } ?? "Not measured")
                    LabeledContent("Photos", value: "\(photos.count)")
                }

                Section("Location") {
                    if existingLocation == nil {
                        Picker("Project", selection: $projectID) {
                            Text(ProjectStore.quickScanProjectName).tag(UUID?.none)
                            ForEach(store.recentProjects.filter { $0.name != ProjectStore.quickScanProjectName }) { p in
                                Text(p.name).tag(Optional(p.id))
                            }
                        }
                    }
                    TextField("Location name", text: $locationName)
                        .textInputAutocapitalization(.words)
                    TextField("Scan name", text: $scanName)
                }

                Section("Notes") {
                    TextField("First impressions, access, power, light…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
            }
            .fsScreen()
            .navigationTitle("Save Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { confirmDiscard = true }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", action: save).bold()
                    }
                }
            }
            .confirmationDialog("Discard this scan?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { onDone(nil) }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        projectID = target.projectID
        if let loc = existingLocation {
            locationName = loc.name
            scanName = "\(result.kind.label) \(loc.scans.count + 1)"
        } else {
            let count = store.allLocationRefs.count + 1
            locationName = String(format: "LOCATION %03d", count)
            scanName = "\(result.kind.label) 1"
        }
    }

    private func save() {
        saving = true
        error = nil
        let request = ScanSaver.Request(result: result, scanName: scanName.isEmpty ? result.kind.label : scanName,
                                        notes: notes, northOffset: northOffset, photos: photos,
                                        segmentCount: segmentCount)
        let destination = CaptureTarget(projectID: projectID ?? target.projectID, locationID: target.locationID)
        Task {
            do {
                let ref = try await ScanSaver.save(request, locationName: locationName, target: destination, store: store)
                if !notes.isEmpty {
                    store.updateLocation(ref) { loc in
                        if loc.notes.isEmpty { loc.notes = notes }
                    }
                }
                onDone(ref)
            } catch {
                self.error = "Saving failed: \(error.localizedDescription)"
                saving = false
            }
        }
    }
}
