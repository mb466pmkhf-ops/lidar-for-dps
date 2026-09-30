import Foundation

/// Metric by default; imperial (feet/inches) when the user toggles it in Settings.
enum UnitsFormatter {
    static let imperialKey = "useImperialUnits"

    static var useImperial: Bool { UserDefaults.standard.bool(forKey: imperialKey) }

    static func distance(_ metres: Double?, precise: Bool = false) -> String {
        guard let metres, metres.isFinite else { return "—" }
        if useImperial {
            let totalInches = metres / 0.0254
            let feet = Int(totalInches / 12)
            let inches = totalInches - Double(feet) * 12
            return precise ? String(format: "%d′ %.1f″", feet, inches) : String(format: "%d′ %.0f″", feet, inches.rounded())
        }
        if metres < 1 && precise { return String(format: "%.1f cm", metres * 100) }
        return String(format: precise ? "%.3f m" : "%.2f m", metres)
    }

    static func area(_ squareMetres: Double?) -> String {
        guard let squareMetres, squareMetres.isFinite else { return "—" }
        if useImperial { return String(format: "%.0f ft²", squareMetres * 10.7639) }
        return String(format: "%.1f m²", squareMetres)
    }

    static func dimensions(_ a: Double?, _ b: Double?) -> String {
        guard a != nil || b != nil else { return "—" }
        return "\(distance(a)) × \(distance(b))"
    }

    static func time(_ date: Date?, in zone: TimeZone) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
