import SwiftUI
import UIKit

struct ProjectDetailView: View {
    let projectID: UUID
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showAddLocation = false
    @State private var newLocationName = ""
    @State private var confirmDelete = false
    @State private var editingClient = false

    var body: some View {
        if let project = store.project(projectID) {
            content(project)
        } else {
            EmptyStateView(systemImage: "questionmark.folder", title: "Project not found", message: "It may have been deleted.")
                .fsScreen()
        }
    }

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeading(title: project.name)
                summary(project)

                HStack(spacing: 8) {
                    ActionTile(title: "Scan location", subtitle: "New location + LiDAR", systemImage: "viewfinder",
                               prominent: true, disabled: !DeviceCapabilities.hasLiDAR) {
                        router.start(.scan(CaptureTarget(projectID: projectID, locationID: nil)))
                    }
                    ActionTile(title: "Scan object", subtitle: "Prop → 3D model", systemImage: "cube",
                               disabled: !ObjectCaptureModel.isSupported) {
                        router.start(.objectScan(projectID: projectID))
                    }
                    ActionTile(title: "Add location", subtitle: "Notes, photos first", systemImage: "plus") {
                        newLocationName = ""
                        showAddLocation = true
                    }
                }

                SectionHeader(title: "Locations")
                if project.locations.isEmpty {
                    EmptyStateView(systemImage: "map", title: "No locations yet",
                                   message: "Scan a location or add one to start collecting photos and notes.")
                        .card()
                } else {
                    ForEach(project.locations) { location in
                        let ref = LocationRef(projectID: projectID, locationID: location.id)
                        Button { router.open(.location(ref)) } label: {
                            LocationRow(location: location, ref: ref)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteLocation(ref) } label: {
                                Label("Delete Location", systemImage: "trash")
                            }
                        }
                    }
                }

                if !project.objects.isEmpty {
                    SectionHeader(title: "Objects", action: { router.start(.objectScan(projectID: projectID)) }, actionLabel: "Scan")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 14) {
                        ForEach(project.objects) { object in
                            Button { router.open(.object(projectID: projectID, objectID: object.id)) } label: {
                                VStack(spacing: 6) {
                                    ObjectThumbnail(projectID: projectID, object: object)
                                        .aspectRatio(1, contentMode: .fit)
                                    Text(object.name).font(.fsLabel).tracking(0.4).lineLimit(1)
                                    Text(object.dimensionsSummary ?? object.status.rawValue)
                                        .font(.fsMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { store.deleteObject(projectID, object.id) } label: {
                                    Label("Delete Object", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .fsScreen()
        .fsWrappingTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { renameText = project.name; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button {
                        if let copy = store.duplicateProject(projectID) { router.open(.project(copy.id)) }
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { router.open(.export(projectID: projectID, location: nil)) } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    Button { router.open(.compare) } label: { Label("Compare Locations", systemImage: "rectangle.split.2x1") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Project", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .light))
                }
            }
        }
        .alert("Rename Project", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") { store.renameProject(projectID, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Location", isPresented: $showAddLocation) {
            TextField("e.g. Warehouse", text: $newLocationName)
                .textInputAutocapitalization(.words)
            Button("Add") {
                if let ref = store.addLocation(to: projectID, name: newLocationName) {
                    router.open(.location(ref))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(project.name)” and all its scans and photos?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) {
                store.deleteProject(projectID)
                dismiss()
            }
        }
    }

    private func summary(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatView(label: "Locations", value: "\(project.locations.count)")
                StatView(label: "Scans", value: "\(project.locations.reduce(0) { $0 + $1.scans.count })")
                StatView(label: "Shots", value: "\(project.locations.reduce(0) { $0 + $1.shots.count })")
                StatView(label: "Objects", value: "\(project.objects.count)")
            }
            TextField("Client / production company", text: Binding(
                get: { store.project(projectID)?.client ?? "" },
                set: { value in store.updateProject(projectID) { $0.client = value } }))
                .font(.fsBody)
                .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

struct LocationRow: View {
    let location: Location
    let ref: LocationRef

    var body: some View {
        HStack(spacing: 14) {
            LocationThumbnail(location: location, ref: ref)
                .frame(width: 96, height: 64)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name).font(.fsHeadline).foregroundStyle(Theme.textPrimary)
                if let scan = location.primaryScan {
                    let s = scan.stats
                    Text("\(s.marked(UnitsFormatter.dimensions(s.width, s.length), .roomSize, kind: scan.kind)) · ceiling \(s.marked(UnitsFormatter.distance(s.ceilingHeight), .ceilingHeight, kind: scan.kind))")
                        .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Not scanned").font(.fsCaption).foregroundStyle(Theme.textTertiary)
                }
                Text("\(location.photos.count) photos · \(location.cameraPositions.count) cameras · \(location.shots.count) shots")
                    .font(.fsMicro).foregroundStyle(Theme.textTertiary)
                if !location.tags.isEmpty {
                    Text(location.sortedTags.prefix(4).map { $0.label.capitalized }.joined(separator: " · "))
                        .font(.fsMicro)
                        .tracking(Theme.tracking)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text("→").font(.poppins(.light, 16)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }
}

/// First reference photo, or the plan, or a placeholder.
struct LocationThumbnail: View {
    let location: Location
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        ZStack {
            Theme.surfaceRaised
            if let photo = location.photos.first {
                StoredImage(url: StoragePaths.photoURL(ref, photo))
            } else if let scan = location.primaryScan, let plan = store.floorPlan(ref, scanID: scan.id) {
                FloorPlanCanvas(plan: plan, style: .thumbnail)
                    .padding(6)
            } else {
                Image(systemName: "photo").font(.system(size: 14, weight: .ultraLight)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Loads a JPEG from disk off the main thread, downsampled for lists.
struct StoredImage: View {
    let url: URL
    var maxPixel: CGFloat = 600
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            let url = self.url, size = maxPixel
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: url.path)?.downsampled(maxPixel: size)
            }.value
        }
    }
}
