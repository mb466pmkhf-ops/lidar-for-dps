import Foundation

enum ScanKind: String, Codable {
    /// Apple RoomPlan: parametric walls, doors, windows, openings, floors and furniture. Interiors.
    case room
    /// Raw ARKit LiDAR scene-reconstruction mesh. Exteriors, irregular or very large spaces.
    case mesh

    var label: String {
        switch self {
        case .room: return "Room Scan"
        case .mesh: return "LiDAR Mesh"
        }
    }

    var detail: String {
        switch self {
        case .room: return "RoomPlan · walls, doors, windows, furniture"
        case .mesh: return "Scene reconstruction · raw surface mesh"
        }
    }
}

/// One saved LiDAR capture. Heavy data lives on disk in the scan folder (see `StoragePaths`).
struct ScanRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: ScanKind
    var createdAt: Date = Date()
    /// Number of RoomPlan capture segments merged into this scan (pause/resume creates segments).
    var segmentCount: Int = 1
    var stats: ScanStats
    /// Compass bearing (degrees clockwise from true north) of the scan's -Z world axis.
    /// Sampled from CoreMotion during the scan; editable because indoor compasses drift.
    var northOffset: Double? = nil
    var measuredNorthOffset: Double? = nil
    var deviceModel: String = ""
    var notes: String = ""
}

struct OpeningSize: Codable, Hashable {
    var width: Double
    var height: Double
    /// Height of the bottom edge above the floor (0 for doors, sill height for windows).
    var sillHeight: Double
}

struct ScanStats: Codable, Hashable {
    var floorArea: Double? = nil
    /// True when floor area is derived from the bounding box rather than detected floor polygons.
    var floorAreaIsEstimate: Bool = false
    /// Shorter horizontal room dimension along the dominant wall direction (m).
    var width: Double? = nil
    /// Longer horizontal room dimension along the dominant wall direction (m).
    var length: Double? = nil
    /// Ceiling height derived from wall heights (RoomPlan) or ceiling-classified mesh (LiDAR mesh).
    var ceilingHeight: Double? = nil
    var minCeilingHeight: Double? = nil
    var wallCount: Int = 0
    var doorCount: Int = 0
    var windowCount: Int = 0
    var openingCount: Int = 0
    var floorCount: Int = 0
    var objectCount: Int = 0
    var objectCategories: [String: Int] = [:]
    var doors: [OpeningSize] = []
    var windows: [OpeningSize] = []
    /// Heuristic 0...1 estimate of how complete the room capture is (RoomPlan only).
    var completeness: Double? = nil
    var meshVertexCount: Int = 0
    var meshFaceCount: Int = 0
}

// MARK: - Top-down plan (derived from a scan, renderer-agnostic)

/// World-space point projected onto the floor plane. `x` and `z` are ARKit world metres.
struct PlanPoint: Codable, Hashable {
    var x: Double
    var z: Double

    static let zero = PlanPoint(x: 0, z: 0)

    func distance(to other: PlanPoint) -> Double {
        ((x - other.x) * (x - other.x) + (z - other.z) * (z - other.z)).squareRoot()
    }

    static func + (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x + b.x, z: a.z + b.z) }
    static func - (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(x: a.x - b.x, z: a.z - b.z) }
    static func * (a: PlanPoint, s: Double) -> PlanPoint { PlanPoint(x: a.x * s, z: a.z * s) }

    /// Bearing in the scan's world frame: 0° = -Z (plan "up"), 90° = +X. Clockwise seen from above.
    var worldBearing: Double {
        let deg = atan2(x, -z) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    /// Unit vector for a world bearing (inverse of `worldBearing`).
    static func unit(bearing degrees: Double) -> PlanPoint {
        let r = degrees * .pi / 180
        return PlanPoint(x: sin(r), z: -cos(r))
    }
}

struct PlanRect: Codable, Hashable {
    var minX: Double
    var minZ: Double
    var maxX: Double
    var maxZ: Double

    var width: Double { maxX - minX }
    var depth: Double { maxZ - minZ }
    var center: PlanPoint { PlanPoint(x: (minX + maxX) / 2, z: (minZ + maxZ) / 2) }

    static let unit = PlanRect(minX: -2.5, minZ: -2.5, maxX: 2.5, maxZ: 2.5)

    static func enclosing(_ points: [PlanPoint]) -> PlanRect? {
        guard let first = points.first else { return nil }
        var r = PlanRect(minX: first.x, minZ: first.z, maxX: first.x, maxZ: first.z)
        for p in points.dropFirst() {
            r.minX = min(r.minX, p.x); r.maxX = max(r.maxX, p.x)
            r.minZ = min(r.minZ, p.z); r.maxZ = max(r.maxZ, p.z)
        }
        return r
    }

    func union(_ other: PlanRect) -> PlanRect {
        PlanRect(minX: min(minX, other.minX), minZ: min(minZ, other.minZ),
                 maxX: max(maxX, other.maxX), maxZ: max(maxZ, other.maxZ))
    }
}

enum PlanSegmentKind: String, Codable {
    case wall, door, window, opening
}

struct PlanSegment: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: PlanSegmentKind
    var a: PlanPoint
    var b: PlanPoint
    var height: Double
    /// Bottom edge height above floor.
    var bottom: Double
    var isOpen: Bool = false

    var length: Double { a.distance(to: b) }
    var midpoint: PlanPoint { PlanPoint(x: (a.x + b.x) / 2, z: (a.z + b.z) / 2) }
}

struct PlanObject: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var category: String
    var center: PlanPoint
    var width: Double
    var depth: Double
    var height: Double
    /// Rotation of the object's local X axis in the plan, radians (screen space: x right, z down).
    var rotation: Double
}

struct FloorPlan: Codable, Hashable {
    var walls: [PlanSegment] = []
    var doors: [PlanSegment] = []
    var windows: [PlanSegment] = []
    var openings: [PlanSegment] = []
    var floorPolygons: [[PlanPoint]] = []
    var objects: [PlanObject] = []
    /// LiDAR mesh scans: occupied floor cells (obstacles between knee and head height).
    var occupancy: [PlanPoint] = []
    var occupancyCellSize: Double = 0.1
    /// World Y of the floor.
    var floorY: Double = 0
    var bounds: PlanRect = .unit

    static let empty = FloorPlan()

    var isEmpty: Bool {
        walls.isEmpty && floorPolygons.isEmpty && occupancy.isEmpty && objects.isEmpty
    }

    /// Centroid used to decide which side of a wall is "outside".
    var interiorCentroid: PlanPoint {
        let pts = floorPolygons.flatMap { $0 }
        let source = pts.isEmpty ? walls.flatMap { [$0.a, $0.b] } : pts
        guard !source.isEmpty else { return bounds.center }
        let sum = source.reduce(PlanPoint.zero, +)
        return sum * (1.0 / Double(source.count))
    }

    /// Outward-facing world bearing of a wall-mounted segment (window/door), pointing away from the room.
    func outwardBearing(of segment: PlanSegment) -> Double {
        let d = segment.b - segment.a
        var n = PlanPoint(x: -d.z, z: d.x)
        let toCentre = interiorCentroid - segment.midpoint
        if n.x * toCentre.x + n.z * toCentre.z > 0 { n = n * -1 }
        return n.worldBearing
    }
}
