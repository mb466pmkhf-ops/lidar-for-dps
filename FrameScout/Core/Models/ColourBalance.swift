import Foundation

/// How each light's colour reads at the camera's white balance. Mirrored by web/src/model/colour.ts.
/// The figures come from the colour temperature set on each unit, its gels and dimming (`photometrics`)
/// and the white balance typed in for the camera. They describe the settings, not a measured colour,
/// so they are estimates.
enum ColourBalance {
    /// White balance choices offered in the pickers on both platforms (Kelvin).
    static let presets: [Double] = [2700, 3200, 4300, 5000, 5600, 6500]
    /// Used to judge colour when no white balance is set: daylight.
    static let defaultWhiteBalance = 5600.0
    /// Mireds of a full CTO and a full CTB, the yardsticks a gaffer speaks in.
    static let fullCTOMired = 159.0
    static let fullCTBMired = 131.0
    /// Within this many mireds a source reads as white at the camera's balance (about ⅛ CTO).
    static let matchMired = 20.0

    enum Tone: String { case warm, cool, match }

    struct Shift: Equatable {
        var mired: Double
        var tone: Tone
        var label: String
    }

    struct Row: Identifiable {
        var id: UUID
        var name: String
        var kelvin: Double?
        var rgb: Bool
        var shift: Shift?
    }

    struct Summary {
        var whiteBalance: Double
        var rows: [Row]
        var warm = 0, cool = 0, match = 0, rgb = 0
        var line: String
    }

    private static func mired(_ kelvin: Double) -> Double { 1_000_000 / max(kelvin, 1000) }

    /// "½", "¼"… of a full gel, to the nearest eighth; whole numbers past one.
    static func gelAmount(_ f: Double) -> String {
        if f > 1.125 {
            let halves = (f * 2).rounded() / 2
            let whole = Int(halves)
            return halves == Double(whole) ? "\(whole)× full" : "\(whole)½× full"
        }
        let eighths = max(1, Int((f * 8).rounded()))
        return ["⅛", "¼", "⅜", "½", "⅝", "¾", "⅞", "full"][min(eighths, 8) - 1]
    }

    /// How a source of `kelvin` reads on a camera balanced to `whiteBalance`: positive mireds read warm.
    static func shift(kelvin: Double, whiteBalance: Double) -> Shift {
        let m = mired(kelvin) - mired(whiteBalance)
        if abs(m) < matchMired { return Shift(mired: m, tone: .match, label: "reads white") }
        return m > 0
            ? Shift(mired: m, tone: .warm, label: "reads warm, about \(gelAmount(m / fullCTOMired)) CTO")
            : Shift(mired: m, tone: .cool, label: "reads cool, about \(gelAmount(-m / fullCTBMired)) CTB")
    }

    /// Every light that is on and gives light, with how it reads at `whiteBalance`.
    static func summary(_ lights: [LightFixture], whiteBalance: Double) -> Summary {
        let rows: [Row] = lights.filter { $0.isOn && $0.kind.emits }.map { l in
            if l.usesRGB { return Row(id: l.id, name: l.name, kelvin: nil, rgb: true, shift: nil) }
            let k = l.photometrics.kelvin
            return Row(id: l.id, name: l.name, kelvin: k, rgb: false, shift: shift(kelvin: k, whiteBalance: whiteBalance))
        }
        func count(_ t: Tone) -> Int { rows.filter { $0.shift?.tone == t }.count }
        let warm = count(.warm), cool = count(.cool), match = count(.match), rgb = rows.filter(\.rgb).count
        let parts = [match > 0 ? "\(match) white" : "", warm > 0 ? "\(warm) warm" : "", cool > 0 ? "\(cool) cool" : "",
                     rgb > 0 ? "\(rgb) RGB colour" : ""].filter { !$0.isEmpty }
        let line = rows.isEmpty ? "No lights on" : "At \(Int(whiteBalance.rounded())) K: \(parts.joined(separator: ", "))"
        return Summary(whiteBalance: whiteBalance, rows: rows, warm: warm, cool: cool, match: match, rgb: rgb, line: line)
    }
}
