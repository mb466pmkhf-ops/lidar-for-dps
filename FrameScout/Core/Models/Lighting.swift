import Foundation

/// What a lighting-diagram fixture is. Emitting units throw light; grip (bounce, negative fill,
/// flags, diffusion frames) shape it and are drawn as boards rather than beams.
enum LightKind: String, Codable, CaseIterable, Identifiable {
    case fresnel, hmi, ledPanel, tube, softbox, spaceLight, practical, bounce, negative, flag, diffusion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fresnel: return "Fresnel"
        case .hmi: return "HMI"
        case .ledPanel: return "LED panel"
        case .tube: return "Tube"
        case .softbox: return "Softbox"
        case .spaceLight: return "Space light"
        case .practical: return "Practical"
        case .bounce: return "Bounce"
        case .negative: return "Negative fill"
        case .flag: return "Flag"
        case .diffusion: return "Diffusion frame"
        }
    }

    var symbol: String {
        switch self {
        case .fresnel, .hmi: return "light.beacon.max"
        case .ledPanel: return "rectangle.inset.filled"
        case .tube: return "light.strip.2"
        case .softbox: return "square.dashed.inset.filled"
        case .spaceLight: return "lamp.ceiling"
        case .practical: return "lamp.table"
        case .bounce: return "square"
        case .negative: return "square.fill"
        case .flag: return "flag"
        case .diffusion: return "square.grid.3x3"
        }
    }

    /// Bounce, negative fill, flags and frames don't emit light.
    var emits: Bool {
        switch self {
        case .bounce, .negative, .flag, .diffusion: return false
        default: return true
        }
    }

    /// Typical beam spread (full angle, degrees) to start from.
    var defaultBeamAngle: Double {
        switch self {
        case .fresnel: return 35
        case .hmi: return 30
        case .ledPanel: return 90
        case .tube: return 120
        case .softbox: return 100
        case .spaceLight: return 160
        case .practical: return 180
        case .bounce, .negative, .flag, .diffusion: return 0
        }
    }

    /// Width of the unit seen from above (metres) — boards, tubes and panels have a length.
    var defaultWidth: Double {
        switch self {
        case .tube: return 1.2
        case .ledPanel: return 0.6
        case .softbox: return 0.9
        case .bounce, .negative, .diffusion: return 1.2
        case .flag: return 0.6
        default: return 0.3
        }
    }

    var defaultHeight: Double {
        switch self {
        case .spaceLight: return 2.6
        case .practical: return 1.0
        case .bounce, .negative, .flag, .diffusion: return 1.5
        default: return 2.2
        }
    }
}

enum LightColorMode: String, Codable {
    case cct, rgb
}

/// Job of a light in the setup, as written on a lighting plot.
enum LightRole: String, Codable, CaseIterable, Identifiable {
    case key, fill, back, edge, background, ambient, practical, effect

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// One unit on the lighting diagram. Lives on the location, in the same plan coordinates as
/// cameras and shots, so the plan and the 3D scan view edit the same data.
struct LightFixture: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: LightKind
    var role: LightRole? = nil
    var position: PlanPoint
    /// Height of the unit above the floor (m).
    var height: Double
    /// World bearing the unit faces (0° = plan up, clockwise), like `CameraRig.pan`.
    var pan: Double = 0
    /// Degrees, negative points down.
    var tilt: Double = -20
    /// Full beam angle in degrees (emitting units).
    var beamAngle: Double
    /// Size seen from above (m).
    var width: Double
    /// Free text, as written on a plot: "1.2K", "600 W", "4×4".
    var power: String = ""
    /// Colour temperature in kelvin (emitting units).
    var colorTemperature: Double = 5600
    var gel: String = ""
    var modifier: String = ""
    /// 0…1.
    var dimmer: Double = 1
    var isOn: Bool = true
    var scanID: UUID? = nil
    var notes: String = ""

    // Fixture data (all optional so lights saved before the fixture library load; see `Photometrics.swift`).
    /// `FixtureLibrary` profile; nil uses the default type for `kind`.
    var profileID: String? = nil
    /// `FixtureLibrary` modifier; nil uses the type's default, "none" runs it bare.
    var modifierID: String? = nil
    var filterIDs: [String]? = nil
    var barnDoors: BarnDoors? = nil
    var colorMode: LightColorMode? = nil
    /// RGB units: hue 0–360°, saturation 0–1.
    var hue: Double? = nil
    var saturation: Double? = nil
    /// The user's own photometric data for this unit (e.g. from the maker's sheet).
    var photometricOverride: PhotometricReference? = nil
    /// Board height for grip (m); nil uses the width (square frame).
    var boardHeight: Double? = nil

    init(name: String, kind: LightKind, position: PlanPoint, pan: Double = 0, scanID: UUID? = nil) {
        self.name = name
        self.kind = kind
        self.position = position
        self.pan = pan
        self.scanID = scanID
        height = kind.defaultHeight
        beamAngle = kind.defaultBeamAngle
        width = kind.defaultWidth
        tilt = kind.emits ? -20 : 0
    }

    /// One line for lists and the plan label: "Key · Fresnel 1.2K · 3200 K".
    var summary: String {
        var parts = [kind.label]
        if !power.isEmpty { parts[0] += " \(power)" }
        if kind.emits { parts.append("\(Int(colorTemperature.rounded())) K") }
        if !gel.isEmpty { parts.append(gel) }
        if kind.emits && dimmer < 0.995 { parts.append("\(Int((dimmer * 100).rounded())) %") }
        return parts.joined(separator: " · ")
    }
}

extension Location {
    /// Lighting units on this location. Stored as an optional so older project files load.
    var lightFixtures: [LightFixture] {
        get { lights ?? [] }
        set { lights = newValue.isEmpty ? nil : newValue }
    }
}

/// Approximate colour of a black-body source, for drawing beams and lighting the 3D view.
enum Kelvin {
    static let presets: [Double] = [2700, 3200, 4300, 5600, 6500]

    /// RGB 0…1 (Tanner Helland's fit), clamped to 1000–15000 K.
    static func rgb(_ kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max(kelvin, 1000), 15000) / 100
        let r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
            b = t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
            b = 255
        }
        func c(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return (c(r), c(g), c(b))
    }
}
