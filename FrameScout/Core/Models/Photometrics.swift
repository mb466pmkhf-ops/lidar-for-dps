import Foundation

// Photometric model for lighting units. Kept separate from how bright a unit looks in the 3D view:
// the viewport is a visual guide, illuminance comes from these numbers (see `LightingCalculator`).
//
// Model, in one place so the assumptions stay consistent:
// - Each fixture type has a reference reading: lux at a distance, on the beam axis, in a stated
//   configuration (usually its standard reflector). Library values are estimates; a user can
//   enter their own data per unit, which is then marked manual.
// - The reading gives peak intensity (cd), and with the beam shape, the luminous flux in the beam.
//   Modifiers and filters scale that flux and change the shape; the dimmer scales it linearly.
//   Peak intensity follows from flux ÷ the beam's solid-angle factor, so a flooded beam is dimmer
//   on axis than a spotted one with the same flux.
// - Electrical watts only drive the power-draw figure. They never set output.

/// How a unit spreads its light. Beam angles follow the photometric convention: the full angle at
/// which intensity falls to 50 % of the peak.
enum BeamDistribution: String, Codable, CaseIterable {
    /// Reflector or lens: flat-topped beam, I(θ) = I₀ · 2^-(θ/θ½)⁴ (50 % at the beam edge,
    /// 10 % at about 1.35× the half angle).
    case beam
    /// Flat diffuse face (panels, softboxes, bounce): I(θ) = I₀ · cos θ — a 120° beam by the same convention.
    case lambertian
    /// Bare bulb or lantern: the same intensity in every direction.
    case omni
    /// Diffuse tube: I = I₀ · sin ψ, ψ measured from the tube's axis.
    case tube

    /// Intensity relative to the peak at `theta` degrees off the beam axis (beam and lambertian),
    /// or `psi` degrees from the tube axis (tube).
    func relativeIntensity(offAxis theta: Double, beamAngle: Double) -> Double {
        switch self {
        case .beam:
            let half = max(beamAngle, 1) / 2
            guard theta < 179 else { return 0 }
            return pow(2, -pow(theta / half, 4))
        case .lambertian:
            return max(0, cos(theta * .pi / 180))
        case .omni:
            return 1
        case .tube:
            return abs(sin(theta * .pi / 180))
        }
    }

    /// Ω such that flux = peak intensity × Ω (steradians). Integrates the shape over the sphere.
    func solidAngleFactor(beamAngle: Double) -> Double {
        switch self {
        case .lambertian: return .pi
        case .omni: return 4 * .pi
        case .tube: return .pi * .pi
        case .beam:
            // Simpson over 0…180°; the integrand is smooth and the beam is never narrower than 1°.
            let n = 720
            let h = Double.pi / Double(n)
            var sum = 0.0
            for i in 0...n {
                let t = Double(i) * h
                let f = relativeIntensity(offAxis: t * 180 / .pi, beamAngle: beamAngle) * sin(t)
                sum += f * (i == 0 || i == n ? 1 : (i % 2 == 1 ? 4 : 2))
            }
            return 2 * .pi * sum * h / 3
        }
    }

    /// Nominal beam angle to show for shapes that don't have an adjustable one.
    var nominalBeam: Double? {
        switch self {
        case .beam: return nil
        case .lambertian: return 120
        case .omni, .tube: return 360
        }
    }
}

/// Families shown when picking a fixture.
enum FixtureCategory: String, Codable, CaseIterable, Identifiable {
    case cob, fresnel, panel, tube, soft, hmi, tungsten, spaceLight, practical

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cob: return "COB LED"
        case .fresnel: return "Fresnel"
        case .panel: return "LED panel"
        case .tube: return "LED tube"
        case .soft: return "Soft source"
        case .hmi: return "HMI"
        case .tungsten: return "Tungsten"
        case .spaceLight: return "Space light / lantern"
        case .practical: return "Practical"
        }
    }
}

/// Where a reference reading came from and what it describes: lux on the beam axis at a distance.
struct PhotometricReference: Codable, Hashable {
    var lux: Double
    var distance: Double
    /// Beam angle the reading was taken at, for units whose beam changes (fresnels, zoom reflectors).
    var beamAngle: Double? = nil
    var provenance: Provenance = .estimated
    var note: String = ""
}

/// What colour a unit can make.
struct ColorCapability: Codable, Hashable {
    var minKelvin: Double
    var maxKelvin: Double
    /// Full colour (hue and saturation) as well as white.
    var rgb: Bool = false

    var isAdjustable: Bool { maxKelvin - minKelvin > 1 }
    static func fixed(_ k: Double) -> ColorCapability { ColorCapability(minKelvin: k, maxKelvin: k) }
    static func biColour(_ lo: Double, _ hi: Double) -> ColorCapability { ColorCapability(minKelvin: lo, maxKelvin: hi) }
    static func fullColour(_ lo: Double, _ hi: Double) -> ColorCapability { ColorCapability(minKelvin: lo, maxKelvin: hi, rgb: true) }
}

/// How the lamp technology behaves when dimmed.
enum LampTechnology: String, Codable {
    case led, hmi, tungsten

    /// Electrical draw as a fraction of rated power at a given output (0…1).
    func drawFraction(output: Double) -> Double {
        let o = min(max(output, 0), 1)
        switch self {
        // Driver overhead plus roughly linear LED current.
        case .led: return o <= 0 ? 0 : 0.06 + 0.94 * o
        // Ballast keeps most of its load when dimmed.
        case .hmi: return o <= 0 ? 0 : 0.25 + 0.75 * o
        // Light ∝ V^3.4, power ∝ V^1.6, so power ∝ light^0.47.
        case .tungsten: return o <= 0 ? 0 : pow(o, 1.6 / 3.4)
        }
    }

    /// Colour temperature after dimming. Tungsten warms as it dims (CCT ∝ V^0.42 ∝ light^0.12).
    func kelvin(_ k: Double, output: Double) -> Double {
        switch self {
        case .tungsten: return k * pow(min(max(output, 0.01), 1), 0.42 / 3.4)
        default: return k
        }
    }
}

/// A generic fixture type with estimated specifications. No brand names: these describe classes
/// of units, and the reference figures are deliberately round.
struct FixtureProfile: Identifiable, Hashable {
    var id: String
    var name: String
    var category: FixtureCategory
    /// How it is drawn on the plan and in 3D.
    var kind: LightKind
    var technology: LampTechnology
    /// Maximum electrical draw (W).
    var ratedPower: Double
    var color: ColorCapability
    var distribution: BeamDistribution
    var defaultBeam: Double
    /// Adjustable beam (spot ↔ flood), if the unit has one built in.
    var beamRange: ClosedRange<Double>? = nil
    var reference: PhotometricReference
    /// Size of the light-emitting face (m): width × height. Sets near-field behaviour of soft sources.
    var emitterWidth: Double
    var emitterHeight: Double
    var hasBarnDoors: Bool = false
    /// Lowest usable output (HMIs don't dim much below half).
    var minOutput: Double = 0.01
    /// Modifier fitted by default (its effect is part of the reference reading).
    var defaultModifierID: String? = nil

    var powerLabel: String {
        ratedPower >= 1000 ? String(format: "%gK", ratedPower / 1000) : "\(Int(ratedPower)) W"
    }
}

/// Something fitted to the front of a unit that changes its beam: reflectors, softboxes, grids,
/// lanterns, fresnel and projection attachments.
struct LightModifier: Identifiable, Hashable {
    var id: String
    var name: String
    var appliesTo: Set<FixtureCategory>
    /// Fraction of the reference configuration's beam flux that comes out (can exceed 1 when the
    /// reference already includes a lossy reflector, e.g. a bare COB).
    var transmission: Double
    var distribution: BeamDistribution? = nil
    var beam: Double? = nil
    var beamRange: ClosedRange<Double>? = nil
    /// New emitting face size (m), for softboxes and lanterns.
    var size: Double? = nil
    var allowsBarnDoors: Bool = false
}

/// Gels, diffusion and ND on the unit. Transmission values are typical published figures for
/// each generic filter type.
struct LightFilter: Identifiable, Hashable {
    enum Diffusion: String { case light, medium, heavy }

    var id: String
    var name: String
    var transmission: Double
    /// Mired shift (+ warms, − cools).
    var mired: Double = 0
    var diffusion: Diffusion? = nil
}

/// Each barn-door leaf as the angle (°) from the beam axis at which it cuts the light. 90° is open.
struct BarnDoors: Codable, Hashable {
    var top: Double = 90
    var bottom: Double = 90
    var left: Double = 90
    var right: Double = 90

    static let open = BarnDoors()
    var isOpen: Bool { min(top, bottom, left, right) >= 89.5 }

    /// Fraction of light passing at horizontal angle `h` and vertical angle `v` off the axis
    /// (degrees; +h right, +v up). Leaves make a soft edge a few degrees wide.
    func transmission(horizontal h: Double, vertical v: Double, softness: Double = 6) -> Double {
        func pass(_ angle: Double, _ limit: Double) -> Double {
            guard limit < 89.5 else { return 1 }
            return min(1, max(0, (limit - angle) / softness + 0.5))
        }
        return pass(h, right) * pass(-h, left) * pass(v, top) * pass(-v, bottom)
    }
}

enum FixtureLibrary {
    private static func ref(_ lux: Double, at d: Double, beam: Double? = nil, _ note: String) -> PhotometricReference {
        PhotometricReference(lux: lux, distance: d, beamAngle: beam, provenance: .estimated, note: note)
    }

    /// Generic units. Reference readings are estimates for a typical unit of each class,
    /// derived from typical efficacy and optics; replace them with the maker's data when you have it.
    static let profiles: [FixtureProfile] = [
        FixtureProfile(id: "cob-1200-d", name: "1200 W COB LED · daylight", category: .cob, kind: .fresnel, technology: .led,
                       ratedPower: 1200, color: .fixed(5600), distribution: .beam, defaultBeam: 55,
                       reference: ref(9000, at: 3, beam: 55, "Standard 55° reflector"), emitterWidth: 0.25, emitterHeight: 0.25,
                       defaultModifierID: "reflector-55"),
        FixtureProfile(id: "cob-600-d", name: "600 W COB LED · daylight", category: .cob, kind: .fresnel, technology: .led,
                       ratedPower: 600, color: .fixed(5600), distribution: .beam, defaultBeam: 55,
                       reference: ref(4500, at: 3, beam: 55, "Standard 55° reflector"), emitterWidth: 0.2, emitterHeight: 0.2,
                       defaultModifierID: "reflector-55"),
        FixtureProfile(id: "cob-600-bi", name: "600 W COB LED · bi-colour", category: .cob, kind: .fresnel, technology: .led,
                       ratedPower: 600, color: .biColour(2700, 6500), distribution: .beam, defaultBeam: 55,
                       reference: ref(3600, at: 3, beam: 55, "Standard 55° reflector, 5600 K"), emitterWidth: 0.2, emitterHeight: 0.2,
                       defaultModifierID: "reflector-55"),
        FixtureProfile(id: "cob-300-d", name: "300 W COB LED · daylight", category: .cob, kind: .fresnel, technology: .led,
                       ratedPower: 300, color: .fixed(5600), distribution: .beam, defaultBeam: 55,
                       reference: ref(2200, at: 3, beam: 55, "Standard 55° reflector"), emitterWidth: 0.18, emitterHeight: 0.18,
                       defaultModifierID: "reflector-55"),
        FixtureProfile(id: "cob-300-bi", name: "300 W COB LED · bi-colour", category: .cob, kind: .fresnel, technology: .led,
                       ratedPower: 300, color: .biColour(2700, 6500), distribution: .beam, defaultBeam: 55,
                       reference: ref(1800, at: 3, beam: 55, "Standard 55° reflector, 5600 K"), emitterWidth: 0.18, emitterHeight: 0.18,
                       defaultModifierID: "reflector-55"),
        FixtureProfile(id: "cob-100-bi", name: "100 W COB LED · bi-colour", category: .cob, kind: .fresnel, technology: .led,
                       ratedPower: 100, color: .biColour(2700, 6500), distribution: .beam, defaultBeam: 55,
                       reference: ref(650, at: 3, beam: 55, "Standard 55° reflector, 5600 K"), emitterWidth: 0.12, emitterHeight: 0.12,
                       defaultModifierID: "reflector-55"),
        FixtureProfile(id: "fresnel-led-200-bi", name: "200 W LED fresnel · bi-colour", category: .fresnel, kind: .fresnel, technology: .led,
                       ratedPower: 200, color: .biColour(2700, 6500), distribution: .beam, defaultBeam: 50, beamRange: 15...50,
                       reference: ref(1100, at: 3, beam: 50, "Full flood, 5600 K"), emitterWidth: 0.2, emitterHeight: 0.2,
                       hasBarnDoors: true),
        FixtureProfile(id: "fresnel-led-600-d", name: "600 W LED fresnel · daylight", category: .fresnel, kind: .fresnel, technology: .led,
                       ratedPower: 600, color: .fixed(5600), distribution: .beam, defaultBeam: 60, beamRange: 15...60,
                       reference: ref(2500, at: 3, beam: 60, "Full flood"), emitterWidth: 0.3, emitterHeight: 0.3,
                       hasBarnDoors: true),
        FixtureProfile(id: "panel-1x1-bi", name: "1×1 LED panel · bi-colour (≈100 W)", category: .panel, kind: .ledPanel, technology: .led,
                       ratedPower: 100, color: .biColour(3200, 5600), distribution: .lambertian, defaultBeam: 120,
                       reference: ref(1850, at: 1, "Bare panel, 5600 K"), emitterWidth: 0.3, emitterHeight: 0.3,
                       hasBarnDoors: true),
        FixtureProfile(id: "panel-2x1-bi", name: "2×1 LED panel · bi-colour (≈200 W)", category: .panel, kind: .ledPanel, technology: .led,
                       ratedPower: 200, color: .biColour(2700, 6500), distribution: .lambertian, defaultBeam: 120,
                       reference: ref(3600, at: 1, "Bare panel, 5600 K"), emitterWidth: 0.6, emitterHeight: 0.3,
                       hasBarnDoors: true),
        FixtureProfile(id: "panel-1x1-rgb", name: "1×1 LED panel · RGB (≈150 W)", category: .panel, kind: .ledPanel, technology: .led,
                       ratedPower: 150, color: .fullColour(2500, 10000), distribution: .lambertian, defaultBeam: 120,
                       reference: ref(1900, at: 1, "Bare panel, 5600 K white"), emitterWidth: 0.3, emitterHeight: 0.3,
                       hasBarnDoors: true),
        FixtureProfile(id: "panel-2x1-rgb", name: "2×1 LED panel · RGB (≈350 W)", category: .panel, kind: .ledPanel, technology: .led,
                       ratedPower: 350, color: .fullColour(2500, 10000), distribution: .lambertian, defaultBeam: 120,
                       reference: ref(4800, at: 1, "Bare panel, 5600 K white"), emitterWidth: 0.6, emitterHeight: 0.3,
                       hasBarnDoors: true),
        FixtureProfile(id: "mat-4x4-bi", name: "4×4 LED soft mat · bi-colour (≈400 W)", category: .soft, kind: .softbox, technology: .led,
                       ratedPower: 400, color: .biColour(2700, 6500), distribution: .lambertian, defaultBeam: 120,
                       reference: ref(600, at: 3, "With its diffusion, 5600 K"), emitterWidth: 1.2, emitterHeight: 1.2),
        FixtureProfile(id: "mat-2x2-bi", name: "2×2 LED soft mat · bi-colour (≈150 W)", category: .soft, kind: .softbox, technology: .led,
                       ratedPower: 150, color: .biColour(2700, 6500), distribution: .lambertian, defaultBeam: 120,
                       reference: ref(230, at: 3, "With its diffusion, 5600 K"), emitterWidth: 0.6, emitterHeight: 0.6),
        FixtureProfile(id: "tube-4ft-rgb", name: "4 ft LED tube · RGB (≈40 W)", category: .tube, kind: .tube, technology: .led,
                       ratedPower: 40, color: .fullColour(2000, 10000), distribution: .tube, defaultBeam: 360,
                       reference: ref(300, at: 1, "Broadside, 5600 K white"), emitterWidth: 1.2, emitterHeight: 0.04),
        FixtureProfile(id: "tube-2ft-rgb", name: "2 ft LED tube · RGB (≈20 W)", category: .tube, kind: .tube, technology: .led,
                       ratedPower: 20, color: .fullColour(2000, 10000), distribution: .tube, defaultBeam: 360,
                       reference: ref(130, at: 1, "Broadside, 5600 K white"), emitterWidth: 0.6, emitterHeight: 0.04),
        FixtureProfile(id: "hmi-1800-par", name: "1.8K HMI PAR", category: .hmi, kind: .hmi, technology: .hmi,
                       ratedPower: 1800, color: .fixed(5600), distribution: .beam, defaultBeam: 30,
                       reference: ref(40000, at: 3, beam: 30, "Medium flood lens"), emitterWidth: 0.4, emitterHeight: 0.4,
                       hasBarnDoors: true, minOutput: 0.5),
        FixtureProfile(id: "hmi-4000-par", name: "4K HMI PAR", category: .hmi, kind: .hmi, technology: .hmi,
                       ratedPower: 4000, color: .fixed(5600), distribution: .beam, defaultBeam: 30,
                       reference: ref(90000, at: 3, beam: 30, "Medium flood lens"), emitterWidth: 0.55, emitterHeight: 0.55,
                       hasBarnDoors: true, minOutput: 0.5),
        FixtureProfile(id: "tungsten-650", name: "650 W tungsten fresnel", category: .tungsten, kind: .fresnel, technology: .tungsten,
                       ratedPower: 650, color: .fixed(3200), distribution: .beam, defaultBeam: 55, beamRange: 15...55,
                       reference: ref(600, at: 3, beam: 55, "Full flood"), emitterWidth: 0.15, emitterHeight: 0.15,
                       hasBarnDoors: true),
        FixtureProfile(id: "tungsten-1k", name: "1K tungsten fresnel", category: .tungsten, kind: .fresnel, technology: .tungsten,
                       ratedPower: 1000, color: .fixed(3200), distribution: .beam, defaultBeam: 55, beamRange: 15...55,
                       reference: ref(950, at: 3, beam: 55, "Full flood"), emitterWidth: 0.2, emitterHeight: 0.2,
                       hasBarnDoors: true),
        FixtureProfile(id: "tungsten-2k", name: "2K tungsten fresnel", category: .tungsten, kind: .fresnel, technology: .tungsten,
                       ratedPower: 2000, color: .fixed(3200), distribution: .beam, defaultBeam: 55, beamRange: 15...55,
                       reference: ref(1900, at: 3, beam: 55, "Full flood"), emitterWidth: 0.25, emitterHeight: 0.25,
                       hasBarnDoors: true),
        FixtureProfile(id: "lantern-300-bi", name: "LED lantern / space light · bi-colour (≈300 W)", category: .spaceLight, kind: .spaceLight, technology: .led,
                       ratedPower: 300, color: .biColour(2700, 6500), distribution: .omni, defaultBeam: 360,
                       reference: ref(110, at: 3, "5600 K"), emitterWidth: 0.65, emitterHeight: 0.65),
        FixtureProfile(id: "bulb-led-60", name: "Household LED bulb (60 W equivalent)", category: .practical, kind: .practical, technology: .led,
                       ratedPower: 9, color: .fixed(2700), distribution: .omni, defaultBeam: 360,
                       reference: ref(64, at: 1, "About 800 lm, bare"), emitterWidth: 0.06, emitterHeight: 0.1),
        FixtureProfile(id: "bulb-tungsten-100", name: "Tungsten bulb 100 W", category: .practical, kind: .practical, technology: .tungsten,
                       ratedPower: 100, color: .fixed(2850), distribution: .omni, defaultBeam: 360,
                       reference: ref(110, at: 1, "About 1,400 lm, bare"), emitterWidth: 0.06, emitterHeight: 0.1),
    ]

    static let modifiers: [LightModifier] = [
        LightModifier(id: "reflector-55", name: "Standard reflector (55°)", appliesTo: [.cob], transmission: 1,
                      distribution: .beam, beam: 55, allowsBarnDoors: true),
        LightModifier(id: "reflector-30", name: "Narrow reflector (30°)", appliesTo: [.cob], transmission: 0.92,
                      distribution: .beam, beam: 30, allowsBarnDoors: true),
        LightModifier(id: "reflector-15", name: "Long-throw reflector (15°)", appliesTo: [.cob], transmission: 0.85,
                      distribution: .beam, beam: 15),
        LightModifier(id: "cob-bare", name: "Bare (no reflector)", appliesTo: [.cob], transmission: 1.3,
                      distribution: .lambertian),
        LightModifier(id: "fresnel-attachment", name: "Fresnel attachment (12–45°)", appliesTo: [.cob], transmission: 0.55,
                      distribution: .beam, beam: 45, beamRange: 12...45, allowsBarnDoors: true),
        LightModifier(id: "projector", name: "Spot projector (19–36°)", appliesTo: [.cob], transmission: 0.25,
                      distribution: .beam, beam: 26, beamRange: 19...36),
        LightModifier(id: "softbox-90", name: "Softbox 90 cm", appliesTo: [.cob, .fresnel, .hmi, .tungsten], transmission: 0.5,
                      distribution: .lambertian, size: 0.9),
        LightModifier(id: "softbox-90-grid", name: "Softbox 90 cm + 40° grid", appliesTo: [.cob, .fresnel, .hmi, .tungsten], transmission: 0.33,
                      distribution: .beam, beam: 40, size: 0.9),
        LightModifier(id: "softbox-150", name: "Large softbox 150 cm", appliesTo: [.cob, .hmi], transmission: 0.45,
                      distribution: .lambertian, size: 1.5),
        LightModifier(id: "lantern-65", name: "Lantern 65 cm", appliesTo: [.cob], transmission: 0.55,
                      distribution: .omni, size: 0.65),
        LightModifier(id: "panel-grid-40", name: "Egg-crate grid (40°)", appliesTo: [.panel, .soft], transmission: 0.65,
                      distribution: .beam, beam: 40, allowsBarnDoors: true),
        LightModifier(id: "panel-softbox", name: "Panel softbox", appliesTo: [.panel], transmission: 0.6,
                      distribution: .lambertian, size: 0.6),
        LightModifier(id: "par-spot", name: "Spot lens (12°)", appliesTo: [.hmi], transmission: 1,
                      distribution: .beam, beam: 12, allowsBarnDoors: true),
        LightModifier(id: "par-wide", name: "Wide flood lens (50°)", appliesTo: [.hmi], transmission: 0.95,
                      distribution: .beam, beam: 50, allowsBarnDoors: true),
        LightModifier(id: "par-superwide", name: "Super-wide lens (70°)", appliesTo: [.hmi], transmission: 0.9,
                      distribution: .beam, beam: 70, allowsBarnDoors: true),
        LightModifier(id: "shade", name: "Lampshade (fabric)", appliesTo: [.practical], transmission: 0.55,
                      distribution: .omni, size: 0.35),
    ]

    static let filters: [LightFilter] = [
        LightFilter(id: "cto-full", name: "Full CTO", transmission: 0.55, mired: 159),
        LightFilter(id: "cto-half", name: "½ CTO", transmission: 0.70, mired: 81),
        LightFilter(id: "cto-quarter", name: "¼ CTO", transmission: 0.81, mired: 42),
        LightFilter(id: "ctb-full", name: "Full CTB", transmission: 0.36, mired: -131),
        LightFilter(id: "ctb-half", name: "½ CTB", transmission: 0.52, mired: -68),
        LightFilter(id: "ctb-quarter", name: "¼ CTB", transmission: 0.75, mired: -30),
        LightFilter(id: "plus-green-quarter", name: "¼ Plus Green", transmission: 0.87),
        LightFilter(id: "minus-green-quarter", name: "¼ Minus Green", transmission: 0.82),
        LightFilter(id: "nd-3", name: "ND 0.3 (1 stop)", transmission: 0.5),
        LightFilter(id: "nd-6", name: "ND 0.6 (2 stops)", transmission: 0.25),
        LightFilter(id: "nd-9", name: "ND 0.9 (3 stops)", transmission: 0.125),
        LightFilter(id: "diff-light", name: "Light diffusion (opal / ¼ frost)", transmission: 0.8, diffusion: .light),
        LightFilter(id: "diff-medium", name: "Medium diffusion (½ white)", transmission: 0.55, diffusion: .medium),
        LightFilter(id: "diff-heavy", name: "Heavy diffusion (full white)", transmission: 0.36, diffusion: .heavy),
    ]

    static func profile(id: String?) -> FixtureProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    static func modifier(id: String?) -> LightModifier? {
        guard let id else { return nil }
        return modifiers.first { $0.id == id }
    }

    static func filter(id: String) -> LightFilter? { filters.first { $0.id == id } }

    static func modifiers(for profile: FixtureProfile) -> [LightModifier] {
        modifiers.filter { $0.appliesTo.contains(profile.category) }
    }

    /// Type used for units placed before the fixture library existed, and the first choice per kind.
    static func defaultProfile(for kind: LightKind) -> FixtureProfile {
        let id: String
        switch kind {
        case .fresnel: id = "fresnel-led-200-bi"
        case .hmi: id = "hmi-1800-par"
        case .ledPanel: id = "panel-1x1-bi"
        case .tube: id = "tube-4ft-rgb"
        case .softbox: id = "mat-4x4-bi"
        case .spaceLight: id = "lantern-300-bi"
        case .practical: id = "bulb-led-60"
        default: id = "cob-300-bi"
        }
        return profile(id: id) ?? profiles[0]
    }
}

/// Everything the calculator and the views need about one unit at its current settings.
struct ResolvedPhotometrics {
    var profile: FixtureProfile
    var modifier: LightModifier?
    var distribution: BeamDistribution
    /// Effective full beam angle (50 % points) for beams; nominal for other shapes.
    var beamAngle: Double
    var beamIsAdjustable: Bool
    var beamRange: ClosedRange<Double>?
    /// Peak intensity at the current settings (cd).
    var peakIntensity: Double
    /// Flux leaving the unit at the current settings (lm, estimated).
    var flux: Double
    /// Radius of a disc with the emitting face's area (m) — soft sources behave like this up close.
    var emitterRadius: Double
    /// Length of a tube (m).
    var tubeLength: Double
    var kelvin: Double
    /// Display colour, 0…1 RGB.
    var color: (r: Double, g: Double, b: Double)
    /// Estimated electrical draw at the current output (W).
    var drawWatts: Double
    var barnDoorsAvailable: Bool
    var provenance: Provenance
    /// Assumptions to show next to estimates.
    var notes: [String]

    /// Illuminance (lux) on the beam axis at `distance`, sensor facing the unit, nothing in the way.
    func illuminanceOnAxis(at distance: Double) -> Double {
        peakIntensity * Photometry.distanceFactor(distance, distribution: distribution,
                                                  emitterRadius: emitterRadius, tubeLength: tubeLength)
    }

    /// Distance on the beam axis at which the unit gives `lux`, or nil if it can't reach it even up close (≥ 0.3 m).
    func distance(forLux lux: Double) -> Double? {
        guard lux > 0, peakIntensity > 0 else { return nil }
        var lo = 0.3, hi = 200.0
        if illuminanceOnAxis(at: lo) < lux { return nil }
        if illuminanceOnAxis(at: hi) > lux { return hi }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if illuminanceOnAxis(at: mid) > lux { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

enum Photometry {
    /// Geometric falloff: E = I × factor. Point sources follow the inverse-square law; a diffuse
    /// disc of radius R gives exactly I/(d² + R²) on its axis; a diffuse tube of length L gives
    /// I·(α + sin α cos α)/(L·d) broadside, α = atan(L / 2d). All tend to 1/d² far away.
    static func distanceFactor(_ d: Double, distribution: BeamDistribution, emitterRadius: Double, tubeLength: Double) -> Double {
        let d = max(d, 0.05)
        switch distribution {
        case .omni:
            return 1 / (d * d)
        case .tube:
            guard tubeLength > 0.01 else { return 1 / (d * d) }
            let a = atan(tubeLength / (2 * d))
            return (a + sin(a) * cos(a)) / (tubeLength * d)
        case .lambertian, .beam:
            return 1 / (d * d + emitterRadius * emitterRadius)
        }
    }

    /// Mired arithmetic for gels.
    static func shifted(kelvin: Double, mired: Double) -> Double {
        let m = 1_000_000 / max(kelvin, 1000) + mired
        return 1_000_000 / max(m, 50)
    }

    /// Relative luminance of a hue/saturation colour against white, used to scale RGB output.
    /// Saturated colours lose a lot of output; pure blue is under 10 % of white.
    static func rgbOutputFactor(hue: Double, saturation: Double) -> Double {
        let c = rgb(hue: hue, saturation: saturation)
        let y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return max(0.03, min(1, y))
    }

    /// Fully bright colour for a hue (0–360°) and saturation (0–1); max channel is 1.
    static func rgb(hue: Double, saturation: Double) -> (r: Double, g: Double, b: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (1, x, 0)
        case 1: (r, g, b) = (x, 1, 0)
        case 2: (r, g, b) = (0, 1, x)
        case 3: (r, g, b) = (0, x, 1)
        case 4: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        let s = min(max(saturation, 0), 1)
        return (1 - s + s * r, 1 - s + s * g, 1 - s + s * b)
    }
}

extension LightFixture {
    /// Fixture type: the one chosen, or the default for its drawing kind.
    var profile: FixtureProfile { FixtureLibrary.profile(id: profileID) ?? FixtureLibrary.defaultProfile(for: kind) }

    /// Fitted modifier: the chosen one if it suits the fixture type, else the type's default.
    var modifierItem: LightModifier? {
        let p = profile
        if let id = modifierID {
            // "None" on a unit that ships with a reflector means running it bare.
            if id == "none" { return p.defaultModifierID == nil ? nil : FixtureLibrary.modifier(id: "cob-bare") }
            if let m = FixtureLibrary.modifier(id: id), m.appliesTo.contains(p.category) { return m }
        }
        return FixtureLibrary.modifier(id: p.defaultModifierID)
    }

    var filterItems: [LightFilter] { (filterIDs ?? []).compactMap(FixtureLibrary.filter(id:)) }
    var barnDoorSettings: BarnDoors { barnDoors ?? .open }
    var usesRGB: Bool { profile.color.rgb && colorMode == .rgb }

    /// Photometrics at the current settings. Pure function of the stored values.
    var photometrics: ResolvedPhotometrics {
        let p = profile
        let reference = photometricOverride ?? p.reference
        var notes: [String] = []

        // 1. Reference reading → flux in the reference configuration.
        let refModifier = FixtureLibrary.modifier(id: p.defaultModifierID)
        let refDistribution = refModifier?.distribution ?? p.distribution
        let refBeam = reference.beamAngle ?? refModifier?.beam ?? p.defaultBeam
        let refRadius = (p.emitterWidth * p.emitterHeight / .pi).squareRoot()
        let refFactor = Photometry.distanceFactor(reference.distance, distribution: refDistribution,
                                                  emitterRadius: refRadius, tubeLength: p.emitterWidth)
        let refPeak = reference.lux / max(refFactor, 1e-9)
        var flux = refPeak * refDistribution.solidAngleFactor(beamAngle: refBeam)

        // 2. Modifier: shape, size and loss relative to the reference configuration.
        let modifier = modifierItem
        var distribution = modifier?.distribution ?? p.distribution
        var radius = refRadius
        if let m = modifier {
            flux *= m.transmission / (refModifier?.transmission ?? 1)
            if let size = m.size { radius = (size * size / .pi).squareRoot() }
        }
        let range = modifier?.beamRange ?? (modifier?.beam == nil ? p.beamRange : nil)
        var beam: Double
        if let range {
            beam = min(max(beamAngle, range.lowerBound), range.upperBound)
        } else {
            beam = modifier?.beam ?? p.defaultBeam
        }
        if distribution != .beam { beam = distribution.nominalBeam ?? beam }

        // 3. Filters: transmission, colour shift, diffusion.
        var kelvin = p.color.isAdjustable ? min(max(colorTemperature, p.color.minKelvin), p.color.maxKelvin) : p.color.minKelvin
        for f in filterItems {
            flux *= f.transmission
            kelvin = Photometry.shifted(kelvin: kelvin, mired: f.mired)
            switch f.diffusion {
            case .light?: if distribution == .beam { beam = min(beam + 15, 160) }
            case .medium?: if distribution == .beam { beam = min(max(beam * 1.8, 90), 160) }
            case .heavy?: if distribution == .beam { distribution = .lambertian; beam = 120 }
            case nil: break
            }
        }

        // 4. Colour mode and output level.
        if usesRGB {
            flux *= Photometry.rgbOutputFactor(hue: hue ?? 0, saturation: saturation ?? 1)
            notes.append("Colour output scaled by the colour's brightness relative to white (estimate).")
        }
        let output = isOn ? min(max(dimmer, p.minOutput), 1) : 0
        flux *= output
        kelvin = p.technology.kelvin(kelvin, output: output)
        if p.technology == .tungsten && output < 0.99 && output > 0 { notes.append("Tungsten warms as it dims.") }

        let peak = flux / distribution.solidAngleFactor(beamAngle: beam)
        let display: (r: Double, g: Double, b: Double) = usesRGB
            ? Photometry.rgb(hue: hue ?? 0, saturation: saturation ?? 1)
            : Kelvin.rgb(kelvin)
        notes.append(reference.provenance == .manual
                     ? "Output from your reference reading: \(Int(reference.lux)) lx at \(String(format: "%g", reference.distance)) m."
                     : "Output estimated for a typical \(p.name) (\(reference.note.lowercased())). Enter the maker's data in Details for better figures.")

        return ResolvedPhotometrics(
            profile: p, modifier: modifier, distribution: distribution, beamAngle: beam,
            beamIsAdjustable: range != nil && distribution == .beam, beamRange: range,
            peakIntensity: peak, flux: flux, emitterRadius: radius, tubeLength: p.emitterWidth,
            kelvin: kelvin, color: display,
            drawWatts: p.ratedPower * p.technology.drawFraction(output: output),
            barnDoorsAvailable: p.hasBarnDoors ? (modifier?.allowsBarnDoors ?? true) : (modifier?.allowsBarnDoors ?? false),
            provenance: reference.provenance == .manual ? .manual : .estimated,
            notes: notes)
    }

    /// Switches the unit to a fixture type, resetting the settings that belong to the old type.
    mutating func apply(profile p: FixtureProfile) {
        profileID = p.id
        kind = p.kind
        modifierID = nil
        width = max(p.emitterWidth, kind.defaultWidth * 0.5)
        if let range = p.beamRange { beamAngle = min(max(beamAngle, range.lowerBound), range.upperBound) } else { beamAngle = p.defaultBeam }
        colorTemperature = p.color.isAdjustable ? min(max(colorTemperature, p.color.minKelvin), p.color.maxKelvin) : p.color.minKelvin
        if !p.color.rgb { colorMode = nil }
        power = p.powerLabel
        photometricOverride = nil
        if !p.hasBarnDoors { barnDoors = nil }
    }
}
