#if DEBUG
import Foundation

/// Sample project for Simulator screenshots (CI and local). Debug builds only; the data itself is
/// `SampleProject`, which Release builds offer as "Try the sample room".
///
/// Launch with `-FSDemo YES` to replace the projects folder with one sample location, and
/// `-FSScreen <name>` to open a screen (see `Screen`). Never shipped in Release builds.
enum DemoContent {
    enum Screen: String, CaseIterable {
        case home, project, location, scan, measurements, plan, lighting, shots, sun
        /// The lighting editor in 3D with a person selected; the plan with the key light's panel.
        case previs, lightpanel
        /// Home with "From a listing" open on a sample studio listing.
        case listing
        /// The lighting editor turned sideways (full-screen 3D), and with the key light selected.
        case landscape, landscapepanel
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
        case .home, .listing: return []
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
        case .landscape, .landscapepanel: return [.project(projectID), .location(ref), .lighting(ref)]
        }
    }

    static var plan: FloorPlan { SampleProject.plan }
    static var project: Project { SampleProject.project(projectID: projectID, locationID: locationID, scanID: scanID) }
}
#endif
