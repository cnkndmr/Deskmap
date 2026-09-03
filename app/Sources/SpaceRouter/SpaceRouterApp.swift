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
        MenuBarExtra {
            RootView()
                .environmentObject(store)
                .environmentObject(screens)
                .environmentObject(router)
                .environmentObject(permission)
                .environmentObject(ui)
        } label: {
            MenuBarLabel(paused: !store.document.enabled)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menü çubuğu simgesi: paketteki `MenuBarIcon.png` (şablon, @1x/@2x) —
/// paket dışında (`swift run`) ya da dosya yoksa SF Symbol'a düşer.
private struct MenuBarLabel: View {
    let paused: Bool

    var body: some View {
        if paused {
            Image(systemName: "pause.rectangle")
        } else if let icon = Self.icon {
            Image(nsImage: icon)
        } else {
            Image(systemName: "rectangle.on.rectangle")
        }
    }

    private static let icon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 22, height: 16)
        return image
    }()
}
