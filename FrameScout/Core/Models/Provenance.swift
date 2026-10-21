import Foundation

/// Where a number came from. Shown next to every figure so a crew never mistakes a guess for a
/// measurement: a sensor reading, a value the app derived with a heuristic, or something typed in.
enum Provenance: String, Codable, CaseIterable, Identifiable {
    /// Read directly from LiDAR/scan geometry (RoomPlan walls and openings, mesh surfaces, AR tape).
    case measured
    /// Derived by a heuristic or a less reliable sensor: bounding boxes, ceiling from wall heights,
    /// compass north, plane-based AR on devices without LiDAR, completeness.
    case estimated
    /// Typed in or corrected by a person.
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .measured: return "Measured"
        case .estimated: return "Estimated"
        case .manual: return "Manual"
        }
    }

    /// Plain-text marker for exports and the PDF, where badges can't be drawn.
    var marker: String {
        switch self {
        case .measured: return ""
        case .estimated: return "≈"
        case .manual: return "✎"
        }
    }

    var symbol: String {
        switch self {
        case .measured: return "ruler"
        case .estimated: return "plusminus"
        case .manual: return "pencil"
        }
    }

    var explanation: String {
        switch self {
        case .measured: return "Read from the LiDAR scan or AR tape."
        case .estimated: return "Derived by the app or from a less precise sensor. Check on set before relying on it."
        case .manual: return "Entered or corrected by hand."
        }
    }
}

extension MeasurementSource {
    /// Default provenance for a source; individual measurements can override it.
    var provenance: Provenance {
        switch self {
        case .ar, .plan, .scanAuto: return .measured
        case .manual: return .manual
        }
    }
}

extension DistanceMeasurement {
    var provenance: Provenance { provenanceOverride ?? source.provenance }
}

/// The headline scan figures that carry a provenance.
enum ScanFigure {
    case roomSize, floorArea, ceilingHeight, openings, completeness
}

extension ScanStats {
    func provenance(of figure: ScanFigure, kind: ScanKind) -> Provenance {
        switch figure {
        case .roomSize:
            // RoomPlan: extents of detected walls. Mesh: bounding box of everything seen, clutter included.
            return kind == .room ? .measured : .estimated
        case .floorArea:
            return floorAreaIsEstimate ? .estimated : .measured
        case .ceilingHeight:
            // RoomPlan doesn't detect ceilings, so it's the tallest wall; mesh scans classify ceiling triangles.
            return kind == .room ? .estimated : .measured
        case .openings:
            return .measured
        case .completeness:
            return .estimated
        }
    }

    /// Prefixes a formatted figure with its plain-text marker (≈ / ✎) where badges can't be drawn.
    func marked(_ value: String, _ figure: ScanFigure, kind: ScanKind) -> String {
        let marker = provenance(of: figure, kind: kind).marker
        return marker.isEmpty || value == "—" ? value : "\(marker) \(value)"
    }
}

extension ScanRecord {
    /// Compass north is an estimate (indoor error 10–20°); a value the user calibrated is manual.
    var northProvenance: Provenance? {
        guard let north = northOffset else { return nil }
        guard let measured = measuredNorthOffset else { return .manual }
        return abs(north - measured) <= 0.5 ? .estimated : .manual
    }
}
