import Foundation

/// On-device layout (all inside the app's Documents folder, which is visible in the Files app):
///
///     Documents/
///       Projects/<projectID>/project.json
///       Projects/<projectID>/Locations/<locationID>/Photos/<photo>.jpg
///       Projects/<projectID>/Locations/<locationID>/Scans/<scanID>/{rooms.json, structure.json, plan.json, mesh.fsmesh, roomplan.usdz}
///       Exports/…            (generated packages, safe to delete)
enum StoragePaths {
    static let projectFileName = "project.json"

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var projectsRoot: URL { documents.appendingPathComponent("Projects", isDirectory: true) }
    static var exportsRoot: URL { documents.appendingPathComponent("Exports", isDirectory: true) }

    static func projectDir(_ projectID: UUID) -> URL {
        projectsRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    static func projectFile(_ projectID: UUID) -> URL {
        projectDir(projectID).appendingPathComponent(projectFileName)
    }

    static func locationDir(_ ref: LocationRef) -> URL {
        projectDir(ref.projectID)
            .appendingPathComponent("Locations", isDirectory: true)
            .appendingPathComponent(ref.locationID.uuidString, isDirectory: true)
    }

    static func photosDir(_ ref: LocationRef) -> URL {
        locationDir(ref).appendingPathComponent("Photos", isDirectory: true)
    }

    static func photoURL(_ ref: LocationRef, _ photo: ReferencePhoto) -> URL {
        photosDir(ref).appendingPathComponent(photo.fileName)
    }

    static func scanDir(_ ref: LocationRef, scanID: UUID) -> URL {
        locationDir(ref)
            .appendingPathComponent("Scans", isDirectory: true)
            .appendingPathComponent(scanID.uuidString, isDirectory: true)
    }

    enum ScanFile: String {
        case rooms = "rooms.json"
        case structure = "structure.json"
        case plan = "plan.json"
        case mesh = "mesh.fsmesh"
        case roomPlanUSDZ = "roomplan.usdz"
    }

    static func scanFile(_ ref: LocationRef, scanID: UUID, _ file: ScanFile) -> URL {
        scanDir(ref, scanID: scanID).appendingPathComponent(file.rawValue)
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Makes a string safe for file and folder names ("Warehouse / Stage 2" → "Warehouse_Stage_2").
    static func safeName(_ name: String, fallback: String = "Untitled") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let parts = name.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "_")
        return joined.isEmpty ? fallback : String(joined.prefix(60))
    }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
