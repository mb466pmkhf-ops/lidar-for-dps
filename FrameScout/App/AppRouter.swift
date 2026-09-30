import SwiftUI

enum Route: Hashable {
    case project(UUID)
    case location(LocationRef)
    case scanDetail(LocationRef, scanID: UUID)
    case plan(LocationRef)
    case shots(LocationRef)
    case sun(LocationRef)
    case measurements(LocationRef)
    case photos(LocationRef)
    case notes(LocationRef)
    case compare
    case export(projectID: UUID?, location: LocationRef?)
}

/// Where a capture flow should save its results. `nil` fields mean "ask / create".
struct CaptureTarget: Hashable {
    var projectID: UUID?
    var locationID: UUID?

    var locationRef: LocationRef? {
        guard let projectID, let locationID else { return nil }
        return LocationRef(projectID: projectID, locationID: locationID)
    }

    static let quick = CaptureTarget(projectID: nil, locationID: nil)

    init(projectID: UUID?, locationID: UUID?) {
        self.projectID = projectID
        self.locationID = locationID
    }

    init(_ ref: LocationRef) {
        projectID = ref.projectID
        locationID = ref.locationID
    }
}

/// Full-screen capture experiences (camera-first UIs).
enum CaptureFlow: Identifiable, Hashable {
    case scan(CaptureTarget)
    case measure(CaptureTarget)
    case viewfinder(CaptureTarget)
    case virtualCamera(LocationRef, cameraID: UUID?)

    var id: String {
        switch self {
        case .scan(let t): return "scan-\(t.hashValue)"
        case .measure(let t): return "measure-\(t.hashValue)"
        case .viewfinder(let t): return "viewfinder-\(t.hashValue)"
        case .virtualCamera(let r, let c): return "vcam-\(r.hashValue)-\(c?.uuidString ?? "")"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()
    @Published var capture: CaptureFlow?

    func open(_ route: Route) { path.append(route) }
    func popToRoot() { path = NavigationPath() }
    func start(_ flow: CaptureFlow) { capture = flow }
}
