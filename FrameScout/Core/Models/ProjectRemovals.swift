import Foundation

/// What a newer copy of a project no longer has, compared with the copy on this device: locations,
/// scans, photos and captured objects deleted on another device. Their files (scan meshes, photos,
/// object models) never sync, so the device that still has them removes them itself when the
/// change arrives, the same way a delete made here does.
struct ProjectRemovals: Equatable {
    struct Scan: Hashable { var locationID: UUID; var scanID: UUID }
    struct Photo: Hashable { var locationID: UUID; var photo: ReferencePhoto }

    /// Whole locations: their folder (scans and photos inside it) goes.
    var locations: [UUID] = []
    /// Scans gone from a location that is still there.
    var scans: [Scan] = []
    /// Photos gone from a location that is still there.
    var photos: [Photo] = []
    var objects: [UUID] = []

    var isEmpty: Bool { locations.isEmpty && scans.isEmpty && photos.isEmpty && objects.isEmpty }

    init(from old: Project, to new: Project) {
        let newLocations = Dictionary(new.locations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for location in old.locations {
            guard let kept = newLocations[location.id] else { locations.append(location.id); continue }
            let keptScans = Set(kept.scans.map(\.id))
            scans += location.scans.filter { !keptScans.contains($0.id) }.map { Scan(locationID: location.id, scanID: $0.id) }
            let keptPhotos = Set(kept.photos.map(\.id))
            photos += location.photos.filter { !keptPhotos.contains($0.id) }.map { Photo(locationID: location.id, photo: $0) }
        }
        let keptObjects = Set(new.objects.map(\.id))
        objects = old.objects.map(\.id).filter { !keptObjects.contains($0) }
    }
}
