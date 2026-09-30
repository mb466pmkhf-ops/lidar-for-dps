import Foundation

/// Named `DistanceMeasurement` to avoid clashing with Foundation's `Measurement<Unit>`.
struct DistanceMeasurement: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: MeasurementKind
    var label: String
    /// Straight-line distance in metres.
    var value: Double
    /// Vertical component (m), where known.
    var vertical: Double? = nil
    /// Horizontal component (m), where known.
    var horizontal: Double? = nil
    var source: MeasurementSource
    /// Endpoints in scan plan coordinates when measured on the top-down plan.
    var planA: PlanPoint? = nil
    var planB: PlanPoint? = nil
    /// Scan the plan endpoints belong to.
    var scanID: UUID? = nil
    var notes: String = ""
    var createdAt: Date = Date()
}

enum MeasurementSource: String, Codable {
    case ar, plan, scanAuto, manual

    var label: String {
        switch self {
        case .ar: return "AR"
        case .plan: return "Plan"
        case .scanAuto: return "Scan"
        case .manual: return "Manual"
        }
    }
}

enum MeasurementKind: String, Codable, CaseIterable, Identifiable {
    case roomDimension, wallToWall, ceilingHeight, door, window
    case cameraToSubject, cameraToBackground, objectToObject, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .roomDimension: return "Room dimension"
        case .wallToWall: return "Wall to wall"
        case .ceilingHeight: return "Ceiling height"
        case .door: return "Door"
        case .window: return "Window"
        case .cameraToSubject: return "Camera → subject"
        case .cameraToBackground: return "Camera → background"
        case .objectToObject: return "Object to object"
        case .custom: return "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .roomDimension: return "square.dashed"
        case .wallToWall: return "arrow.left.and.right"
        case .ceilingHeight: return "arrow.up.and.down"
        case .door: return "door.left.hand.closed"
        case .window: return "window.vertical.closed"
        case .cameraToSubject: return "person.crop.rectangle"
        case .cameraToBackground: return "photo"
        case .objectToObject: return "cube"
        case .custom: return "ruler"
        }
    }
}
