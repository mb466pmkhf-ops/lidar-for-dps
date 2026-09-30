import Foundation
import SwiftUI

/// Local, offline-first project database. One JSON document per project plus binary assets
/// (photos, scan data) in the project folder. No account or network needed.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var lastError: String?

    static let quickScanProjectName = "Quick Scans"

    private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    private var planCache: [UUID: FloorPlan] = [:]
    private let fm = FileManager.default

    init() {
        StoragePaths.ensureDirectory(StoragePaths.projectsRoot)
        load()
    }

    // MARK: Loading & saving

    func load() {
        let dirs = (try? fm.contentsOfDirectory(at: StoragePaths.projectsRoot,
                                                 includingPropertiesForKeys: nil)) ?? []
        var loaded: [Project] = []
        for dir in dirs {
            let file = dir.appendingPathComponent(StoragePaths.projectFileName)
            guard let data = try? Data(contentsOf: file) else { continue }
            do {
                var project = try JSONCoding.decoder.decode(Project.self, from: data)
                // The folder name is the source of truth for the id.
                if let folderID = UUID(uuidString: dir.lastPathComponent), folderID != project.id {
                    project.id = folderID
                }
                loaded.append(project)
            } catch {
                lastError = "Could not read \(dir.lastPathComponent): \(error.localizedDescription)"
            }
        }
        projects = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func writeNow(_ project: Project) {
        let dir = StoragePaths.projectDir(project.id)
        StoragePaths.ensureDirectory(dir)
        do {
            let data = try JSONCoding.encoder.encode(project)
            try data.write(to: StoragePaths.projectFile(project.id), options: .atomic)
        } catch {
            lastError = "Could not save \(project.name): \(error.localizedDescription)"
        }
    }

    /// Debounced save so typing into notes doesn't hammer the disk.
    private func scheduleSave(_ projectID: UUID) {
        pendingSaves[projectID]?.cancel()
        pendingSaves[projectID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self, let project = self.project(projectID) else { return }
            self.writeNow(project)
            self.pendingSaves[projectID] = nil
        }
    }

    /// Flush any pending writes (called when the app goes to the background).
    func flush() {
        for (id, task) in pendingSaves {
            task.cancel()
            if let p = project(id) { writeNow(p) }
        }
        pendingSaves.removeAll()
    }

    // MARK: Queries

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func location(_ ref: LocationRef) -> Location? {
        project(ref.projectID)?.locations.first { $0.id == ref.locationID }
    }

    var recentProjects: [Project] { projects.sorted { $0.modifiedAt > $1.modifiedAt } }

    /// Every location across every project (used by compare and pickers).
    var allLocationRefs: [(project: Project, location: Location)] {
        recentProjects.flatMap { p in p.locations.map { (p, $0) } }
    }

    // MARK: Project mutations

    @discardableResult
    func createProject(name: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed.isEmpty ? "Untitled Project" : trimmed)
        projects.insert(project, at: 0)
        writeNow(project)
        return project
    }

    func updateProject(_ id: UUID, _ mutate: (inout Project) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        mutate(&projects[i])
        projects[i].modifiedAt = Date()
        scheduleSave(id)
    }

    func renameProject(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateProject(id) { $0.name = trimmed }
    }

    @discardableResult
    func duplicateProject(_ id: UUID) -> Project? {
        guard var copy = project(id) else { return nil }
        flush()
        let newID = UUID()
        do {
            try fm.copyItem(at: StoragePaths.projectDir(id), to: StoragePaths.projectDir(newID))
        } catch {
            lastError = "Duplicate failed: \(error.localizedDescription)"
            return nil
        }
        copy.id = newID
        copy.name += " Copy"
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        projects.insert(copy, at: 0)
        writeNow(copy)
        return copy
    }

    func deleteProject(_ id: UUID) {
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        try? fm.removeItem(at: StoragePaths.projectDir(id))
        projects.removeAll { $0.id == id }
    }

    /// The project quick scans / quick measurements land in when started from the home screen.
    func quickScanProjectID() -> UUID {
        if let existing = projects.first(where: { $0.name == Self.quickScanProjectName }) {
            return existing.id
        }
        return createProject(name: Self.quickScanProjectName).id
    }

    // MARK: Location mutations

    @discardableResult
    func addLocation(to projectID: UUID, name: String) -> LocationRef? {
        guard project(projectID) != nil else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = Location(name: trimmed.isEmpty ? "New Location" : trimmed)
        updateProject(projectID) { $0.locations.append(location) }
        let ref = LocationRef(projectID: projectID, locationID: location.id)
        StoragePaths.ensureDirectory(StoragePaths.locationDir(ref))
        return ref
    }

    func updateLocation(_ ref: LocationRef, _ mutate: (inout Location) -> Void) {
        updateProject(ref.projectID) { project in
            guard let i = project.locations.firstIndex(where: { $0.id == ref.locationID }) else { return }
            mutate(&project.locations[i])
        }
    }

    func deleteLocation(_ ref: LocationRef) {
        updateProject(ref.projectID) { $0.locations.removeAll { $0.id == ref.locationID } }
        try? fm.removeItem(at: StoragePaths.locationDir(ref))
    }

    /// Two-way binding into a stored location, for forms.
    func binding(for ref: LocationRef) -> Binding<Location> {
        Binding(
            get: { self.location(ref) ?? Location(name: "") },
            set: { newValue in self.updateLocation(ref) { $0 = newValue } }
        )
    }

    // MARK: Photos

    @discardableResult
    func addPhoto(_ jpeg: Data, to ref: LocationRef, source: PhotoSource, caption: String = "",
                  pose: PhotoPose? = nil, lensDescription: String? = nil) -> ReferencePhoto? {
        let photo = ReferencePhoto(fileName: "\(UUID().uuidString).jpg", caption: caption,
                                   source: source, pose: pose, lensDescription: lensDescription)
        StoragePaths.ensureDirectory(StoragePaths.photosDir(ref))
        do {
            try jpeg.write(to: StoragePaths.photoURL(ref, photo), options: .atomic)
        } catch {
            lastError = "Could not save photo: \(error.localizedDescription)"
            return nil
        }
        updateLocation(ref) { $0.photos.append(photo) }
        return photo
    }

    func deletePhoto(_ photo: ReferencePhoto, from ref: LocationRef) {
        try? fm.removeItem(at: StoragePaths.photoURL(ref, photo))
        updateLocation(ref) { loc in
            loc.photos.removeAll { $0.id == photo.id }
            for i in loc.shots.indices where loc.shots[i].photoID == photo.id { loc.shots[i].photoID = nil }
        }
    }

    // MARK: Scans

    func addScan(_ record: ScanRecord, to ref: LocationRef) {
        updateLocation(ref) { loc in
            loc.scans.append(record)
            loc.primaryScanID = record.id
        }
        flush()
    }

    func deleteScan(_ scanID: UUID, from ref: LocationRef) {
        try? fm.removeItem(at: StoragePaths.scanDir(ref, scanID: scanID))
        planCache[scanID] = nil
        updateLocation(ref) { loc in
            loc.scans.removeAll { $0.id == scanID }
            if loc.primaryScanID == scanID { loc.primaryScanID = loc.scans.last?.id }
        }
    }

    func floorPlan(_ ref: LocationRef, scanID: UUID) -> FloorPlan? {
        if let cached = planCache[scanID] { return cached }
        let url = StoragePaths.scanFile(ref, scanID: scanID, .plan)
        guard let data = try? Data(contentsOf: url),
              let plan = try? JSONCoding.decoder.decode(FloorPlan.self, from: data) else { return nil }
        planCache[scanID] = plan
        return plan
    }

    // MARK: Import

    /// Imports a project backup ZIP produced by "Export Project Backup".
    @discardableResult
    func importProject(from zipURL: URL) throws -> Project {
        let archive = try ZipReader(url: zipURL)
        guard let manifest = archive.entries
            .filter({ $0.path.hasSuffix(StoragePaths.projectFileName) && !$0.path.contains("__MACOSX") })
            .min(by: { $0.path.count < $1.path.count }) else {
            throw ImportError.notAProject
        }
        let rootPrefix = String(manifest.path.dropLast(StoragePaths.projectFileName.count))

        var project = try JSONCoding.decoder.decode(Project.self, from: try archive.data(for: manifest))
        project.id = UUID()
        if projects.contains(where: { $0.name == project.name }) { project.name += " (Imported)" }
        project.modifiedAt = Date()

        let destination = StoragePaths.projectDir(project.id)
        StoragePaths.ensureDirectory(destination)
        for entry in archive.entries where entry.path.hasPrefix(rootPrefix) && !entry.isDirectory {
            let relative = String(entry.path.dropFirst(rootPrefix.count))
            guard !relative.isEmpty, !relative.contains(".."), relative != StoragePaths.projectFileName else { continue }
            let target = destination.appendingPathComponent(relative)
            StoragePaths.ensureDirectory(target.deletingLastPathComponent())
            try archive.data(for: entry).write(to: target, options: .atomic)
        }
        projects.insert(project, at: 0)
        writeNow(project)
        return project
    }

    enum ImportError: LocalizedError {
        case notAProject
        var errorDescription: String? { "This archive is not a FrameScout project backup (no project.json found)." }
    }
}
