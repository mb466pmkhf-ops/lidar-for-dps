import ARKit
import CoreImage
import Foundation
import ImageIO
import Metal
import RoomPlan
import UIKit

/// Photo snapped from the live AR feed during a scan, with the camera pose in scan space.
struct PendingPhoto: Identifiable {
    let id = UUID()
    var jpeg: Data
    var position: PlanPoint
    var worldY: Double
    var bearing: Double
    var createdAt = Date()
    var thumbnail: UIImage?
}

enum ScanResult {
    case room(rooms: [CapturedRoom], structure: CapturedStructure?)
    case mesh(MeshScanData)

    var kind: ScanKind {
        switch self {
        case .room: return .room
        case .mesh: return .mesh
        }
    }
}

/// Live figures shown while scanning.
struct LiveScanInfo {
    var stats = ScanStats()
    var elapsed: TimeInterval = 0
    var segments = 0
    var northOffset: Double?
}

enum ScanPhase: Equatable {
    case ready
    case scanning
    /// RoomPlan is processing the segment just captured (after pause or finish).
    case processing
    case paused
    case finalizing
    case finished
    case failed(String)
}

enum FrameGrabber {
    private static let context = CIContext()

    /// JPEG of the current AR camera frame, rotated to match how the phone is held.
    static func jpeg(from frame: ARFrame, quality: CGFloat = 0.85) -> Data? {
        let orientation: CGImagePropertyOrientation
        switch UIDevice.current.orientation {
        case .landscapeLeft: orientation = .up
        case .landscapeRight: orientation = .down
        case .portraitUpsideDown: orientation = .left
        default: orientation = .right
        }
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(orientation)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        return context.jpegRepresentation(of: image, colorSpace: space, options: options)
    }

    static func pendingPhoto(from frame: ARFrame) -> PendingPhoto? {
        guard let jpeg = jpeg(from: frame) else { return nil }
        let t = frame.camera.transform
        let forward = PlanPoint(x: Double(-t.columns.2.x), z: Double(-t.columns.2.z))
        return PendingPhoto(jpeg: jpeg,
                            position: PlanPoint(x: Double(t.columns.3.x), z: Double(t.columns.3.z)),
                            worldY: Double(t.columns.3.y),
                            bearing: forward.worldBearing,
                            thumbnail: UIImage(data: jpeg)?.downsampled(maxPixel: 160))
    }
}

/// Converts ARKit mesh anchors (anchor-local chunks) into one world-space mesh.
enum MeshExtractor {
    static func extract(_ anchors: [ARMeshAnchor]) -> MeshScanData {
        var data = MeshScanData()
        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let base = UInt32(data.positions.count)

            let vertices = geometry.vertices
            let vPtr = vertices.buffer.contents()
            data.positions.reserveCapacity(data.positions.count + vertices.count)
            for i in 0..<vertices.count {
                let o = vertices.offset + vertices.stride * i
                let local = SIMD4<Float>(vPtr.load(fromByteOffset: o, as: Float.self),
                                         vPtr.load(fromByteOffset: o + 4, as: Float.self),
                                         vPtr.load(fromByteOffset: o + 8, as: Float.self), 1)
                let w = transform * local
                data.positions.append(Vec3(w.x, w.y, w.z))
            }

            let normals = geometry.normals
            let nPtr = normals.buffer.contents()
            for i in 0..<vertices.count {
                guard i < normals.count else { data.normals.append(Vec3(0, 1, 0)); continue }
                let o = normals.offset + normals.stride * i
                let local = SIMD4<Float>(nPtr.load(fromByteOffset: o, as: Float.self),
                                         nPtr.load(fromByteOffset: o + 4, as: Float.self),
                                         nPtr.load(fromByteOffset: o + 8, as: Float.self), 0)
                let w = transform * local
                data.normals.append(V3.normalized(Vec3(w.x, w.y, w.z)))
            }

            let faces = geometry.faces
            let fPtr = faces.buffer.contents()
            let perFace = faces.indexCountPerPrimitive
            let bytes = faces.bytesPerIndex
            for f in 0..<faces.count {
                for k in 0..<min(perFace, 3) {
                    let o = (f * perFace + k) * bytes
                    let index: UInt32 = bytes == 4
                        ? fPtr.load(fromByteOffset: o, as: UInt32.self)
                        : UInt32(fPtr.load(fromByteOffset: o, as: UInt16.self))
                    data.indices.append(base + index)
                }
            }

            if let classification = geometry.classification {
                let cPtr = classification.buffer.contents()
                for f in 0..<faces.count {
                    let value = f < classification.count
                        ? cPtr.load(fromByteOffset: classification.offset + classification.stride * f, as: UInt8.self)
                        : 0
                    data.faceClasses.append(value)
                }
            } else {
                data.faceClasses += Array(repeating: 0, count: faces.count)
            }
        }
        return data
    }
}

/// Writes a finished scan to disk and registers it with the store.
enum ScanSaver {
    struct Request {
        var result: ScanResult
        var scanName: String
        var notes: String
        var northOffset: Double?
        var photos: [PendingPhoto]
        var segmentCount: Int
    }

    struct Prepared {
        var record: ScanRecord
        var plan: FloorPlan
    }

    /// Heavy work (encoding, plan/stat derivation, USDZ export). Runs off the main actor.
    static func prepare(_ request: Request, scanDir: URL) throws -> Prepared {
        StoragePaths.ensureDirectory(scanDir)
        let plan: FloorPlan
        let stats: ScanStats

        switch request.result {
        case .room(let rooms, let structure):
            let encoder = JSONEncoder()
            try encoder.encode(rooms).write(to: scanDir.appendingPathComponent(StoragePaths.ScanFile.rooms.rawValue))
            let elements: RoomElements
            if let structure {
                try encoder.encode(structure).write(to: scanDir.appendingPathComponent(StoragePaths.ScanFile.structure.rawValue))
                elements = RoomElements(structure: structure)
            } else {
                elements = RoomElements(rooms: rooms)
            }
            if rooms.count == 1, let room = rooms.first {
                // Apple's own parametric USDZ, kept alongside FrameScout's exports.
                try? room.export(to: scanDir.appendingPathComponent(StoragePaths.ScanFile.roomPlanUSDZ.rawValue),
                                 metadataURL: nil, modelProvider: nil, exportOptions: .parametric)
            }
            plan = RoomPlanConverter.floorPlan(elements)
            stats = RoomPlanConverter.stats(elements, plan: plan)

        case .mesh(let mesh):
            try mesh.encoded().write(to: scanDir.appendingPathComponent(StoragePaths.ScanFile.mesh.rawValue))
            let analysis = mesh.analyse()
            plan = analysis.plan
            stats = analysis.stats
        }

        try JSONCoding.encoder.encode(plan).write(to: scanDir.appendingPathComponent(StoragePaths.ScanFile.plan.rawValue))

        let record = ScanRecord(name: request.scanName, kind: request.result.kind,
                                segmentCount: request.segmentCount, stats: stats,
                                northOffset: request.northOffset, measuredNorthOffset: request.northOffset,
                                deviceModel: DeviceCapabilities.modelIdentifier, notes: request.notes)
        return Prepared(record: record, plan: plan)
    }

    @MainActor
    static func save(_ request: Request, locationName: String, target: CaptureTarget,
                     store: ProjectStore) async throws -> LocationRef {
        // Resolve / create the destination location.
        let projectID = target.projectID ?? store.quickScanProjectID()
        let ref: LocationRef
        if let existing = target.locationRef, store.location(existing) != nil {
            ref = existing
        } else {
            guard let created = store.addLocation(to: projectID, name: locationName) else {
                throw CocoaError(.fileWriteUnknown)
            }
            ref = created
        }

        let scanID = UUID()
        let scanDir = StoragePaths.scanDir(ref, scanID: scanID)
        let prepared = try await Task.detached(priority: .userInitiated) {
            try ScanSaver.prepare(request, scanDir: scanDir)
        }.value
        var record = prepared.record
        record.id = scanID
        store.addScan(record, to: ref)

        let name = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            store.updateLocation(ref) { $0.name = name }
        }

        for (i, photo) in request.photos.enumerated() {
            let pose = PhotoPose(scanID: scanID, position: photo.position,
                                 height: photo.worldY - prepared.plan.floorY, bearing: photo.bearing)
            store.addPhoto(photo.jpeg, to: ref, source: .scan, caption: "Scan photo \(i + 1)", pose: pose)
        }
        return ref
    }
}
