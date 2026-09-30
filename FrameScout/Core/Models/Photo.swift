import Foundation

enum PhotoSource: String, Codable {
    case camera, library, scan, viewfinder
}

/// Where a photo was taken inside a scan, when known (photos snapped during a LiDAR scan).
struct PhotoPose: Codable, Hashable {
    var scanID: UUID
    var position: PlanPoint
    var height: Double
    /// World bearing of the lens direction (see `PlanPoint.worldBearing`).
    var bearing: Double
}

struct ReferencePhoto: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var caption: String = ""
    var createdAt: Date = Date()
    var source: PhotoSource
    var pose: PhotoPose? = nil
    /// Lens/sensor info burned in when captured through the Lens Viewfinder.
    var lensDescription: String? = nil
}
