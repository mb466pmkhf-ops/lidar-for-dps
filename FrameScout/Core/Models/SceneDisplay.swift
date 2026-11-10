import Foundation

/// What the plan and 3D view show for a location. Nothing here changes the scan itself:
/// hiding, transparency and alignment are view settings stored next to it.
struct SceneDisplay: Codable, Hashable {
    /// Hidden single items, by key (see `SceneItemKey`).
    var hiddenItems: [String]? = nil
    /// Hidden groups: `SceneGroup` raw values, or "category:<name>" for one kind of set piece.
    var hiddenGroups: [String]? = nil
    /// Label groups switched off (`SceneLabelGroup` raw values).
    var hiddenLabels: [String]? = nil
    /// How see-through windows look in 3D (0 = invisible, 1 = solid).
    var windowOpacity: Double? = nil
    /// How much light the glass passes in the lux calculation (0…1).
    var windowTransmission: Double? = nil
    /// Walls in 3D (1 = solid); lower to see lights outside.
    var wallOpacity: Double? = nil
    /// False-colour exposure map on the plan.
    var showLuxMap: Bool? = nil

    static let defaultWindowOpacity = 0.25
    /// Typical visible-light transmission of clear double glazing.
    static let defaultWindowTransmission = 0.78

    var windowOpacityValue: Double { windowOpacity ?? Self.defaultWindowOpacity }
    var windowTransmissionValue: Double { windowTransmission ?? Self.defaultWindowTransmission }
    var wallOpacityValue: Double { wallOpacity ?? 1 }
    var luxMapOn: Bool { showLuxMap ?? false }

    func isHidden(item key: String) -> Bool { hiddenItems?.contains(key) ?? false }
    func isHidden(group: SceneGroup) -> Bool { hiddenGroups?.contains(group.rawValue) ?? false }
    func isHidden(category: String) -> Bool { hiddenGroups?.contains(Self.categoryKey(category)) ?? false }
    func showsLabels(_ group: SceneLabelGroup) -> Bool { !(hiddenLabels?.contains(group.rawValue) ?? false) }

    /// A set piece is hidden on its own, through its category, or through the furniture group.
    func isHidden(object id: UUID, category: String) -> Bool {
        isHidden(group: .furniture) || isHidden(category: category) || isHidden(item: SceneItemKey.object(id))
    }

    static func categoryKey(_ category: String) -> String { "category:" + category.lowercased() }

    mutating func setHidden(item key: String, _ hidden: Bool) {
        hiddenItems = Self.toggled(hiddenItems, key, hidden)
    }
    mutating func setHidden(group: SceneGroup, _ hidden: Bool) {
        hiddenGroups = Self.toggled(hiddenGroups, group.rawValue, hidden)
    }
    mutating func setHidden(category: String, _ hidden: Bool) {
        hiddenGroups = Self.toggled(hiddenGroups, Self.categoryKey(category), hidden)
    }
    mutating func setLabels(_ group: SceneLabelGroup, shown: Bool) {
        hiddenLabels = Self.toggled(hiddenLabels, group.rawValue, !shown)
    }

    /// Shows everything again (keeps transparency and the lux map).
    mutating func showAll() {
        hiddenItems = nil
        hiddenGroups = nil
    }

    var hiddenCount: Int { (hiddenItems?.count ?? 0) + (hiddenGroups?.count ?? 0) }

    private static func toggled(_ list: [String]?, _ key: String, _ on: Bool) -> [String]? {
        var set = list ?? []
        set.removeAll { $0 == key }
        if on { set.append(key) }
        return set.isEmpty ? nil : set
    }
}

enum SceneGroup: String, CaseIterable, Identifiable {
    case walls, doors, windows, floors, furniture, cameras, lights, grip, people, meters

    var id: String { rawValue }
    var label: String {
        switch self {
        case .walls: return "Walls"
        case .doors: return "Doors"
        case .windows: return "Windows"
        case .floors: return "Floors"
        case .furniture: return "Set pieces"
        case .cameras: return "Cameras & shots"
        case .lights: return "Lights"
        case .grip: return "Grip (bounce, neg, flags)"
        case .people: return "People"
        case .meters: return "Light meters"
        }
    }
    var symbol: String {
        switch self {
        case .walls: return "square.split.bottomrightquarter"
        case .doors: return "door.left.hand.open"
        case .windows: return "window.vertical.closed"
        case .floors: return "square.bottomhalf.filled"
        case .furniture: return "sofa"
        case .cameras: return "video"
        case .lights: return "lightbulb"
        case .grip: return "rectangle.portrait"
        case .people: return "figure.stand"
        case .meters: return "gauge.with.dots.needle.50percent"
        }
    }
    /// Groups that come from the scan (the rest are things placed in the plan).
    var isScan: Bool { [.walls, .doors, .windows, .floors, .furniture].contains(self) }
}

enum SceneLabelGroup: String, CaseIterable, Identifiable {
    case objects, dimensions, cameras, lights, people, meters

    var id: String { rawValue }
    var label: String {
        switch self {
        case .objects: return "Set piece names"
        case .dimensions: return "Wall dimensions"
        case .cameras: return "Camera labels"
        case .lights: return "Light labels"
        case .people: return "Names of people"
        case .meters: return "Meter readings"
        }
    }
}

enum SceneItemKey {
    static func object(_ id: UUID) -> String { "object:" + id.uuidString }
    static func light(_ id: UUID) -> String { "light:" + id.uuidString }
    static func character(_ id: UUID) -> String { "character:" + id.uuidString }
}

/// Non-destructive correction applied to a scan in the 3D view: levelling (pitch and roll),
/// a turn about the vertical axis and a move. Cameras, lights and people placed on the plan move
/// with the scan, so they stay where they were in the room.
struct ScanAlignment: Codable, Hashable {
    /// Degrees about the scan's X axis (+ tips the far side up).
    var pitch: Double = 0
    /// Degrees about the scan's Z axis (+ tips the right side up).
    var roll: Double = 0
    /// Degrees about the vertical axis, clockwise seen from above.
    var yaw: Double = 0
    var offsetX: Double = 0
    /// Moves the scan up (+) or down (m) to sit the floor on the ground plane.
    var offsetY: Double = 0
    var offsetZ: Double = 0

    static let identity = ScanAlignment()
    var isIdentity: Bool { self == .identity }

    /// Pitch and roll that turn a measured floor normal (x, y, z) straight up.
    static func levelling(floorNormal n: (x: Double, y: Double, z: Double)) -> (pitch: Double, roll: Double) {
        let len = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
        guard len > 1e-9 else { return (0, 0) }
        let (x, y, z) = (n.x / len, n.y / len, n.z / len)
        // Roll about Z removes the X tilt, then pitch about X removes the Z tilt.
        let roll = atan2(x, y) * 180 / .pi
        let yAfterRoll = (x * x + y * y).squareRoot()
        let pitch = -atan2(z, yAfterRoll) * 180 / .pi
        return (pitch, roll)
    }
}

extension ScanRecord {
    var alignmentValue: ScanAlignment { alignment ?? .identity }
}

/// Where an incident light meter points.
enum MeterFacing: String, Codable, CaseIterable, Identifiable {
    /// Towards the camera that sees this spot (how a DP meters a face).
    case camera
    /// Horizontal, towards a bearing.
    case bearing
    /// Straight up (a horizontal surface, like a table top).
    case up

    var id: String { rawValue }
    var label: String {
        switch self {
        case .camera: return "Towards camera"
        case .bearing: return "Fixed direction"
        case .up: return "Up (table top)"
        }
    }
}

/// A point where the plan shows an incident reading.
struct LightMeter: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var position: PlanPoint
    /// Height of the receptor above the floor (m).
    var height: Double = 1.5
    var facing: MeterFacing = .camera
    var bearing: Double = 0
    /// Lux you want here; nil uses the camera's key level.
    var targetLux: Double? = nil
    var scanID: UUID? = nil

    init(name: String, position: PlanPoint, height: Double = 1.5, scanID: UUID? = nil) {
        self.name = name
        self.position = position
        self.height = height
        self.scanID = scanID
    }

    enum CodingKeys: String, CodingKey { case id, name, position, height, facing, bearing, targetLux, scanID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Meter",
                  position: try c.decodeIfPresent(PlanPoint.self, forKey: .position) ?? .zero)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? height
        facing = try c.decodeIfPresent(MeterFacing.self, forKey: .facing) ?? facing
        bearing = try c.decodeIfPresent(Double.self, forKey: .bearing) ?? bearing
        targetLux = try c.decodeIfPresent(Double.self, forKey: .targetLux)
        scanID = try c.decodeIfPresent(UUID.self, forKey: .scanID)
    }
}

extension Location {
    var lightMeters: [LightMeter] {
        get { meters ?? [] }
        set { meters = newValue.isEmpty ? nil : newValue }
    }

    var displaySettings: SceneDisplay {
        get { display ?? SceneDisplay() }
        set { display = newValue == SceneDisplay() ? nil : newValue }
    }
}
