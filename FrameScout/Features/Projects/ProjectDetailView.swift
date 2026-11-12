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
    @State private var showDrawRoom = false
    @State private var showListing = false

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
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenHeading(title: project.name)
                    TextField("Client / production company", text: Binding(
                        get: { store.project(projectID)?.client ?? "" },
                        set: { value in store.updateProject(projectID) { $0.client = value } }))
                        .font(.fsBody)
                        .foregroundStyle(Theme.textSecondary)
                    // The counts are context, not the point of the screen: one small line.
                    Text(countsLine(project)).font(.fsCaption).foregroundStyle(Theme.textTertiary)
                }

                // The rooms come first: that's what you open a project for.
                VStack(alignment: .leading, spacing: 8) {
                    ListSectionTitle(title: "Locations")
                    if project.locations.isEmpty {
                        Text("No locations yet. Scan a room, draw one or add an empty one below.")
                            .font(.fsCaption).foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(project.locations) { location in
                                let ref = LocationRef(projectID: projectID, locationID: location.id)
                                Button { router.open(.location(ref)) } label: {
                                    LocationRow(location: location, ref: ref)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { router.open(.lighting(ref)) } label: { Label("Open plan", systemImage: "map") }
                                    Button(role: .destructive) { store.deleteLocation(ref) } label: {
                                        Label("Delete Location", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                if DeviceCapabilities.hasLiDAR {
                    Button { router.start(.scan(CaptureTarget(projectID: projectID, locationID: nil))) } label: {
                        Label("Scan a room", systemImage: "viewfinder")
                            .font(HomeStyle.button)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(HomePrimaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    ListSectionTitle(title: "Add a location")
                    RowList(rows: addRows)
                }

                if !project.objects.isEmpty {
                    ListSectionTitle(title: "Objects (\(project.objects.count))")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 14) {
                        ForEach(project.objects) { object in
                            Button { router.open(.object(projectID: projectID, objectID: object.id)) } label: {
                                VStack(spacing: 6) {
                                    ObjectThumbnail(projectID: projectID, object: object)
                                        .aspectRatio(1, contentMode: .fit)
                                    Text(object.name).font(.fsLabel).lineLimit(1)
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
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
                    if project.locations.count > 1 {
                        Button { router.open(.compare) } label: { Label("Compare Locations", systemImage: "rectangle.split.2x1") }
                    }
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
        .sheet(isPresented: $showDrawRoom) { DrawRoomView(intoProject: projectID) }
        .sheet(isPresented: $showListing) { BuildFromListingView(intoProject: projectID) }
        .confirmationDialog("Delete “\(project.name)” and all its scans and photos?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) {
                store.deleteProject(projectID)
                dismiss()
            }
        }
    }

    private func countsLine(_ project: Project) -> String {
        func n(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        var parts = [n(project.locations.count, "location"),
                     n(project.locations.reduce(0) { $0 + $1.scans.count }, "scan"),
                     n(project.locations.reduce(0) { $0 + $1.shots.count }, "shot")]
        if !project.objects.isEmpty { parts.append(n(project.objects.count, "object")) }
        return parts.joined(separator: " · ")
    }

    /// Ways to add a room to this project, minus the ones this phone can't do.
    private var addRows: [RowItem] {
        var rows: [RowItem] = [
            RowItem(title: "Draw a plan", subtitle: "Pick a shape and type the sizes", systemImage: "pencil.and.ruler") { showDrawRoom = true },
            RowItem(title: "From a listing", subtitle: "The studio's photos and sizes", systemImage: "photo.on.rectangle.angled") { showListing = true },
            RowItem(title: "Empty location", subtitle: "Photos and notes now, scan later", systemImage: "plus") {
                newLocationName = ""
                showAddLocation = true
            },
        ]
        if ObjectCaptureModel.isSupported {
            rows.append(RowItem(title: "Scan an object", subtitle: "A prop as a textured 3D model", systemImage: "cube") {
                router.start(.objectScan(projectID: projectID))
            })
        }
        return rows
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
                if !planLine.isEmpty {
                    Text(planLine).font(.fsMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    /// What's planned here, only the parts that exist ("2 people · 3 cameras · 6 lights").
    private var planLine: String {
        func n(_ count: Int, _ one: String, _ many: String) -> String? { count == 0 ? nil : "\(count) \(count == 1 ? one : many)" }
        return [n(location.previsCharacters.count, "person", "people"),
                n(location.cameraPositions.count + location.shots.count, "camera", "cameras"),
                n(location.lightFixtures.count, "light", "lights"),
                n(location.photos.count, "photo", "photos")]
            .compactMap { $0 }.joined(separator: " · ")
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
