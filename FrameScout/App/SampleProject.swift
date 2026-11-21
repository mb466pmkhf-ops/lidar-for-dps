import Foundation

/// A lit sample room to try the app on: a 6.2 × 4.8 m living room with one door and two windows,
/// six lights, two people on the sofa and two shots. Release builds offer it on Home ("Open the
/// sample room") so someone without a LiDAR phone, or App Review, can see the planner working;
/// Debug builds also use it for Simulator screenshots (`DemoContent`). Its name says "sample" and
/// its address says "Sample location", so it is never mistaken for a real scan.
enum SampleProject {
    static let name = "Family on the sofa (sample)"

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

    /// The sample as a project. IDs are passed in: screenshots use fixed ones, the app new ones.
    static func project(projectID: UUID = UUID(), locationID: UUID = UUID(), scanID: UUID = UUID()) -> Project {
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
        // Fixture types from the library, so readings and draw come from the photometric model. Lit for
        // both shots with nothing in frame (persona audit 2026-11-21): a big soft key from the window side,
        // fill from beside the single's camera, a bounce behind the wide camera, the lamp as a practical.
        var key = aimed("Key", .softbox, P(-1.4, -2.05), to: P(0.0, 1.8))
        key.apply(profile: FixtureLibrary.profile(id: "cob-1200-d")!)
        key.modifierID = "softbox-150"; key.role = .key; key.height = 2.3; key.tilt = -15; key.dimmer = 0.45
        var fill = aimed("Fill", .ledPanel, P(2.4, -1.8), to: sofa)
        fill.apply(profile: FixtureLibrary.profile(id: "panel-1x1-bi")!)
        fill.role = .fill; fill.colorTemperature = 4300; fill.dimmer = 0.3; fill.height = 1.6; fill.tilt = -10
        var bounce = aimed("Bounce", .bounce, P(-2.65, -0.3), to: sofa)
        bounce.width = 1.2
        var lamp = aimed("Lamp", .practical, P(2.6, 1.9), to: sofa)
        lamp.apply(profile: FixtureLibrary.profile(id: "bulb-tungsten-100")!)
        lamp.role = .practical; lamp.height = 1.4
        location.lightFixtures = [key, fill, bounce, lamp]
        var maya = PrevisCharacter(name: "Maya", type: .woman, position: P(0.0, 1.8), facing: 330, scanID: scanID)
        maya.posture = .sitting; maya.skinTone = .tone4
        var leo = PrevisCharacter(name: "Leo", type: .boy, position: P(0.9, 1.8), facing: 340, scanID: scanID)
        leo.posture = .sitting; leo.skinTone = .tone2; leo.build = 0.4
        // Sat on the sofa at its cushion height (Placement).
        location.previsCharacters = Placement.settle([maya, leo], plan: plan, scanID: scanID, all: true) ?? [maya, leo]
        var meter = LightMeter(name: "Table", position: P(0.4, 0.4), height: 0.5, scanID: scanID)
        meter.facing = .up
        location.lightMeters = [meter]
        var exposure = ExposureSettings()
        exposure.iso = 800; exposure.tStop = 5.6
        location.exposureSettings = exposure
        location.displaySettings = SceneDisplay()
        var project = Project(name: Self.name)
        project.id = projectID
        project.client = "Sample job"
        project.locations = [location]
        return project
    }
}
