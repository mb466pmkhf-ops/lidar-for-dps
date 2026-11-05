import Foundation

/// Stand-in people for blocking, framing and lighting. Proportions follow standard figure-drawing
/// ratios (adults about 7.5 heads tall, children about 6), scaled by height and build.
enum CharacterType: String, Codable, CaseIterable, Identifiable {
    case man, woman, girl, boy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var isChild: Bool { self == .girl || self == .boy }
    var symbol: String {
        switch self {
        case .man: return "figure.stand"
        case .woman: return "figure.stand.dress"
        case .girl, .boy: return "figure.child"
        }
    }

    var defaultHeight: Double {
        switch self {
        case .man: return 1.78
        case .woman: return 1.65
        case .girl: return 1.30
        case .boy: return 1.34
        }
    }

    var heightRange: ClosedRange<Double> { isChild ? 0.8...1.75 : 1.4...2.1 }
}

enum CharacterPosture: String, Codable, CaseIterable, Identifiable {
    case standing, sitting
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Six generic skin tones, light to deep. Colours are display sRGB; reflectance is the
/// approximate diffuse reflectance used to say how a face reads relative to mid grey.
enum SkinTone: Int, Codable, CaseIterable, Identifiable {
    case tone1 = 1, tone2, tone3, tone4, tone5, tone6

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .tone1: return "Very light"
        case .tone2: return "Light"
        case .tone3: return "Medium"
        case .tone4: return "Olive / tan"
        case .tone5: return "Brown"
        case .tone6: return "Deep"
        }
    }

    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .tone1: return (0.96, 0.84, 0.76)
        case .tone2: return (0.91, 0.74, 0.62)
        case .tone3: return (0.80, 0.60, 0.46)
        case .tone4: return (0.67, 0.48, 0.34)
        case .tone5: return (0.50, 0.34, 0.24)
        case .tone6: return (0.32, 0.21, 0.15)
        }
    }

    /// Approximate diffuse reflectance (mid grey is 0.18).
    var reflectance: Double {
        switch self {
        case .tone1: return 0.45
        case .tone2: return 0.38
        case .tone3: return 0.30
        case .tone4: return 0.22
        case .tone5: return 0.15
        case .tone6: return 0.09
        }
    }

    /// How a correctly metered incident reading places this skin relative to mid grey (stops).
    var stopsFromMidGrey: Double { log2(reflectance / 0.18) }
}

struct PrevisCharacter: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var type: CharacterType
    /// Standing height (m).
    var height: Double
    /// 0 = slim, 0.5 = average, 1 = heavy.
    var build: Double = 0.5
    var skinTone: SkinTone = .tone3
    var position: PlanPoint
    /// World bearing the person faces (0° = plan up, clockwise).
    var facing: Double = 180
    var posture: CharacterPosture = .standing
    var scanID: UUID? = nil

    init(name: String, type: CharacterType, position: PlanPoint, facing: Double = 180, scanID: UUID? = nil) {
        self.name = name
        self.type = type
        self.height = type.defaultHeight
        self.position = position
        self.facing = facing
        self.scanID = scanID
    }

    enum CodingKeys: String, CodingKey { case id, name, type, height, build, skinTone, position, facing, posture, scanID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(CharacterType.self, forKey: .type) ?? .man
        self.init(name: try c.decodeIfPresent(String.self, forKey: .name) ?? type.label, type: type,
                  position: try c.decodeIfPresent(PlanPoint.self, forKey: .position) ?? .zero)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? height
        build = try c.decodeIfPresent(Double.self, forKey: .build) ?? build
        skinTone = try c.decodeIfPresent(SkinTone.self, forKey: .skinTone) ?? skinTone
        facing = try c.decodeIfPresent(Double.self, forKey: .facing) ?? facing
        posture = try c.decodeIfPresent(CharacterPosture.self, forKey: .posture) ?? posture
        scanID = try c.decodeIfPresent(UUID.self, forKey: .scanID)
    }

    var proportions: FigureProportions { FigureProportions(self) }

    /// Eye height above the floor in the current posture (m).
    var eyeHeight: Double { proportions.eyeHeight }

    var buildLabel: String {
        switch build {
        case ..<0.2: return "Slim"
        case ..<0.4: return "Lean"
        case ..<0.6: return "Average"
        case ..<0.8: return "Solid"
        default: return "Heavy"
        }
    }

    var summary: String {
        "\(type.label) · \(UnitsFormatter.distance(height)) · \(buildLabel)\(posture == .sitting ? " · sitting" : "")"
    }
}

/// Body measurements (m) for drawing a figure. Heights are above the floor; widths are full widths.
struct FigureProportions {
    var headHeight: Double
    var headWidth: Double
    var eyeHeight: Double
    var neckBase: Double
    var shoulderHeight: Double
    var shoulderWidth: Double
    var chestDepth: Double
    var waistWidth: Double
    var hipHeight: Double
    var hipWidth: Double
    var armRadius: Double
    var legRadius: Double
    var armLength: Double
    var seatHeight: Double
    var sitting: Bool
    var top: Double

    init(_ c: PrevisCharacter) {
        let h = c.height
        let heads = c.type.isChild ? 6.0 : 7.5
        let head = h / heads
        let b = min(max(c.build, 0), 1) - 0.5           // −0.5 … 0.5
        let broad: Double = {
            switch c.type {
            case .man: return 1.0
            case .woman: return 0.9
            case .boy, .girl: return 0.92
            }
        }()
        headHeight = head
        headWidth = head * 0.72 * (1 + b * 0.12)
        shoulderWidth = h * 0.245 * broad * (1 + b * 0.25)
        chestDepth = h * 0.12 * (1 + b * 0.55)
        waistWidth = h * 0.16 * (c.type == .woman ? 0.92 : 1) * (1 + b * 0.6)
        hipWidth = h * (c.type == .woman ? 0.2 : 0.185) * (1 + b * 0.35)
        armRadius = h * 0.026 * (1 + b * 0.45)
        legRadius = h * 0.04 * (1 + b * 0.4)
        armLength = h * 0.36
        let standingHip = h * 0.52
        sitting = c.posture == .sitting
        seatHeight = sitting ? min(0.45, standingHip * 0.5) : 0
        // Sitting lowers everything above the hips to a seat (thighs horizontal).
        let drop = sitting ? standingHip - seatHeight : 0
        hipHeight = standingHip - drop
        shoulderHeight = h * 0.818 - drop
        neckBase = h * 0.845 - drop
        eyeHeight = h - head * 0.48 - drop
        top = h - drop
    }
}

extension Location {
    var previsCharacters: [PrevisCharacter] {
        get { characters ?? [] }
        set { characters = newValue.isEmpty ? nil : newValue }
    }
}
