import AppKit
import SwiftUI

@main
struct SpaceRouterApp: App {

    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    @StateObject private var store: Store
    @StateObject private var screens: ScreenService
    @StateObject private var router: Router
    @StateObject private var permission = AccessibilityPermission()
    @StateObject private var ui = UIState()

    init() {
        // Router yaratılmadan önce: ikinci kopya hiç tarama yapmadan çıkar.
        SingleInstance.exitIfAlreadyRunning()

        let model = AppModel.shared
        _store = StateObject(wrappedValue: model.store)
        _screens = StateObject(wrappedValue: model.screens)
        _router = StateObject(wrappedValue: model.router)
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

/// Uygulamanın çekirdek nesneleri: Store, ekranlar ve Router. Bir kez
/// yaratılır; hem SwiftUI `App` (StateObject olarak sahiplenir) hem de
/// `AppDelegate` (URL komutları) aynı örnekleri kullanır. Tek pencereli
/// menü çubuğu uygulamasında ikinci bir sahne ya da örnek olmadığı için
/// paylaşılan tekil, App'in delegate'e elden vermesinden daha sade ve
/// StateObject anlamını bozmaz (App.init içinde yalnızca sarılır).
@MainActor
final class AppModel {

    static let shared = AppModel()

    let store: Store
    let screens: ScreenService
    let router: Router

    private init() {
        store = Store()
        screens = ScreenService()
        router = Router(store: store, screens: screens)
    }
}

/// `spacerouter://` URL'lerini alır. LSUIElement menü çubuğu uygulamasında
/// SwiftUI `.onOpenURL` güvenilir değil (sahne pencere değil); AppKit
/// delegate'i Launch Services'ten gelen URL'leri her durumda alır,
/// uygulama URL ile soğuk başlatılsa bile.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ application: NSApplication, open urls: [URL]) {
        let model = AppModel.shared
        URLCommands.handle(urls, store: model.store, router: model.router)
    }
}

/// Tek kopya koruması. İki Space Router aynı anda çalışırsa iki Router
/// aynı pencereleri iki ayrı düzen belleğiyle taşımaya çalışır: pencere
/// ileri geri gider, rules.json'u ikisi de yazar. Bu yüzden aynı bundle
/// kimliğiyle çalışan başka bir kopya varsa yenisi hemen çıkar; eskisi
/// öne getirilmez (menü çubuğu uygulamasının öne gelecek penceresi yok).
/// `swift run` ile paket dışında bundle kimliği olmadığı için atlanır.
enum SingleInstance {

    static func exitIfAlreadyRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        // NSApp henüz yok (App.init içindeyiz); doğrudan çık.
        exit(0)
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
