import Foundation

/// A cine lens series: the focal lengths a rental house would hand you, its squeeze and the
/// format it is made to cover. Coverage is the maker's format class, not a measured image
/// circle, so the vignetting hint built on it is an estimate.
struct LensSeries: Identifiable, Hashable {
    enum Coverage: String, Hashable {
        case super35, fullFrame, largeFormat

        var label: String {
            switch self {
            case .super35: return "Super 35"
            case .fullFrame: return "Full frame"
            case .largeFormat: return "Large format"
            }
        }

        /// Largest sensor diagonal (mm) the class normally covers without dark corners.
        var maxDiagonal: Double {
            switch self {
            case .super35: return 34
            case .fullFrame: return 44
            case .largeFormat: return 47
            }
        }
    }

    var id: String
    var maker: String
    var name: String
    /// Primes: every focal length in the set. Zooms: the two ends.
    var focalLengths: [Double]
    var isZoom = false
    /// 1 for spherical lenses.
    var squeeze: Double = 1
    var coverage: Coverage

    var displayName: String { maker.isEmpty ? name : "\(maker) \(name)" }

    /// Focal lengths to offer as steps. Zooms get the common focal lengths inside their range.
    var steps: [Double] {
        guard isZoom, let lo = focalLengths.first, let hi = focalLengths.last else { return focalLengths }
        let inside = LensLibrary.commonFocalLengths.filter { $0 > lo && $0 < hi }
        return [lo] + inside + [hi]
    }

    func contains(_ focal: Double) -> Bool {
        if isZoom, let lo = focalLengths.first, let hi = focalLengths.last { return focal >= lo - 0.01 && focal <= hi + 0.01 }
        return focalLengths.contains { abs($0 - focal) < 0.01 }
    }

    /// Nearest focal length this lens can actually be set to.
    func nearest(to focal: Double) -> Double {
        if isZoom, let lo = focalLengths.first, let hi = focalLengths.last { return min(max(focal, lo), hi) }
        return focalLengths.min { abs($0 - focal) < abs($1 - focal) } ?? focal
    }

    /// "24–290 mm" for a zoom, "16 lenses, 12–280 mm" for a set. Half millimetres stay (15.5).
    var rangeLabel: String {
        let lo = LensLibrary.focalNumber(focalLengths.first ?? 0), hi = LensLibrary.focalNumber(focalLengths.last ?? 0)
        return isZoom ? "\(lo)–\(hi) mm" : "\(focalLengths.count) lenses, \(lo)–\(hi) mm"
    }

    /// Diagonal (mm) of the part of the sensor the frame lines use. Anamorphic lenses squeeze the
    /// picture sideways, so the frame is fitted to the desqueezed sensor and then squeezed back.
    func usedDiagonal(on sensor: SensorFormat, aspect: FrameAspect = .sensor) -> Double {
        var desqueezed = sensor
        desqueezed.width = sensor.width * squeeze
        let area = Optics.imageArea(sensor: desqueezed, aspect: aspect)
        let w = area.width / squeeze, h = area.height
        return (w * w + h * h).squareRoot()
    }

    /// True when the framed part of the sensor is bigger than this lens class is made for. An
    /// estimate from the maker's format class, not a measured image circle: a lens can cover a
    /// little more (or less) than its class, and focus distance changes it.
    func mayVignette(on sensor: SensorFormat, aspect: FrameAspect = .sensor) -> Bool {
        usedDiagonal(on: sensor, aspect: aspect) > coverage.maxDiagonal + 0.01
    }
}

enum LensLibrary {
    static let commonFocalLengths: [Double] = [14, 18, 21, 24, 28, 32, 35, 40, 50, 65, 75, 85, 100, 135]

    /// "Any lens": free focal lengths, no coverage hint.
    static let anyID = "any"

    static let series: [LensSeries] = [
        LensSeries(id: "angenieux-15-40", maker: "Angénieux", name: "Optimo 15–40 zoom",
                   focalLengths: [15, 40], isZoom: true, coverage: .super35),
        LensSeries(id: "angenieux-24-290", maker: "Angénieux", name: "Optimo 24–290 zoom",
                   focalLengths: [24, 290], isZoom: true, coverage: .super35),
        LensSeries(id: "angenieux-28-76", maker: "Angénieux", name: "Optimo 28–76 zoom",
                   focalLengths: [28, 76], isZoom: true, coverage: .super35),
        LensSeries(id: "angenieux-45-120", maker: "Angénieux", name: "Optimo 45–120 zoom",
                   focalLengths: [45, 120], isZoom: true, coverage: .super35),
        LensSeries(id: "arri-signature", maker: "ARRI", name: "Signature Prime",
                   focalLengths: [12, 15, 18, 21, 25, 29, 35, 40, 47, 58, 75, 95, 125, 150, 200, 280], coverage: .largeFormat),
        LensSeries(id: "arri-master-prime", maker: "ARRI / Zeiss", name: "Master Prime",
                   focalLengths: [12, 14, 16, 18, 21, 25, 27, 32, 35, 40, 50, 65, 75, 100, 135, 150], coverage: .super35),
        LensSeries(id: "arri-ultra-prime", maker: "ARRI / Zeiss", name: "Ultra Prime",
                   focalLengths: [8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 50, 65, 85, 100, 135, 180], coverage: .super35),
        LensSeries(id: "arri-master-anamorphic", maker: "ARRI", name: "Master Anamorphic 2×",
                   focalLengths: [28, 32, 35, 40, 50, 60, 75, 100, 135, 180], squeeze: 2, coverage: .super35),
        LensSeries(id: "arri-alura-18-80", maker: "ARRI", name: "Alura 18–80 zoom",
                   focalLengths: [18, 80], isZoom: true, coverage: .super35),
        LensSeries(id: "arri-alura-45-250", maker: "ARRI", name: "Alura 45–250 zoom",
                   focalLengths: [45, 250], isZoom: true, coverage: .super35),
        LensSeries(id: "atlas-orion", maker: "Atlas", name: "Orion 2× anamorphic",
                   focalLengths: [21, 25, 32, 40, 50, 65, 80, 100], squeeze: 2, coverage: .super35),
        LensSeries(id: "canon-sumire", maker: "Canon", name: "CN-E Sumire Prime",
                   focalLengths: [14, 20, 24, 35, 50, 85, 135], coverage: .fullFrame),
        LensSeries(id: "canon-cne-15-47", maker: "Canon", name: "CN-E 15.5–47 zoom",
                   focalLengths: [15.5, 47], isZoom: true, coverage: .super35),
        LensSeries(id: "canon-cne-30-105", maker: "Canon", name: "CN-E 30–105 zoom",
                   focalLengths: [30, 105], isZoom: true, coverage: .super35),
        LensSeries(id: "cooke-s4i", maker: "Cooke", name: "S4/i",
                   focalLengths: [12, 14, 16, 18, 21, 25, 27, 32, 35, 40, 50, 65, 75, 100, 135, 150, 180, 300], coverage: .super35),
        LensSeries(id: "cooke-s7i", maker: "Cooke", name: "S7/i",
                   focalLengths: [16, 18, 21, 25, 27, 32, 40, 50, 65, 75, 100, 135, 180, 300], coverage: .largeFormat),
        LensSeries(id: "cooke-anamorphic-i", maker: "Cooke", name: "Anamorphic/i 2×",
                   focalLengths: [25, 32, 40, 50, 65, 75, 100, 135, 180, 300], squeeze: 2, coverage: .super35),
        LensSeries(id: "fujinon-cabrio-19-90", maker: "Fujinon", name: "Cabrio 19–90 zoom",
                   focalLengths: [19, 90], isZoom: true, coverage: .super35),
        LensSeries(id: "fujinon-premista-19-45", maker: "Fujinon", name: "Premista 19–45 zoom",
                   focalLengths: [19, 45], isZoom: true, coverage: .largeFormat),
        LensSeries(id: "fujinon-premista-28-100", maker: "Fujinon", name: "Premista 28–100 zoom",
                   focalLengths: [28, 100], isZoom: true, coverage: .largeFormat),
        LensSeries(id: "fujinon-premista-80-250", maker: "Fujinon", name: "Premista 80–250 zoom",
                   focalLengths: [80, 250], isZoom: true, coverage: .largeFormat),
        LensSeries(id: "leitz-summilux-c", maker: "Leitz", name: "Summilux-C",
                   focalLengths: [16, 18, 21, 25, 29, 35, 40, 50, 65, 75, 100, 135], coverage: .super35),
        LensSeries(id: "sigma-ff-high-speed", maker: "Sigma", name: "Cine FF High Speed",
                   focalLengths: [14, 20, 24, 28, 35, 40, 50, 65, 85, 105, 135], coverage: .fullFrame),
        LensSeries(id: "zeiss-supreme", maker: "Zeiss", name: "Supreme Prime",
                   focalLengths: [15, 18, 21, 25, 29, 35, 50, 65, 85, 100, 135, 150, 200], coverage: .largeFormat),
        LensSeries(id: "zeiss-cp3", maker: "Zeiss", name: "CP.3",
                   focalLengths: [15, 18, 21, 25, 28, 35, 50, 85, 100, 135], coverage: .fullFrame),
        LensSeries(id: "zeiss-cz2-28-80", maker: "Zeiss", name: "CZ.2 28–80 zoom",
                   focalLengths: [28, 80], isZoom: true, coverage: .fullFrame),
        LensSeries(id: "zeiss-cz2-70-200", maker: "Zeiss", name: "CZ.2 70–200 zoom",
                   focalLengths: [70, 200], isZoom: true, coverage: .fullFrame),
    ]

    static func lens(id: String?) -> LensSeries? {
        guard let id, id != anyID else { return nil }
        return series.first { $0.id == id }
    }

    /// Focal length as a bare number: "50", "15.5".
    static func focalNumber(_ f: Double) -> String { String(format: "%g", (f * 10).rounded() / 10) }

    /// Focal length and squeeze that go with a lens choice. A set brings its own squeeze and
    /// snaps the focal length to a lens it has; "any lens" keeps both as they were. Also used
    /// to tidy settings saved before a set's figures changed.
    static func fit(lensID: String?, focalLength: Double, squeeze: Double) -> (focalLength: Double, squeeze: Double) {
        guard let lens = lens(id: lensID) else { return (focalLength, squeeze) }
        return (lens.nearest(to: focalLength), lens.squeeze)
    }
}
