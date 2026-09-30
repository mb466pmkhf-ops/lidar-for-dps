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

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 12) {
                    ActionTile(title: "New Project", subtitle: "Production / job", systemImage: "folder.badge.plus", prominent: true) {
                        newProjectName = ""
                        showNewProject = true
                    }
                    ActionTile(title: "Quick Scan", subtitle: DeviceCapabilities.hasLiDAR ? "LiDAR room or mesh" : "Needs LiDAR",
                               systemImage: "viewfinder.circle", disabled: !DeviceCapabilities.hasLiDAR) {
                        router.start(.scan(.quick))
                    }
                    ActionTile(title: "Measure", subtitle: DeviceCapabilities.hasLiDAR ? "AR tape, LiDAR accurate" : "AR tape (plane-based)",
                               systemImage: "ruler", disabled: !DeviceCapabilities.supportsWorldTracking) {
                        router.start(.measure(.quick))
                    }
                    ActionTile(title: "Camera", subtitle: "Lens / FOV viewfinder", systemImage: "camera.viewfinder",
                               disabled: !DeviceCapabilities.hasCamera) {
                        router.start(.viewfinder(.quick))
                    }
                    ActionTile(title: "Export", subtitle: "Unreal · USD · OBJ · GLB · ZIP", systemImage: "square.and.arrow.up.on.square") {
                        router.open(.export(projectID: nil, location: nil))
                    }
                    ActionTile(title: "Compare", subtitle: "Location A vs B", systemImage: "rectangle.split.2x1") {
                        router.open(.compare)
                    }
                }

                SectionHeader(title: "Recent Projects", systemImage: "clock")
                if store.recentProjects.isEmpty {
                    EmptyStateView(systemImage: "film.stack", title: "No projects yet",
                                   message: "Create a project for each production, then add locations and scan them.")
                        .card()
                } else {
                    VStack(spacing: 10) {
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
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .fsScreen()
        .navigationTitle("FrameScout")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImporter = true } label: { Label("Import Project Backup…", systemImage: "square.and.arrow.down") }
                    Toggle(isOn: $useImperial) { Label("Imperial units (ft/in)", systemImage: "ruler") }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("LOCATION SCOUT · PREVIS")
                .font(.fsLabel)
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Text("Scan it. Measure it. Frame it. Take it to Unreal.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
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

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: project.name == ProjectStore.quickScanProjectName ? "bolt.fill" : "film")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(summary).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 12)
    }

    private var summary: String {
        let scans = project.locations.reduce(0) { $0 + $1.scans.count }
        let shots = project.locations.reduce(0) { $0 + $1.shots.count }
        return "\(project.locations.count) locations · \(scans) scans · \(shots) shots · \(project.modifiedAt.formatted(.relative(presentation: .named)))"
    }
}
