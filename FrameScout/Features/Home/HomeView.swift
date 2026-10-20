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
            VStack(alignment: .leading, spacing: 26) {
                header

                VStack(spacing: 0) {
                    MenuRow(title: "Scan a location",
                            subtitle: DeviceCapabilities.hasLiDAR ? "Room plan or LiDAR mesh" : "Needs LiDAR",
                            disabled: !DeviceCapabilities.hasLiDAR) {
                        router.start(.scan(.quick))
                    }
                    MenuRow(title: "Scan an object",
                            subtitle: ObjectCaptureModel.isSupported ? "Prop or toy → textured 3D model for Unreal" : "Needs LiDAR + iOS 17",
                            disabled: !ObjectCaptureModel.isSupported) {
                        router.start(.objectScan(projectID: nil))
                    }
                    MenuRow(title: "Viewfinder", subtitle: "Cinema lens frame lines", disabled: !DeviceCapabilities.hasCamera) {
                        router.start(.viewfinder(.quick))
                    }
                    MenuRow(title: "Measure",
                            subtitle: DeviceCapabilities.hasLiDAR ? "AR tape, LiDAR accurate" : "AR tape, plane-based",
                            disabled: !DeviceCapabilities.supportsWorldTracking) {
                        router.start(.measure(.quick))
                    }
                    MenuRow(title: "Export", subtitle: "Unreal · USD · OBJ · GLB · ZIP") {
                        router.open(.export(projectID: nil, location: nil))
                    }
                    MenuRow(title: "Compare", subtitle: "Location A vs B") {
                        router.open(.compare)
                    }
                }

                HStack {
                    SectionHeader(title: "Projects")
                    Button {
                        newProjectName = ""
                        showNewProject = true
                    } label: {
                        Text("+ New")
                            .font(.fsLabel).tracking(Theme.tracking)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white, in: Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if store.recentProjects.isEmpty {
                    EmptyStateView(systemImage: "film", title: "No projects yet",
                                   message: "Make a project for each production, then add locations, scans and props to it.")
                } else {
                    VStack(spacing: 30) {
                        ForEach(store.recentProjects.prefix(12)) { project in
                            Button { router.open(.project(project.id)) } label: {
                                ProjectRow(project: project)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { projectMenu(project) }
                        }
                    }
                }

                Text(DeviceCapabilities.summary)
                    .font(.fsMono)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .fsScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Wordmark() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImporter = true } label: { Label("Import Project Backup…", systemImage: "square.and.arrow.down") }
                    Toggle(isOn: $useImperial) { Label("Imperial units (ft/in)", systemImage: "ruler") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .light))
                }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scout, measure\nand frame it.")
                .font(.fsTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("Then take it to Unreal.")
                .font(.fsBody)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 8)
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

/// A project as the site shows a piece of work: a centred "Name | type" caption over three stills.
struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(spacing: 12) {
            Text(caption)
                .font(.fsLabel)
                .tracking(0.4)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            let stills = self.stills
            if stills.isEmpty {
                Rectangle()
                    .fill(Theme.surface)
                    .aspectRatio(16 / 5, contentMode: .fit)
                    .overlay(Text("no stills yet").font(.fsMicro).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary))
            } else {
                HStack(spacing: 8) {
                    ForEach(stills.indices, id: \.self) { i in
                        Color.clear
                            .aspectRatio(16 / 10, contentMode: .fit)
                            .overlay { stills[i] }
                            .clipped()
                    }
                }
            }
            Text(summary)
                .font(.fsMono)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
    }

    private var caption: String {
        let kind = project.name == ProjectStore.quickScanProjectName ? "quick captures"
            : (project.client.isEmpty ? "production" : project.client)
        return "\(project.name) | \(kind)"
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
        var parts = ["\(project.locations.count) loc", "\(scans) scans"]
        if !project.objects.isEmpty { parts.append("\(project.objects.count) obj") }
        parts.append(project.modifiedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
