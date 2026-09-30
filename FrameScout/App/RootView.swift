import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .fullScreenCover(item: $router.capture) { flow in
            CaptureFlowView(flow: flow)
                .environmentObject(store)
                .environmentObject(router)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .project(let id):
            ProjectDetailView(projectID: id)
        case .location(let ref):
            LocationDetailView(ref: ref)
        case .scanDetail(let ref, let scanID):
            ScanDetailView(ref: ref, scanID: scanID)
        case .plan(let ref):
            PlanEditorView(ref: ref)
        case .shots(let ref):
            ShotListView(ref: ref)
        case .sun(let ref):
            SunLightView(ref: ref)
        case .measurements(let ref):
            MeasurementListView(ref: ref)
        case .photos(let ref):
            PhotoGalleryView(ref: ref)
        case .notes(let ref):
            LocationNotesView(ref: ref)
        case .compare:
            CompareView()
        case .export(let projectID, let location):
            ExportView(projectID: projectID, locationRef: location)
        }
    }
}

struct CaptureFlowView: View {
    let flow: CaptureFlow

    var body: some View {
        switch flow {
        case .scan(let target):
            ScanFlowView(target: target)
        case .measure(let target):
            ARMeasureView(target: target)
        case .viewfinder(let target):
            ViewfinderView(target: target)
        case .virtualCamera(let ref, let cameraID):
            VirtualCameraView(ref: ref, initialCameraID: cameraID)
        }
    }
}
