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
                summary(project)

                HStack(spacing: 12) {
                    ActionTile(title: "Scan Location", subtitle: "New location + LiDAR scan", systemImage: "viewfinder.circle",
                               prominent: true, disabled: !DeviceCapabilities.hasLiDAR) {
                        router.start(.scan(CaptureTarget(projectID: projectID, locationID: nil)))
                    }
                    ActionTile(title: "Add Location", subtitle: "Notes / photos first", systemImage: "mappin.and.ellipse") {
                        newLocationName = ""
                        showAddLocation = true
                    }
                }

                SectionHeader(title: "Locations", systemImage: "mappin")
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
            }
            .padding()
        }
        .fsScreen()
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
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
                    Image(systemName: "ellipsis.circle")
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
            }
            TextField("Client / production company", text: Binding(
                get: { store.project(projectID)?.client ?? "" },
                set: { value in store.updateProject(projectID) { $0.client = value } }))
                .font(.subheadline)
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
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name).font(.headline).foregroundStyle(Theme.textPrimary)
                if let s = location.primaryScan?.stats {
                    Text("\(UnitsFormatter.dimensions(s.width, s.length)) · ceiling \(UnitsFormatter.distance(s.ceilingHeight))")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Not scanned").font(.caption).foregroundStyle(Theme.textTertiary)
                }
                Text("\(location.photos.count) photos · \(location.cameraPositions.count) cameras · \(location.shots.count) shots")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                if !location.tags.isEmpty {
                    Text(location.sortedTags.prefix(4).map(\.label).joined(separator: " · "))
                        .font(.system(size: 10, weight: .bold).width(.condensed))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 10)
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
                Image(systemName: "photo").foregroundStyle(Theme.textTertiary)
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
