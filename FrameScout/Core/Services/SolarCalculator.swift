import Foundation

struct SolarPosition: Hashable {
    /// Degrees clockwise from true north.
    var azimuth: Double
    /// Degrees above the horizon (includes approximate atmospheric refraction).
    var elevation: Double

    var isUp: Bool { elevation > -0.833 }
}

struct SunEvents: Hashable {
    var civilDawn: Date?
    var sunrise: Date?
    var goldenHourMorningEnd: Date?
    var solarNoon: Date?
    var goldenHourEveningStart: Date?
    var sunset: Date?
    var civilDusk: Date?
    var noonElevation: Double
}

/// NOAA solar position algorithm (accurate to well under a degree for 1900–2100).
/// Works fully offline — only latitude, longitude and time are needed.
enum SolarCalculator {
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// - Parameter refraction: add atmospheric refraction to the elevation (apparent position).
    static func position(date: Date, latitude: Double, longitude: Double, refraction: Bool = true) -> SolarPosition {
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let t = (jd - 2451545.0) / 36525.0

        var l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        if l0 < 0 { l0 += 360 }
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * m)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * m)) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let decl = asin(sin(rad(eps)) * sin(rad(lambda)))

        let y = pow(tan(rad(eps / 2)), 2)
        let eqTime = 4 * deg(
            y * sin(2 * rad(l0))
            - 2 * e * sin(rad(m))
            + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0))
            - 0.5 * y * y * sin(4 * rad(l0))
            - 1.25 * e * e * sin(2 * rad(m))
        )

        let secondsIntoDay = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        let utcMinutes = (secondsIntoDay < 0 ? secondsIntoDay + 86400 : secondsIntoDay) / 60
        var trueSolarTime = (utcMinutes + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if trueSolarTime < 0 { trueSolarTime += 1440 }
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let latR = rad(latitude)
        let haR = rad(hourAngle)
        let cosZenith = max(-1, min(1, sin(latR) * sin(decl) + cos(latR) * cos(decl) * cos(haR)))
        let zenith = acos(cosZenith)
        var elevation = 90 - deg(zenith)

        var azimuth = deg(atan2(sin(haR), cos(haR) * sin(latR) - tan(decl) * cos(latR))) + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }

        if refraction { elevation += refractionCorrection(elevation: elevation) }
        return SolarPosition(azimuth: azimuth, elevation: elevation)
    }

    /// NOAA approximation of atmospheric refraction, in degrees.
    private static func refractionCorrection(elevation e: Double) -> Double {
        if e > 85 { return 0 }
        let te = tan(rad(e))
        let arcsec: Double
        if e > 5 {
            arcsec = 58.1 / te - 0.07 / pow(te, 3) + 0.000086 / pow(te, 5)
        } else if e > -0.575 {
            arcsec = 1735 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)))
        } else {
            arcsec = -20.772 / te
        }
        return arcsec / 3600
    }

    /// Sun events for the local calendar day containing `date` in `timeZone`.
    /// Found by sampling the day, so polar day/night simply returns nil events.
    static func events(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> SunEvents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let step: TimeInterval = 120
        let samples = Int(86400 / step)

        var elevations: [Double] = []
        elevations.reserveCapacity(samples + 1)
        for i in 0...samples {
            // Geometric elevation: the standard -0.833° threshold already includes refraction.
            elevations.append(position(date: start.addingTimeInterval(Double(i) * step),
                                       latitude: latitude, longitude: longitude, refraction: false).elevation)
        }

        func crossing(_ threshold: Double, rising: Bool) -> Date? {
            for i in 0..<samples {
                let a = elevations[i], b = elevations[i + 1]
                let crosses = rising ? (a < threshold && b >= threshold) : (a >= threshold && b < threshold)
                if crosses {
                    let f = (threshold - a) / (b - a)
                    return start.addingTimeInterval((Double(i) + f) * step)
                }
            }
            return nil
        }

        let maxIndex = elevations.indices.max { elevations[$0] < elevations[$1] } ?? 0

        return SunEvents(
            civilDawn: crossing(-6, rising: true),
            sunrise: crossing(-0.833, rising: true),
            goldenHourMorningEnd: crossing(6, rising: true),
            solarNoon: start.addingTimeInterval(Double(maxIndex) * step),
            goldenHourEveningStart: crossing(6, rising: false),
            sunset: crossing(-0.833, rising: false),
            civilDusk: crossing(-6, rising: false),
            noonElevation: elevations[maxIndex]
        )
    }

    /// Sun path samples for drawing, every `minutes` minutes, only while above the horizon.
    static func path(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone,
                     minutes: Int = 15) -> [(Date, SolarPosition)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        var result: [(Date, SolarPosition)] = []
        var t = 0
        while t <= 1440 {
            let d = start.addingTimeInterval(Double(t) * 60)
            let p = position(date: d, latitude: latitude, longitude: longitude)
            if p.elevation > -1 { result.append((d, p)) }
            t += minutes
        }
        return result
    }

    static func compassName(_ azimuth: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        var a = azimuth.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return names[Int((a / 22.5).rounded()) % 16]
    }
}

/// How sunlight relates to a window / wall opening.
struct WindowLight: Identifiable, Hashable {
    var id: UUID
    /// True bearing the window faces (outward).
    var facing: Double
    /// 0...1 relative intensity of direct sun on the window plane (cosine of incidence), 0 when in shade.
    var directSun: Double
    var width: Double
    var height: Double

    var receivesDirectSun: Bool { directSun > 0.02 }

    static func evaluate(facing: Double, sun: SolarPosition) -> Double {
        guard sun.elevation > 0 else { return 0 }
        var delta = abs(sun.azimuth - facing).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta = 360 - delta }
        guard delta < 90 else { return 0 }
        let e = sun.elevation * .pi / 180
        let d = delta * .pi / 180
        return max(0, cos(e) * cos(d))
    }
}
