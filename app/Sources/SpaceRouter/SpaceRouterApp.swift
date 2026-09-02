import SwiftUI

@main
struct SpaceRouterApp: App {

    @StateObject private var store = RuleStore()
    @StateObject private var screenService = ScreenService()
    @StateObject private var accessibility = AccessibilityService()
    @StateObject private var hammerspoon = HammerspoonBridge()
    @StateObject private var inspector = WindowInspector()

    var body: some Scene {
        MenuBarExtra("Space Router", systemImage: menuBarSymbol) {
            RootView()
                .environmentObject(store)
                .environmentObject(screenService)
                .environmentObject(accessibility)
                .environmentObject(hammerspoon)
                .environmentObject(inspector)
                .frame(width: 460, height: 580)
        }
        .menuBarExtraStyle(.window)
    }

    /// Menü çubuğu simgesi dock durumunu de gösterir.
    private var menuBarSymbol: String {
        if !store.document.settings.enabled {
            return "pause.rectangle"
        }
        return screenService.isDocked
            ? "rectangle.3.group"
            : "rectangle.on.rectangle"
    }
}
