import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @AppStorage(UnitsFormatter.imperialKey) private var useImperial = false
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ActionTile(title: "Scan a location",
                               subtitle: DeviceCapabilities.hasLiDAR ? "Room plan or LiDAR mesh" : "Needs a LiDAR iPhone",
                               systemImage: "viewfinder", prominent: true, disabled: !DeviceCapabilities.hasLiDAR) {
                        router.start(.scan(.quick))
                    }
                    ActionTile(title: "Measure",
                               subtitle: DeviceCapabilities.hasLiDAR ? "AR tape, LiDAR accurate" : (DeviceCapabilities.supportsWorldTracking ? "AR tape, estimated without LiDAR" : "Needs AR camera"),
                               systemImage: "ruler", disabled: !DeviceCapabilities.supportsWorldTracking) {
                        router.start(.measure(.quick))
                    }
                    ActionTile(title: "Viewfinder", subtitle: DeviceCapabilities.hasCamera ? "Cinema lens frame lines" : "Needs a camera",
                               systemImage: "camera.aperture", disabled: !DeviceCapabilities.hasCamera) {
                        router.start(.viewfinder(.quick))
                    }
                    ActionTile(title: "Scan an object",
                               subtitle: ObjectCaptureModel.isSupported ? "Prop → textured 3D model" : "Needs a LiDAR iPhone",
                               systemImage: "cube", disabled: !ObjectCaptureModel.isSupported) {
                        router.start(.objectScan(projectID: nil))
                    }
                }

                VStack(spacing: 0) {
                    MenuRow(title: "Export", subtitle: "Unreal · USD · OBJ · GLB · ZIP", systemImage: "square.and.arrow.up") {
                        router.open(.export(projectID: nil, location: nil))
                    }
                    Divider().padding(.leading, 42)
                    MenuRow(title: "Compare locations", subtitle: "Side by side, A vs B", systemImage: "rectangle.split.2x1") {
                        router.open(.compare)
                    }
                }
                .card(padding: 14)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Projects", action: {
                        newProjectName = ""
                        showNewProject = true
                    }, actionLabel: "New")
                    if store.recentProjects.isEmpty {
                        EmptyStateView(systemImage: "film", title: "No projects yet",
                                       message: "Make a project for each production, then add locations, scans and props to it.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.recentProjects.prefix(12).enumerated()), id: \.element.id) { i, project in
                                if i > 0 { Divider().padding(.leading, 88) }
                                Button { router.open(.project(project.id)) } label: {
                                    ProjectRow(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { projectMenu(project) }
                            }
                        }
                        .card(padding: 14)
                    }
                }

                Label(DeviceCapabilities.summary, systemImage: DeviceCapabilities.hasLiDAR ? "checkmark.circle" : "info.circle")
                    .font(.fsFootnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .fsScreen()
        .navigationTitle("FrameScout")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImporter = true } label: { Label("Import Project Backup…", systemImage: "square.and.arrow.down") }
                    Toggle(isOn: $useImperial) { Label("Imperial units (ft/in)", systemImage: "ruler") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .accessibilityLabel("More")
            }
        }
        .alert("New Project", isPresented: $showNewProject) {
            TextField("e.g. Commercial XYZ", text: $newProjectName)
                .textInputAutocapitalization(.words)
            Button("Create") {
                let project = store.createProject(name: newProjectName)
                router.open(.project(project.id))
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            importProject(result)
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Button { store.duplicateProject(project.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { store.deleteProject(project.id) } label: { Label("Delete", systemImage: "trash") }
    }

    private func importProject(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let project = try store.importProject(from: url)
                importMessage = "Imported “\(project.name)” with \(project.locations.count) location(s)."
            } catch {
                importMessage = error.localizedDescription
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }
}

/// A project in the home list: first still (or an icon), name, client and counts.
struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let still = stills.first {
                    Color.clear.overlay { still }.clipped()
                } else {
                    Image(systemName: "film").font(.title2).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.surfaceRaised)
                }
            }
            .frame(width: 76, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.fsHeadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(summary).font(.fsFootnote).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the project")
    }

    private var caption: String {
        let kind = project.name == ProjectStore.quickScanProjectName ? "quick captures"
            : (project.client.isEmpty ? "production" : project.client)
        return kind.prefix(1).uppercased() + kind.dropFirst()
    }

    /// Up to three reference photos, then object thumbnails.
    private var stills: [AnyView] {
        var out: [AnyView] = []
        for location in project.locations {
            let ref = LocationRef(projectID: project.id, locationID: location.id)
            for photo in location.photos.prefix(3) where out.count < 3 {
                out.append(AnyView(StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 500)))
            }
            if out.count == 3 { return out }
        }
        for object in project.objects where out.count < 3 && object.status == .ready {
            out.append(AnyView(ObjectThumbnail(projectID: project.id, object: object)))
        }
        return out
    }

    private var summary: String {
        let scans = project.locations.reduce(0) { $0 + $1.scans.count }
        var parts = [caption, "\(project.locations.count) location\(project.locations.count == 1 ? "" : "s")", "\(scans) scan\(scans == 1 ? "" : "s")"]
        if !project.objects.isEmpty { parts.append("\(project.objects.count) objects") }
        parts.append(project.modifiedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
