#if DEBUG
import Foundation

/// Sample project for Simulator screenshots (CI and local). Debug builds only.
///
/// Launch with `-FSDemo YES` to replace the projects folder with one sample location, and
/// `-FSScreen <name>` to open a screen (see `Screen`). Never shipped in Release builds.
enum DemoContent {
    enum Screen: String, CaseIterable {
        case home, project, location, scan, measurements, plan, lighting, shots, sun
        /// The lighting editor in 3D with a person selected; the plan with the key light's panel.
        case previs, lightpanel
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "FSDemo") }
    static var screen: Screen { UserDefaults.standard.string(forKey: "FSScreen").flatMap(Screen.init) ?? .home }

    static let projectID = UUID(uuidString: "0D3E5F00-0000-4000-8000-000000000001")!
    static let locationID = UUID(uuidString: "0D3E5F00-0000-4000-8000-000000000002")!
    static let scanID = UUID(uuidString: "0D3E5F00-0000-4000-8000-000000000003")!
    static var ref: LocationRef { LocationRef(projectID: projectID, locationID: locationID) }

    /// Writes the sample project to disk. Call before `ProjectStore` loads.
    static func install() {
        let fm = FileManager.default
        try? fm.removeItem(at: StoragePaths.projectsRoot)
        StoragePaths.ensureDirectory(StoragePaths.scanDir(ref, scanID: scanID))
        do {
            try JSONCoding.encoder.encode(project).write(to: StoragePaths.projectFile(projectID))
            try JSONCoding.encoder.encode(plan).write(to: StoragePaths.scanFile(ref, scanID: scanID, .plan))
        } catch {
            print("DemoContent: \(error)")
        }
    }

    static var routes: [Route] {
        switch screen {
        case .home: return []
        case .project: return [.project(projectID)]
        case .location: return [.project(projectID), .location(ref)]
        case .scan: return [.project(projectID), .location(ref), .scanDetail(ref, scanID: scanID)]
        case .measurements: return [.project(projectID), .location(ref), .measurements(ref)]
        case .plan: return [.project(projectID), .location(ref), .plan(ref)]
        case .lighting: return [.project(projectID), .location(ref), .lighting(ref)]
        case .shots: return [.project(projectID), .location(ref), .shots(ref)]
        case .sun: return [.project(projectID), .location(ref), .sun(ref)]
        case .previs: return [.project(projectID), .location(ref), .lighting(ref)]
        case .lightpanel: return [.project(projectID), .location(ref), .plan(ref)]
        }
    }

    // MARK: Sample data — a 6.2 × 4.8 m living room with one door and two windows

    private static let P = PlanPoint.init(x:z:)

    static var plan: FloorPlan {
        let corners = [P(-3.1, -2.4), P(3.1, -2.4), P(3.1, 2.4), P(-3.1, 2.4)]
        var plan = FloorPlan()
        plan.walls = (0..<4).map { i in
            PlanSegment(kind: .wall, a: corners[i], b: corners[(i + 1) % 4], height: 2.74, bottom: 0)
        }
        plan.doors = [PlanSegment(kind: .door, a: P(-3.1, 1.6), b: P(-3.1, 0.7), height: 2.05, bottom: 0)]
        plan.windows = [
            PlanSegment(kind: .window, a: P(-1.9, -2.4), b: P(-0.5, -2.4), height: 1.5, bottom: 0.8),
            PlanSegment(kind: .window, a: P(0.7, -2.4), b: P(2.1, -2.4), height: 1.5, bottom: 0.8),
        ]
        plan.floorPolygons = [corners]
        plan.objects = [
            PlanObject(category: "Sofa", center: P(0.4, 1.8), width: 2.2, depth: 0.9, height: 0.8, rotation: 0),
            PlanObject(category: "Table", center: P(0.4, 0.4), width: 1.2, depth: 0.6, height: 0.45, rotation: 0),
            PlanObject(category: "Storage", center: P(2.8, 0.2), width: 0.4, depth: 1.6, height: 1.9, rotation: 0),
        ]
        plan.bounds = PlanRect(minX: -3.1, minZ: -2.4, maxX: 3.1, maxZ: 2.4)
        return plan
    }

    static var stats: ScanStats {
        var s = ScanStats()
        s.floorArea = 29.8
        s.width = 4.8
        s.length = 6.2
        s.ceilingHeight = 2.74
        s.minCeilingHeight = 2.71
        s.wallCount = 4
        s.doorCount = 1
        s.windowCount = 2
        s.floorCount = 1
        s.objectCount = 3
        s.objectCategories = ["Sofa": 1, "Table": 1, "Storage": 1]
        s.doors = [OpeningSize(width: 0.9, height: 2.05, sillHeight: 0)]
        s.windows = [OpeningSize(width: 1.4, height: 1.5, sillHeight: 0.8), OpeningSize(width: 1.4, height: 1.5, sillHeight: 0.8)]
        s.completeness = 0.86
        return s
    }

    static var project: Project {
        var location = Location(name: "Hackney Flat — Living Room")
        location.id = locationID
        location.address = "Sample location"
        location.coordinate = GeoCoordinate(latitude: 51.5450, longitude: -0.0553, altitude: nil)
        location.timeZoneIdentifier = "Europe/London"
        location.tags = [.interior, .day, .house, .naturalLight]
        location.lightingNotes = "Two south-facing windows. Direct sun on the sofa wall mid-afternoon."
        location.quickNotes = [LocationNote(text: "Power outlets on this wall", category: .power),
                               LocationNote(text: "Narrow access — no dolly through door", category: .access)]
        location.scans = [ScanRecord(id: scanID, name: "Living room", kind: .room, segmentCount: 1, stats: stats,
                                     northOffset: 172, measuredNorthOffset: 172, deviceModel: "iPhone16,1")]
        location.primaryScanID = scanID
        location.measurements = [
            DistanceMeasurement(kind: .roomDimension, label: "Room length", value: 6.2, source: .scanAuto, scanID: scanID),
            DistanceMeasurement(kind: .ceilingHeight, label: "Ceiling height", value: 2.74, vertical: 2.74,
                                source: .scanAuto, provenanceOverride: .estimated, scanID: scanID),
            DistanceMeasurement(kind: .cameraToSubject, label: "Wide to sofa", value: 3.42, vertical: 0.1, horizontal: 3.41, source: .ar),
            DistanceMeasurement(kind: .door, label: "Hall door clear width", value: 0.86, source: .manual, notes: "Measured with tape, frame removed"),
        ]
        var wide = CameraRig()
        wide.position = P(-2.2, -1.6); wide.pan = 135; wide.focalLength = 24
        var single = CameraRig()
        single.position = P(1.6, -1.2); single.pan = 200; single.focalLength = 50; single.height = 1.35
        location.cameraPositions = [CameraPosition(name: "A · Window corner", rig: wide, scanID: scanID)]
        location.shots = [
            Shot(number: 1, title: "Wide, family on sofa", rig: wide, subject: P(0.4, 1.8), scanID: scanID),
            Shot(number: 2, title: "Single on Maya", rig: single, subject: P(0.0, 1.8), scanID: scanID),
        ]
        let sofa = P(0.4, 1.8)
        func aimed(_ name: String, _ kind: LightKind, _ at: PlanPoint, to target: PlanPoint) -> LightFixture {
            LightFixture(name: name, kind: kind, position: at, pan: PlanGeometry.bearing(from: at, to: target), scanID: scanID)
        }
        // Fixture types from the library, so readings and draw come from the photometric model.
        var key = aimed("Key", .softbox, P(-1.2, 0.2), to: sofa)
        key.apply(profile: FixtureLibrary.profile(id: "cob-600-d")!)
        key.modifierID = "softbox-90-grid"; key.role = .key; key.height = 2.1; key.tilt = -25; key.dimmer = 0.5
        var fill = aimed("Fill", .ledPanel, P(2.2, -0.6), to: sofa)
        fill.apply(profile: FixtureLibrary.profile(id: "panel-1x1-bi")!)
        fill.role = .fill; fill.colorTemperature = 4300; fill.dimmer = 0.3; fill.height = 1.8; fill.tilt = -15
        var back = aimed("Back", .fresnel, P(1.9, 2.15), to: P(0.0, 1.8))
        back.apply(profile: FixtureLibrary.profile(id: "fresnel-led-200-bi")!)
        back.role = .back; back.height = 2.4; back.tilt = -35; back.beamAngle = 25; back.dimmer = 0.7
        back.barnDoors = BarnDoors(top: 90, bottom: 90, left: 9, right: 90)
        var bounce = aimed("Bounce", .bounce, P(1.7, 1.0), to: sofa)
        bounce.width = 1.2
        var neg = aimed("Neg", .negative, P(-1.4, 2.0), to: sofa)
        neg.width = 1.2
        var lamp = aimed("Lamp", .practical, P(2.6, 1.9), to: sofa)
        lamp.apply(profile: FixtureLibrary.profile(id: "bulb-tungsten-100")!)
        lamp.role = .practical; lamp.height = 1.4
        location.lightFixtures = [key, fill, back, bounce, neg, lamp]
        var maya = PrevisCharacter(name: "Maya", type: .woman, position: P(0.0, 1.8), facing: 330, scanID: scanID)
        maya.posture = .sitting; maya.skinTone = .tone4
        var leo = PrevisCharacter(name: "Leo", type: .boy, position: P(0.9, 1.8), facing: 340, scanID: scanID)
        leo.skinTone = .tone2; leo.build = 0.4
        location.previsCharacters = [maya, leo]
        var meter = LightMeter(name: "Table", position: P(0.4, 0.4), height: 0.5, scanID: scanID)
        meter.facing = .up
        location.lightMeters = [meter]
        var exposure = ExposureSettings()
        exposure.iso = 800; exposure.tStop = 2.8
        location.exposureSettings = exposure
        var display = SceneDisplay()
        display.showLuxMap = true
        location.displaySettings = display
        var project = Project(name: "Sample Commercial")
        project.id = projectID
        project.client = "Demo"
        project.locations = [location]
        return project
    }
}
#endif
