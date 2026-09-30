import Foundation

/// World-space LiDAR mesh captured from ARKit scene reconstruction, with per-face classification.
/// Stored on disk in a compact binary format (`mesh.fsmesh`). Platform-independent.
struct MeshScanData {
    /// Matches `ARMeshClassification` raw values.
    enum Classification: UInt8, CaseIterable {
        case none = 0, wall, floor, ceiling, table, seat, window, door

        var groupName: String {
            switch self {
            case .none: return "Unclassified"
            case .wall: return "Walls"
            case .floor: return "Floor"
            case .ceiling: return "Ceiling"
            case .table: return "Tables"
            case .seat: return "Seats"
            case .window: return "Windows"
            case .door: return "Doors"
            }
        }

        var material: SceneMaterial {
            switch self {
            case .none: return SceneMaterial(name: "Mesh_Unclassified", color: SIMD4(0.62, 0.62, 0.62, 1))
            case .wall: return SceneMaterial(name: "Mesh_Wall", color: SIMD4(0.82, 0.82, 0.80, 1))
            case .floor: return SceneMaterial(name: "Mesh_Floor", color: SIMD4(0.45, 0.42, 0.38, 1))
            case .ceiling: return SceneMaterial(name: "Mesh_Ceiling", color: SIMD4(0.90, 0.90, 0.90, 1))
            case .table: return SceneMaterial(name: "Mesh_Table", color: SIMD4(0.55, 0.45, 0.35, 1))
            case .seat: return SceneMaterial(name: "Mesh_Seat", color: SIMD4(0.45, 0.50, 0.60, 1))
            case .window: return SceneMaterial(name: "Mesh_Window", color: SIMD4(0.55, 0.75, 0.95, 1))
            case .door: return SceneMaterial(name: "Mesh_Door", color: SIMD4(0.42, 0.28, 0.16, 1))
            }
        }
    }

    var positions: [Vec3] = []
    var normals: [Vec3] = []
    /// Triangle list (3 indices per face).
    var indices: [UInt32] = []
    /// One classification per face (`Classification.rawValue`).
    var faceClasses: [UInt8] = []

    var faceCount: Int { indices.count / 3 }
    var vertexCount: Int { positions.count }
    var isEmpty: Bool { indices.isEmpty }

    // MARK: Binary I/O

    private static let magic = Data("FSMESH01".utf8)

    func encoded() -> Data {
        var d = Data()
        d.append(Self.magic)
        var vc = UInt32(positions.count).littleEndian, fc = UInt32(faceCount).littleEndian
        withUnsafeBytes(of: &vc) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &fc) { d.append(contentsOf: $0) }
        var flat: [Float] = []
        flat.reserveCapacity(positions.count * 6)
        for p in positions { flat += [p.x, p.y, p.z] }
        for i in 0..<positions.count {
            let n = i < normals.count ? normals[i] : Vec3(0, 1, 0)
            flat += [n.x, n.y, n.z]
        }
        flat.withUnsafeBytes { d.append(contentsOf: $0) }
        indices.withUnsafeBytes { d.append(contentsOf: $0) }
        var classes = faceClasses
        if classes.count != faceCount { classes = Array(repeating: 0, count: faceCount) }
        d.append(contentsOf: classes)
        return d
    }

    init() {}

    init(data: Data) throws {
        guard data.count >= 16, data.prefix(8) == Self.magic else { throw CocoaError(.fileReadCorruptFile) }
        func u32(_ o: Int) -> Int {
            var v: UInt32 = 0
            for i in 0..<4 { v |= UInt32(data[data.startIndex + o + i]) << (8 * UInt32(i)) }
            return Int(v)
        }
        let vc = u32(8), fc = u32(12)
        let floatsBytes = vc * 6 * 4, indexBytes = fc * 3 * 4
        guard data.count >= 16 + floatsBytes + indexBytes + fc else { throw CocoaError(.fileReadCorruptFile) }
        var floats = [Float](repeating: 0, count: vc * 6)
        floats.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst.bindMemory(to: UInt8.self), from: (data.startIndex + 16)..<(data.startIndex + 16 + floatsBytes))
        }
        indices = [UInt32](repeating: 0, count: fc * 3)
        let iStart = data.startIndex + 16 + floatsBytes
        indices.withUnsafeMutableBytes { dst in
            data.copyBytes(to: dst.bindMemory(to: UInt8.self), from: iStart..<(iStart + indexBytes))
        }
        let cStart = iStart + indexBytes
        faceClasses = [UInt8](data[cStart..<(cStart + fc)])
        positions.reserveCapacity(vc)
        normals.reserveCapacity(vc)
        for i in 0..<vc { positions.append(Vec3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])) }
        let nBase = vc * 3
        for i in 0..<vc { normals.append(Vec3(floats[nBase + i * 3], floats[nBase + i * 3 + 1], floats[nBase + i * 3 + 2])) }
    }

    // MARK: Analysis

    private func faceVertices(_ f: Int) -> (Vec3, Vec3, Vec3) {
        (positions[Int(indices[f * 3])], positions[Int(indices[f * 3 + 1])], positions[Int(indices[f * 3 + 2])])
    }

    private func faceClass(_ f: Int) -> Classification {
        f < faceClasses.count ? Classification(rawValue: faceClasses[f]) ?? .none : .none
    }

    /// Floor height: median of floor-classified faces, or a low percentile of all vertices.
    func estimateFloorY() -> Float {
        var floorYs: [Float] = []
        for f in 0..<faceCount where faceClass(f) == .floor {
            let (a, b, c) = faceVertices(f)
            floorYs.append((a.y + b.y + c.y) / 3)
        }
        if floorYs.count > 20 {
            floorYs.sort()
            return floorYs[floorYs.count / 2]
        }
        let ys = positions.map(\.y).sorted()
        guard !ys.isEmpty else { return 0 }
        return ys[min(ys.count - 1, ys.count / 50)]
    }

    struct Analysis {
        var plan: FloorPlan
        var stats: ScanStats
    }

    func analyse(cellSize: Double = 0.1) -> Analysis {
        var stats = ScanStats()
        stats.meshVertexCount = vertexCount
        stats.meshFaceCount = faceCount
        let floorY = estimateFloorY()

        var floorArea: Double = 0
        var ceilingYs: [Float] = []
        var occupied = Set<Int64>()
        var floorCells = Set<Int64>()
        func key(_ x: Double, _ z: Double) -> Int64 {
            let ix = Int64((x / cellSize).rounded(.down)), iz = Int64((z / cellSize).rounded(.down))
            return (ix << 32) ^ (iz & 0xFFFF_FFFF)
        }

        for f in 0..<faceCount {
            let (a, b, c) = faceVertices(f)
            let cls = faceClass(f)
            let centre = (a + b + c) / 3
            switch cls {
            case .floor:
                let n = V3.cross(b - a, c - a)
                floorArea += Double(abs(n.y)) / 2
                floorCells.insert(key(Double(centre.x), Double(centre.z)))
            case .ceiling:
                ceilingYs.append(centre.y)
            default:
                let h = centre.y - floorY
                if h > 0.15 && h < 2.2 {
                    for p in [a, b, c, centre] { occupied.insert(key(Double(p.x), Double(p.z))) }
                }
            }
        }

        if floorArea > 0.2 {
            stats.floorArea = floorArea
        }
        if ceilingYs.count > 20 {
            ceilingYs.sort()
            stats.ceilingHeight = Double(ceilingYs[ceilingYs.count / 2] - floorY)
            stats.minCeilingHeight = Double(ceilingYs[ceilingYs.count / 10] - floorY)
        }

        var plan = FloorPlan()
        plan.floorY = Double(floorY)
        plan.occupancyCellSize = cellSize
        func centre(of k: Int64) -> PlanPoint {
            let ix = Double(Int32(truncatingIfNeeded: k >> 32))
            let iz = Double(Int32(truncatingIfNeeded: k & 0xFFFF_FFFF))
            return PlanPoint(x: (ix + 0.5) * cellSize, z: (iz + 0.5) * cellSize)
        }
        plan.occupancy = occupied.map(centre)
        let floorPoints = floorCells.map(centre)

        let all = plan.occupancy + floorPoints
        if let bounds = PlanRect.enclosing(all) {
            plan.bounds = bounds
            stats.width = min(bounds.width, bounds.depth)
            stats.length = max(bounds.width, bounds.depth)
            if stats.floorArea == nil {
                stats.floorArea = Double(floorCells.count) * cellSize * cellSize
                stats.floorAreaIsEstimate = true
            }
        }
        return Analysis(plan: plan, stats: stats)
    }

    // MARK: Geometry

    /// Splits the mesh into one node per classification so each surface type can be
    /// hidden, re-materialised or given collision separately in Unreal.
    func sceneGeometry() -> SceneGeometry {
        let root = SceneNode(name: "FrameScout_Location")
        let meshGroup = root.addChild(SceneNode(name: "LiDAR_Mesh"))
        let hasClasses = faceClasses.contains { $0 != 0 }

        for cls in Classification.allCases {
            var remap = [Int32](repeating: -1, count: positions.count)
            var mesh = SceneMesh(material: hasClasses ? cls.material : .mesh)
            for f in 0..<faceCount where (hasClasses ? faceClass(f) == cls : cls == .none) {
                for k in 0..<3 {
                    let vi = Int(indices[f * 3 + k])
                    if remap[vi] < 0 {
                        remap[vi] = Int32(mesh.positions.count)
                        mesh.positions.append(positions[vi])
                        mesh.normals.append(vi < normals.count ? normals[vi] : Vec3(0, 1, 0))
                    }
                    mesh.indices.append(UInt32(remap[vi]))
                }
            }
            guard !mesh.isEmpty else { continue }
            let node = SceneNode(name: hasClasses ? cls.groupName : "Mesh", mesh: mesh)
            node.info = ["category": hasClasses ? cls.groupName.lowercased() : "mesh", "triangles": "\(mesh.triangleCount)"]
            meshGroup.addChild(node)
        }
        let pruned = root.pruned() ?? SceneNode(name: "FrameScout_Location")
        return SceneGeometry(root: pruned, metadata: ["source": "ARKit LiDAR scene reconstruction mesh"])
    }
}
