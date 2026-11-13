import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var sync = CloudSync.shared
    @AppStorage(UnitsFormatter.imperialKey) private var useImperial = false
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var showImporter = false
    @State private var showSync = false
    @State private var showAbout = false
    @State private var showDrawRoom = false
    @State private var showListing = false
    @AppStorage(Theme.nightKey) private var night = false
    @State private var importMessage: String?
    /// Projects sit at the top of Home, so only the most recent few show until the user expands the list.
    @State private var showAllProjects = false
    private let collapsedProjectCount = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomeStyle.sectionSpacing) {
                // Projects first: returning users go straight back to their work.
                VStack(alignment: .leading, spacing: 12) {
                    HomeSectionHeader(title: "Projects", action: {
                        newProjectName = ""
                        showNewProject = true
                    }, actionLabel: "New")
                    if store.recentProjects.isEmpty {
                        EmptyStateView(systemImage: "film", title: "No projects yet",
                                       message: "Make a project for each production, then add locations, scans and props to it.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleProjects.enumerated()), id: \.element.id) { i, project in
                                if i > 0 { Divider().padding(.leading, 88) }
                                Button { router.open(.project(project.id)) } label: {
                                    ProjectRow(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { projectMenu(project) }
                            }
                        }
                        .homeCard()
                        if store.recentProjects.count > collapsedProjectCount {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showAllProjects.toggle() }
                            } label: {
                                Label(showAllProjects ? "Show fewer" : "Show all \(store.recentProjects.count) projects",
                                      systemImage: showAllProjects ? "chevron.up" : "chevron.down")
                                    .font(HomeStyle.button)
                                    .foregroundStyle(HomeStyle.accent)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // One scan button when the phone can scan, then the other ways in as a plain list.
                // Tools the phone can't run are left out instead of shown as locked tiles; the line at
                // the bottom says what this phone supports.
                if DeviceCapabilities.hasLiDAR {
                    Button { router.start(.scan(.quick)) } label: {
                        Label("Scan a location", systemImage: "viewfinder")
                            .font(HomeStyle.button)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(HomePrimaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    HomeSectionHeader(title: "Start")
                    VStack(spacing: 0) {
                        ForEach(Array(startRows.enumerated()), id: \.offset) { i, row in
                            if i > 0 { Divider().padding(.leading, 42) }
                            HomeMenuRow(title: row.title, subtitle: row.subtitle, systemImage: row.image, action: row.action)
                        }
                    }
                    .homeCard()
                }

                VStack(spacing: 0) {
                    HomeMenuRow(title: syncTitle, subtitle: syncSubtitle,
                                systemImage: sync.email == nil ? "person.crop.circle.badge.plus" : "checkmark.icloud") {
                        showSync = true
                    }
                    .accessibilityHint("Sign in or create an account to sync with the web and desktop planner")
                    Divider().padding(.leading, 42)
                    HomeMenuRow(title: "Export", subtitle: "Unreal, USD, OBJ, GLB or ZIP", systemImage: "square.and.arrow.up") {
                        router.open(.export(projectID: nil, location: nil))
                    }
                    if store.recentProjects.reduce(0, { $0 + $1.locations.count }) > 1 {
                        Divider().padding(.leading, 42)
                        HomeMenuRow(title: "Compare locations", subtitle: "Side by side: size, ceiling, windows", systemImage: "rectangle.split.2x1") {
                            router.open(.compare)
                        }
                    }
                }
                .homeCard()

                Label(DeviceCapabilities.summary, systemImage: DeviceCapabilities.hasLiDAR ? "checkmark.circle" : "info.circle")
                    .font(HomeStyle.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .fsScreen()
        .navigationTitle("FrameScan")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { night.toggle() } label: {
                    Label(night ? "Day" : "Night", systemImage: night ? "sun.max" : "moon")
                        .labelStyle(.titleAndIcon)
                        .font(HomeStyle.button)
                        .foregroundStyle(HomeStyle.accent)
                }
                .accessibilityHint(night ? "Back to the bright screen" : "Dim, dark screen for a dark set")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSync = true } label: {
                    Image(systemName: sync.email == nil ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                        .font(.title3).foregroundStyle(HomeStyle.accent)
                }
                .accessibilityLabel(sync.email == nil ? "Sign in" : "Account and sync")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Import and sign-in have their own rows and button; this menu is only for settings.
                    Toggle(isOn: $useImperial) { Label("Imperial units (ft/in)", systemImage: "ruler") }
                    Button { showAbout = true } label: { Label("About FrameScout", systemImage: "info.circle") }
                } label: {
                    Image(systemName: "gearshape").font(.title3).foregroundStyle(HomeStyle.accent)
                }
                .accessibilityLabel("Settings")
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
        .sheet(isPresented: $showSync) { SyncSettingsView() }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showDrawRoom) { DrawRoomView() }
        .sheet(isPresented: $showListing) { listingSheet }
#if DEBUG
        .onAppear { if DemoContent.isEnabled && DemoContent.screen == .listing { showListing = true } }
#endif
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            importProject(result)
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var visibleProjects: [Project] {
        showAllProjects ? store.recentProjects : Array(store.recentProjects.prefix(collapsedProjectCount))
    }

    private struct StartRow { let title: String; let subtitle: String?; let image: String; let action: () -> Void }

    /// The ways to start, minus the ones this phone can't do.
    private var startRows: [StartRow] {
        var rows: [StartRow] = []
        if DeviceCapabilities.hasCamera {
            rows.append(StartRow(title: "Viewfinder", subtitle: "Frame lines for your lens", image: "camera.aperture") { router.start(.viewfinder(.quick)) })
        }
        if DeviceCapabilities.supportsWorldTracking {
            rows.append(StartRow(title: "Measure", subtitle: DeviceCapabilities.hasLiDAR ? nil : "Estimated without LiDAR", image: "ruler") { router.start(.measure(.quick)) })
        }
        if ObjectCaptureModel.isSupported {
            rows.append(StartRow(title: "Scan an object", subtitle: "A prop as a textured 3D model", image: "cube") { router.start(.objectScan(projectID: nil)) })
        }
        rows.append(StartRow(title: "Draw a plan", subtitle: "Pick a shape and type the sizes", image: "pencil.and.ruler") { showDrawRoom = true })
        rows.append(StartRow(title: "From a listing", subtitle: "The studio's photos and sizes", image: "photo.on.rectangle.angled") { showListing = true })
        rows.append(StartRow(title: "Import a backup", subtitle: nil, image: "square.and.arrow.down") { showImporter = true })
        return rows
    }

    private var syncTitle: String {
        if sync.config == nil { return "Sync is off" }
        return sync.email == nil ? "Sign in to sync" : "Synced with web & desktop"
    }

    private var syncSubtitle: String {
        if sync.config == nil { return "Turn it on to continue on your computer" }
        guard let email = sync.email else { return "Apple, Google or email · continue on your computer" }
        return "\(email) · \(sync.status.label)"
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
                        .background(HomeStyle.cardRaised)
                }
            }
            .frame(width: 76, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(HomeStyle.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(summary).font(HomeStyle.footnote).foregroundStyle(Theme.textTertiary).lineLimit(2)
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

private extension HomeView {
    @ViewBuilder var listingSheet: some View {
#if DEBUG
        if DemoContent.isEnabled && DemoContent.screen == .listing {
            BuildFromListingView(sampleText: BuildFromListingView.sampleListing)
        } else {
            BuildFromListingView()
        }
#else
        BuildFromListingView()
#endif
    }
}
