import Foundation
import SwiftUI

/// Local, offline-first project database. One JSON document per project plus binary assets
/// (photos, scan data) in the project folder. No account or network needed.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var lastError: String?

    static let quickScanProjectName = "Quick Scans"

    /// Sync hooks (D-007). Called after a local change to a project has been written to disk, and
    /// after a project is deleted. Never called for changes applied with `applyRemote`.
    var onProjectWritten: ((Project) -> Void)?
    var onProjectDeleted: ((UUID) -> Void)?

    private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    private var planCache: [UUID: FloorPlan] = [:]
    /// Plans edited by hand that are waiting to be written (debounced like project saves).
    private var pendingPlanSaves: [UUID: (ref: LocationRef, task: Task<Void, Never>)] = [:]
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

    private func writeNow(_ project: Project, notify: Bool = true) {
        let dir = StoragePaths.projectDir(project.id)
        StoragePaths.ensureDirectory(dir)
        do {
            let data = try JSONCoding.encoder.encode(project)
            try data.write(to: StoragePaths.projectFile(project.id), options: .atomic)
            if notify { onProjectWritten?(project) }
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

    /// Puts a project that changed on another device in place (or adds it) and saves it, without
    /// reporting it back through `onProjectWritten`. Pending local saves for it are dropped: the
    /// caller has already merged them into `project`.
    func applyRemote(_ project: Project) {
        pendingSaves[project.id]?.cancel()
        pendingSaves[project.id] = nil
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.insert(project, at: 0)
        }
        writeNow(project, notify: false)
    }

    /// Flush any pending writes (called when the app goes to the background).
    func flush() {
        for (scanID, pending) in pendingPlanSaves {
            pending.task.cancel()
            writePlanNow(pending.ref, scanID: scanID)
        }
        pendingPlanSaves.removeAll()
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
        onProjectDeleted?(id)
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

    /// Saves a room drawn by hand as a new location: a scan record with only a plan, no mesh.
    @discardableResult
    func addDrawnRoom(_ room: DrawnRoom, name: String, to projectID: UUID) -> LocationRef? {
        guard let ref = addLocation(to: projectID, name: name.isEmpty ? "New room" : name) else { return nil }
        let record = room.scanRecord
        StoragePaths.ensureDirectory(StoragePaths.scanDir(ref, scanID: record.id))
        do {
            try JSONCoding.encoder.encode(room.plan).write(to: StoragePaths.scanFile(ref, scanID: record.id, .plan))
        } catch {
            lastError = "Couldn't save the room: \(error.localizedDescription)"
            deleteLocation(ref)
            return nil
        }
        addScan(record, to: ref)
        return ref
    }

    func deleteScan(_ scanID: UUID, from ref: LocationRef) {
        pendingPlanSaves[scanID]?.task.cancel()
        pendingPlanSaves[scanID] = nil
        try? fm.removeItem(at: StoragePaths.scanDir(ref, scanID: scanID))
        planCache[scanID] = nil
        updateLocation(ref) { loc in
            loc.scans.removeAll { $0.id == scanID }
            if loc.primaryScanID == scanID { loc.primaryScanID = loc.scans.last?.id }
        }
    }

    /// Replaces a scan's 2D plan after an edit by hand (doors, windows, set pieces). The change shows
    /// at once; the file is written shortly after, and the project is marked changed so it syncs.
    func setFloorPlan(_ plan: FloorPlan, _ ref: LocationRef, scanID: UUID) {
        guard floorPlan(ref, scanID: scanID) != plan else { return }
        objectWillChange.send()
        planCache[scanID] = plan
        pendingPlanSaves[scanID]?.task.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writePlanNow(ref, scanID: scanID)
            self.pendingPlanSaves[scanID] = nil
        }
        pendingPlanSaves[scanID] = (ref, task)
        // Touching the project saves it, which tells sync something changed.
        updateProject(ref.projectID) { _ in }
    }

    private func writePlanNow(_ ref: LocationRef, scanID: UUID) {
        // The scan may have gone (deleted with its location or project) while the write waited.
        guard let plan = planCache[scanID], location(ref)?.scans.contains(where: { $0.id == scanID }) == true else { return }
        let url = StoragePaths.scanFile(ref, scanID: scanID, .plan)
        StoragePaths.ensureDirectory(url.deletingLastPathComponent())
        do {
            try JSONCoding.encoder.encode(plan).write(to: url, options: .atomic)
        } catch {
            lastError = "Couldn't save the plan: \(error.localizedDescription)"
        }
    }

    /// A plan that changed on another device: replaces the file and the cached copy, without
    /// reporting it back to sync.
    func applyRemotePlan(_ plan: FloorPlan, _ ref: LocationRef, scanID: UUID) {
        pendingPlanSaves[scanID]?.task.cancel()
        pendingPlanSaves[scanID] = nil
        objectWillChange.send()
        planCache[scanID] = plan
        writePlanNow(ref, scanID: scanID)
    }

    func floorPlan(_ ref: LocationRef, scanID: UUID) -> FloorPlan? {
        if let cached = planCache[scanID] { return cached }
        let url = StoragePaths.scanFile(ref, scanID: scanID, .plan)
        guard let data = try? Data(contentsOf: url),
              let plan = try? JSONCoding.decoder.decode(FloorPlan.self, from: data) else { return nil }
        planCache[scanID] = plan
        return plan
    }

    // MARK: Objects

    func object(_ projectID: UUID, _ objectID: UUID) -> CapturedObject? {
        project(projectID)?.objects.first { $0.id == objectID }
    }

    /// Creates the record and its folder before capture starts, so images land in place.
    @discardableResult
    func addObject(to projectID: UUID, name: String) -> CapturedObject? {
        guard project(projectID) != nil else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = (project(projectID)?.objects.count ?? 0) + 1
        let object = CapturedObject(name: trimmed.isEmpty ? String(format: "Object %02d", count) : trimmed,
                                    deviceModel: DeviceCapabilities.modelIdentifier)
        StoragePaths.ensureDirectory(StoragePaths.objectFile(projectID, objectID: object.id, .images))
        updateProject(projectID) { $0.objects.append(object) }
        flush()
        return object
    }

    func updateObject(_ projectID: UUID, _ objectID: UUID, _ mutate: (inout CapturedObject) -> Void) {
        updateProject(projectID) { project in
            guard let i = project.objects.firstIndex(where: { $0.id == objectID }) else { return }
            mutate(&project.objects[i])
        }
    }

    func deleteObject(_ projectID: UUID, _ objectID: UUID) {
        try? fm.removeItem(at: StoragePaths.objectDir(projectID, objectID: objectID))
        updateProject(projectID) { $0.objects.removeAll { $0.id == objectID } }
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
        let root = destination.standardizedFileURL.path + "/"
        for entry in archive.entries where entry.path.hasPrefix(rootPrefix) && !entry.isDirectory {
            let relative = String(entry.path.dropFirst(rootPrefix.count))
            guard !relative.isEmpty, !relative.contains(".."),
                  relative != StoragePaths.projectFileName else { continue }
            let target = destination.appendingPathComponent(relative).standardizedFileURL
            guard target.path.hasPrefix(root) else { continue }
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
