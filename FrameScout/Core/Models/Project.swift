import Foundation

/// A production (e.g. "Commercial XYZ"). Projects own locations; everything else hangs off a location.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var client: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var locations: [Location] = []
    var objects: [CapturedObject] = []
}

extension Project {
    enum CodingKeys: String, CodingKey {
        case id, name, client, notes, createdAt, modifiedAt, locations, objects
    }

    /// Decodes projects saved before objects existed (and tolerates other missing keys).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? createdAt
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? modifiedAt
        locations = try c.decodeIfPresent([Location].self, forKey: .locations) ?? []
        objects = try c.decodeIfPresent([CapturedObject].self, forKey: .objects) ?? []
    }
}

/// Stable address of a location inside a project. Used for navigation and file paths.
struct LocationRef: Hashable, Codable {
    var projectID: UUID
    var locationID: UUID
}

struct GeoCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
}

enum LocationTag: String, Codable, CaseIterable, Identifiable {
    case interior, exterior, day, night, studio, house, office, warehouse
    case naturalLight, lowCeiling, smallSpace, largeSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .interior: return "INTERIOR"
        case .exterior: return "EXTERIOR"
        case .day: return "DAY"
        case .night: return "NIGHT"
        case .studio: return "STUDIO"
        case .house: return "HOUSE"
        case .office: return "OFFICE"
        case .warehouse: return "WAREHOUSE"
        case .naturalLight: return "NATURAL LIGHT"
        case .lowCeiling: return "LOW CEILING"
        case .smallSpace: return "SMALL SPACE"
        case .largeSpace: return "LARGE SPACE"
        }
    }
}

enum NoteCategory: String, Codable, CaseIterable, Identifiable {
    case general, lighting, power, access, sound, production

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: return "note.text"
        case .lighting: return "sun.max"
        case .power: return "powerplug"
        case .access: return "door.left.hand.open"
        case .sound: return "waveform"
        case .production: return "clapperboard"
        }
    }
}

/// Short, scannable scout notes ("Power outlets on this wall").
struct LocationNote: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var category: NoteCategory = .general
    var createdAt: Date = Date()

    static let templates: [(NoteCategory, String)] = [
        (.lighting, "Large south-facing windows"),
        (.lighting, "Good natural light from 3–5pm"),
        (.lighting, "Potential 4x4 lighting position outside"),
        (.production, "Very little space behind camera"),
        (.production, "Ceiling only 2.6m"),
        (.power, "Power outlets on this wall"),
        (.access, "Narrow access — no dolly through door"),
        (.sound, "Traffic noise from street side"),
    ]
}

struct Location: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var address: String = ""
    var coordinate: GeoCoordinate? = nil
    var timeZoneIdentifier: String? = nil
    var createdAt: Date = Date()
    var tags: Set<LocationTag> = []
    var notes: String = ""
    var lightingNotes: String = ""
    var productionNotes: String = ""
    var quickNotes: [LocationNote] = []
    var scans: [ScanRecord] = []
    var primaryScanID: UUID? = nil
    var photos: [ReferencePhoto] = []
    var measurements: [DistanceMeasurement] = []
    var cameraPositions: [CameraPosition] = []
    var shots: [Shot] = []
    /// Lighting diagram units (see `lightFixtures`). Optional so older project files load.
    var lights: [LightFixture]? = nil
    /// Stand-in people for blocking and lighting (see `previsCharacters`).
    var characters: [PrevisCharacter]? = nil
    /// Placed light meters (see `lightMeters`).
    var meters: [LightMeter]? = nil
    /// Camera exposure for reading lux as stops (see `exposureSettings`).
    var exposure: ExposureSettings? = nil
    /// Visibility, transparency and label settings for the plan and 3D view (see `displaySettings`).
    var display: SceneDisplay? = nil

    var dateScanned: Date? { scans.map(\.createdAt).max() }

    var primaryScan: ScanRecord? {
        if let id = primaryScanID, let scan = scans.first(where: { $0.id == id }) { return scan }
        return scans.last
    }

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    var sortedTags: [LocationTag] {
        LocationTag.allCases.filter { tags.contains($0) }
    }

    var nextShotNumber: Int { (shots.map(\.number).max() ?? 0) + 1 }
}
