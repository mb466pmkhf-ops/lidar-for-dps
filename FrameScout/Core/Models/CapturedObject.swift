import Foundation

/// A single prop or object scanned with Object Capture (a plush toy, a camera body, a hero
/// prop) and reconstructed into a photo-textured model. Lives on the project, not on a
/// location, so props can be reused across locations and exported on their own.
struct CapturedObject: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        /// Images captured, model not built yet (or the build was interrupted).
        case captured
        case ready
        case failed
    }

    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var status: Status = .captured
    var notes: String = ""
    var imageCount: Int = 0
    var scanPasses: Int = 1
    var triangleCount: Int = 0
    var vertexCount: Int = 0
    /// Bounding box in metres: width (x), height (y), depth (z).
    var width: Double = 0
    var height: Double = 0
    var depth: Double = 0
    var deviceModel: String = ""
    var failureReason: String? = nil

    var dimensionsSummary: String? {
        guard width > 0 || height > 0 || depth > 0 else { return nil }
        return [width, height, depth].map { UnitsFormatter.distance($0) }.joined(separator: " × ")
    }
}
