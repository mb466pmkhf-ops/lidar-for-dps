import CoreText
import SwiftUI

@main
struct FrameScoutApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Theme.nightKey) private var night = false

    init() {
        Self.registerBundledFonts()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: ReadingExtra.key) == nil,
           let kept = ReadingExtra.migrated(from: defaults.string(forKey: ReadingExtra.legacyKey)) {
            defaults.set(kept.rawValue, forKey: ReadingExtra.key)
        }
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
                .preferredColorScheme(night ? .dark : .light)
                .tint(Theme.accent)
                .font(.fsBody)
                // List section headers in sentence case, as written (Docs/LOOK.md: no ALL-CAPS labels).
                .textCase(nil)
                .task { CloudSync.shared.attach(store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flush() } else { CloudSync.shared.appBecameActive() }
        }
    }
}
