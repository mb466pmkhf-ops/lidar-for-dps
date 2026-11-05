import Foundation

/// Camera exposure settings for planning a stop. Lux readings come from `LightingCalculator`;
/// this turns them into stops with the incident-meter equation
///
///     N² / t = E · S / C
///
/// (N = T-stop, t = exposure time in s, E = illuminance in lux, S = ISO, C = meter calibration,
/// 250 for a flat receptor). A light meter assumes a lens that passes all the light, so the stop
/// it gives is a T-stop; the f-stop that gives the same exposure is T × √transmission.
/// ND is subtracted from the light reaching the sensor. A T-stop is an exposure setting, never a
/// measure of how bright the scene is.
struct ExposureSettings: Codable, Hashable {
    static let meterCalibration = 250.0

    var iso: Double = 800
    var frameRate: Double = 24
    var shutterAngle: Double = 180
    /// When set, the shutter is given as a speed (seconds) instead of an angle (stills, or a
    /// camera set in speed mode).
    var shutterSeconds: Double? = nil
    var tStop: Double = 2.8
    /// Fraction of light the lens passes. T = f / √transmission.
    var lensTransmission: Double = 0.85
    var ndStops: Double = 0

    init() {}

    enum CodingKeys: String, CodingKey { case iso, frameRate, shutterAngle, shutterSeconds, tStop, lensTransmission, ndStops }

    /// Tolerates settings saved by older or newer versions with keys missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iso = try c.decodeIfPresent(Double.self, forKey: .iso) ?? iso
        frameRate = try c.decodeIfPresent(Double.self, forKey: .frameRate) ?? frameRate
        shutterAngle = try c.decodeIfPresent(Double.self, forKey: .shutterAngle) ?? shutterAngle
        shutterSeconds = try c.decodeIfPresent(Double.self, forKey: .shutterSeconds)
        tStop = try c.decodeIfPresent(Double.self, forKey: .tStop) ?? tStop
        lensTransmission = try c.decodeIfPresent(Double.self, forKey: .lensTransmission) ?? lensTransmission
        ndStops = try c.decodeIfPresent(Double.self, forKey: .ndStops) ?? ndStops
    }

    /// Exposure time per frame (s).
    var exposureTime: Double {
        if let shutterSeconds { return max(shutterSeconds, 1e-5) }
        return max(shutterAngle, 1) / 360 / max(frameRate, 1)
    }

    /// Lens aperture (geometric) that matches the T-stop on this lens.
    var fStop: Double { tStop * lensTransmission.squareRoot() }

    /// Incident reading (lux) that places a mid-grey subject correctly at these settings: the key level.
    var keyLux: Double { lux(forTStop: tStop) }

    func lux(forTStop n: Double) -> Double {
        Self.meterCalibration * n * n * pow(2, ndStops) / (iso * exposureTime)
    }

    /// T-stop an incident meter would give for `lux` at this ISO, shutter and ND.
    func tStop(forLux lux: Double) -> Double {
        (max(lux, 1e-6) * iso * exposureTime / (Self.meterCalibration * pow(2, ndStops))).squareRoot()
    }

    /// Stops over (+) or under (−) the set stop for an incident reading.
    func stops(forLux lux: Double) -> Double {
        log2(max(lux, 1e-6) / keyLux)
    }

    var shutterDescription: String {
        if let shutterSeconds { return Self.speedLabel(shutterSeconds) }
        return "\(Self.trim(shutterAngle))° @ \(Self.trim(frameRate)) fps (\(Self.speedLabel(exposureTime)))"
    }

    var summary: String {
        var s = "ISO \(Int(iso)) · \(shutterSeconds == nil ? "\(Self.trim(shutterAngle))° @ \(Self.trim(frameRate))" : Self.speedLabel(exposureTime)) · \(Self.stopLabel(tStop, prefix: "T"))"
        if ndStops > 0 { s += " · ND \(String(format: "%.1f", ndStops * 0.3))" }
        return s
    }

    // MARK: Formatting

    static let fullStops: [Double] = [1, 1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22, 32, 45, 64]

    /// "T2.8", "T2.8 +⅓", "T4 −⅓": nearest third of a stop, named from the nearest full stop.
    static func stopLabel(_ n: Double, prefix: String = "T") -> String {
        guard n > 0 else { return "—" }
        let thirds = Int((6 * log2(n)).rounded())          // N = 2^(k/6) → thirds of a stop from 1
        let fullIndex = Int((Double(thirds) / 3).rounded())
        let offset = thirds - fullIndex * 3
        let name: String
        if fullIndex >= 0 && fullIndex < fullStops.count {
            name = trim(fullStops[fullIndex])
        } else {
            name = String(format: "%.2g", pow(2, Double(fullIndex) / 2))
        }
        switch offset {
        case 1: return "\(prefix)\(name) +⅓"
        case -1: return "\(prefix)\(name) −⅓"
        default: return "\(prefix)\(name)"
        }
    }

    /// "+1⅓", "−⅔", "±0" — exposure difference in thirds.
    static func stopsDelta(_ stops: Double) -> String {
        let thirds = Int((stops * 3).rounded())
        if thirds == 0 { return "±0" }
        let sign = thirds > 0 ? "+" : "−"
        let whole = abs(thirds) / 3, frac = abs(thirds) % 3
        let fracText = frac == 1 ? "⅓" : (frac == 2 ? "⅔" : "")
        return sign + (whole > 0 ? "\(whole)" : "") + fracText
    }

    static func speedLabel(_ seconds: Double) -> String {
        if seconds >= 1 { return "\(trim(seconds)) s" }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    static func trim(_ v: Double) -> String {
        abs(v - v.rounded()) < 0.001 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    static let isoPresets: [Double] = [100, 200, 400, 640, 800, 1280, 1600, 3200, 6400]
    static let frameRates: [Double] = [23.976, 24, 25, 30, 48, 50, 60, 100, 120]
    static let shutterAngles: [Double] = [45, 90, 144, 172.8, 180, 270, 360]
    static let tStops: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]
}

extension Location {
    /// Camera exposure used to read lux as stops. Stored only once changed.
    var exposureSettings: ExposureSettings {
        get { exposure ?? ExposureSettings() }
        set { exposure = newValue }
    }
}
