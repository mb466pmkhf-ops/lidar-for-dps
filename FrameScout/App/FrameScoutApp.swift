import SwiftUI

@main
struct FrameScoutApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.configureUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
        }
    }
}
