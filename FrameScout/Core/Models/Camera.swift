import Foundation

/// A camera sensor / recording format. Dimensions are the active image area in millimetres.
struct SensorFormat: Codable, Hashable, Identifiable {
    var id: String
    var manufacturer: String
    var name: String
    var width: Double
    var height: Double

    var displayName: String { manufacturer.isEmpty ? name : "\(manufacturer) \(name)" }
    var aspectRatio: Double { width / height }
    var diagonal: Double { (width * width + height * height).squareRoot() }
    var sizeDescription: String { String(format: "%.2f × %.2f mm", width, height) }
}

enum SensorLibrary {
    static let customID = "custom"

    /// Common cinema formats. Values are published active-area figures (approximate, mode dependent).
    static let presets: [SensorFormat] = [
        SensorFormat(id: "arri-minilf-og", manufacturer: "ARRI", name: "Alexa Mini LF · 4.5K LF Open Gate", width: 36.70, height: 25.54),
        SensorFormat(id: "arri-minilf-169", manufacturer: "ARRI", name: "Alexa Mini LF · 4.3K LF 16:9 UHD", width: 31.68, height: 17.82),
        SensorFormat(id: "arri-35-og", manufacturer: "ARRI", name: "Alexa 35 · 4.6K 3:2 Open Gate", width: 27.99, height: 19.22),
        SensorFormat(id: "arri-35-169", manufacturer: "ARRI", name: "Alexa 35 · 4K 16:9", width: 24.88, height: 14.00),
        SensorFormat(id: "arri-mini-og", manufacturer: "ARRI", name: "Alexa Mini · 3.4K Open Gate", width: 28.25, height: 18.17),
        SensorFormat(id: "sony-venice2-86k", manufacturer: "Sony", name: "Venice 2 · 8.6K 3:2 FF", width: 35.90, height: 24.00),
        SensorFormat(id: "sony-venice-6k-179", manufacturer: "Sony", name: "Venice · 6K 17:9 FF", width: 35.90, height: 18.90),
        SensorFormat(id: "sony-venice-4k-s35", manufacturer: "Sony", name: "Venice · 4K 17:9 S35", width: 24.30, height: 12.80),
        SensorFormat(id: "sony-fx6", manufacturer: "Sony", name: "FX6 / FX3 · FF 16:9", width: 35.60, height: 20.00),
        SensorFormat(id: "red-vraptor-8k-vv", manufacturer: "RED", name: "V-Raptor · 8K VV 17:9", width: 40.96, height: 21.60),
        SensorFormat(id: "red-vraptor-6k-s35", manufacturer: "RED", name: "V-Raptor · 6K S35 17:9", width: 30.72, height: 16.20),
        SensorFormat(id: "red-komodo-6k", manufacturer: "RED", name: "Komodo · 6K S35 17:9", width: 27.03, height: 14.26),
        SensorFormat(id: "generic-ff", manufacturer: "", name: "Full Frame 3:2", width: 36.00, height: 24.00),
        SensorFormat(id: "generic-s35-4perf", manufacturer: "", name: "Super 35 · 4-perf", width: 24.89, height: 18.66),
        SensorFormat(id: "generic-s35-169", manufacturer: "", name: "Super 35 · 16:9", width: 24.89, height: 14.00),
        SensorFormat(id: "generic-s16", manufacturer: "", name: "Super 16", width: 12.52, height: 7.41),
        SensorFormat(id: "generic-m43", manufacturer: "", name: "Micro Four Thirds", width: 17.30, height: 13.00),
    ]

    static let defaultID = "arri-minilf-og"

    static func format(id: String, custom: SensorFormat? = nil) -> SensorFormat {
        if id == customID, let custom { return custom }
        return presets.first { $0.id == id } ?? presets[0]
    }

    static var manufacturers: [String] {
        var seen: [String] = []
        for p in presets where !seen.contains(p.manufacturer) { seen.append(p.manufacturer) }
        return seen
    }
}

enum LensLibrary {
    static let commonFocalLengths: [Double] = [14, 18, 21, 24, 28, 32, 35, 40, 50, 65, 75, 85, 100, 135]
}

/// Delivery aspect ratio used for frame lines inside the sensor area.
enum FrameAspect: String, Codable, CaseIterable, Identifiable {
    case sensor, r239, r200, r185, r178, r143

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sensor: return "Sensor"
        case .r239: return "2.39"
        case .r200: return "2.00"
        case .r185: return "1.85"
        case .r178: return "16:9"
        case .r143: return "1.43"
        }
    }

    var ratio: Double? {
        switch self {
        case .sensor: return nil
        case .r239: return 2.39
        case .r200: return 2.0
        case .r185: return 1.85
        case .r178: return 16.0 / 9.0
        case .r143: return 1.43
        }
    }
}

/// Camera placement + optics. Shared by saved camera positions and shots.
struct CameraRig: Codable, Hashable {
    /// Position in scan plan coordinates (metres).
    var position: PlanPoint = .zero
    /// Lens height above the floor (m).
    var height: Double = 1.5
    /// World bearing the camera faces (0° = plan up / scan -Z, clockwise).
    var pan: Double = 0
    /// Degrees, positive tilts up.
    var tilt: Double = 0
    var focalLength: Double = 32
    var sensorID: String = SensorLibrary.defaultID
    var customSensor: SensorFormat? = nil
    var aspect: FrameAspect = .sensor

    var sensor: SensorFormat { SensorLibrary.format(id: sensorID, custom: customSensor) }

    /// Effective image area after applying the delivery aspect ratio (fit to sensor).
    var imageArea: (width: Double, height: Double) {
        Optics.imageArea(sensor: sensor, aspect: aspect)
    }

    var horizontalFOV: Double { Optics.fieldOfView(size: imageArea.width, focalLength: focalLength) }
    var verticalFOV: Double { Optics.fieldOfView(size: imageArea.height, focalLength: focalLength) }

    var lensSummary: String {
        "\(Optics.formatFocal(focalLength)) · \(sensor.displayName)"
    }
}

struct CameraPosition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var rig: CameraRig
    var scanID: UUID? = nil
    var notes: String = ""
    var createdAt: Date = Date()
}

struct Shot: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var number: Int
    var title: String = ""
    var rig: CameraRig
    /// Subject (actor) mark on the plan.
    var subject: PlanPoint? = nil
    var subjectHeight: Double = 1.75
    var cameraPositionID: UUID? = nil
    var scanID: UUID? = nil
    var notes: String = ""
    var photoID: UUID? = nil
    var createdAt: Date = Date()

    var code: String { String(format: "SHOT %02d", number) }

    var subjectDistance: Double? { subject.map { rig.position.distance(to: $0) } }
}
