import CoreText
import SwiftUI

@main
struct FrameScoutApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.registerBundledFonts()
        #if DEBUG
        if DemoContent.isEnabled { DemoContent.install() }
        #endif
        Theme.configureUIKitAppearance()
    }

    /// Registers the bundled Poppins faces (SIL OFL) wherever the build put them in the bundle.
    private static func registerBundledFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .font(.fsBody)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() }
        }
    }
}
