import Foundation
import RoomPlan

/// Loads heavy scan data from disk and turns it into geometry for previews and export.
enum ScanAssets {
    enum AssetError: LocalizedError {
        case missingData(String)
        var errorDescription: String? {
            switch self {
            case .missingData(let what): return "Scan data is missing (\(what))."
            }
        }
    }

    static func roomElements(_ ref: LocationRef, scanID: UUID) throws -> RoomElements {
        let structureURL = StoragePaths.scanFile(ref, scanID: scanID, .structure)
        if let data = try? Data(contentsOf: structureURL) {
            let structure = try JSONDecoder().decode(CapturedStructure.self, from: data)
            return RoomElements(structure: structure)
        }
        let roomsURL = StoragePaths.scanFile(ref, scanID: scanID, .rooms)
        guard let data = try? Data(contentsOf: roomsURL) else { throw AssetError.missingData("rooms.json") }
        let rooms = try JSONDecoder().decode([CapturedRoom].self, from: data)
        return RoomElements(rooms: rooms)
    }

    static func mesh(_ ref: LocationRef, scanID: UUID) throws -> MeshScanData {
        let url = StoragePaths.scanFile(ref, scanID: scanID, .mesh)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw AssetError.missingData("mesh.fsmesh")
        }
        return try MeshScanData(data: data)
    }

    static func geometry(for scan: ScanRecord, ref: LocationRef,
                         options: RoomPlanConverter.GeometryOptions = .init()) throws -> SceneGeometry {
        var scene: SceneGeometry
        switch scan.kind {
        case .room:
            scene = RoomPlanConverter.sceneGeometry(try roomElements(ref, scanID: scan.id), options: options)
        case .mesh:
            scene = try mesh(ref, scanID: scan.id).sceneGeometry()
        }
        scene.metadata["units"] = "metres"
        scene.metadata["up_axis"] = "Y"
        scene.metadata["scan_id"] = scan.id.uuidString
        scene.metadata["scan_name"] = scan.name
        if let north = scan.northOffset {
            scene.metadata["north_offset_deg"] = String(format: "%.1f", north)
        }
        return scene
    }
}
