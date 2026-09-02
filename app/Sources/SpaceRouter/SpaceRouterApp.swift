import SwiftUI

@main
struct SpaceRouterApp: App {

    @StateObject private var store: Store
    @StateObject private var screens: ScreenService
    @StateObject private var router: Router
    @StateObject private var permission = AccessibilityPermission()
    @StateObject private var ui = UIState()

    init() {
        let store = Store()
        let screens = ScreenService()
        _store = StateObject(wrappedValue: store)
        _screens = StateObject(wrappedValue: screens)
        _router = StateObject(wrappedValue: Router(store: store, screens: screens))
    }

    var body: some Scene {
        MenuBarExtra("Space Router", systemImage: symbol) {
            RootView()
                .environmentObject(store)
                .environmentObject(screens)
                .environmentObject(router)
                .environmentObject(permission)
                .environmentObject(ui)
        }
        .menuBarExtraStyle(.window)
    }

    private var symbol: String {
        if !store.document.enabled { return "pause.rectangle" }
        return screens.isDocked ? "rectangle.3.group" : "rectangle.on.rectangle"
    }
}
