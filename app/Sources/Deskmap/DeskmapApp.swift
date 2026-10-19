import AppKit
import Combine
import SwiftUI

/// Gerçek giriş noktası. `--shots <dizin>` varsa (bkz. `Shots.swift`) normal
/// uygulama hiç başlamaz: `AppModel`, `SingleInstance` ve dolayısıyla
/// `Store`/`ScreenService`/`Router`'ın disk/tarama yapan üretim yolu
/// çalışmaz. Yoksa `DeskmapApp.main()` (SwiftUI'nin `App` için ürettiği
/// varsayılan giriş) üretim yolunu değişmeden çalıştırır.
@main
enum AppEntry {
    static func main() {
        if let options = Shots.parseOptions(CommandLine.arguments) {
            MainActor.assumeIsolated { Shots.run(options) }
        }
        DeskmapApp.main()
    }
}

struct DeskmapApp: App {

    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    @StateObject private var store: Store
    @StateObject private var screens: ScreenService
    @StateObject private var router: Router
    @StateObject private var permission = AccessibilityPermission()
    @StateObject private var indicatorTick = IndicatorTick()
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
            // Turuncu uzun sürünce kırmızıya dönsün diye seyrek yeniden çizim
            // (tarama yok; son anlık görüntüden hesaplanır). TimelineView
            // menü çubuğu etiketinde sonsuz güncelleme döngüsüne giriyor.
            let _ = indicatorTick.count
                MenuBarLabel(
                    health: AppHealth.state(
                        enabled: store.document.enabled,
                        trusted: permission.isTrusted,
                        requiredSettingsOK: MacSettings.allRequiredOK(MacSettings.checks()),
                        movesDegraded: router.moveHealth.state == .degraded),
                    // Haritanın "Sahipsiz pencereler" kutusuyla aynı sayım.
                    unassigned: ScreenMapView.unownedWindows(
                        router.windows, rules: store.document.rules,
                        sessionPins: router.sessionPins).count,
                    indicator: StatusIndicator.current(
                        store: store, router: router, screens: screens,
                        trusted: permission.isTrusted))
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
    let status: StatusFile
    /// Otomatik yedek (`Backups/`); Shots modunda hiç yaratılmaz.
    let backups: BackupService?
    private var roleSync: [AnyCancellable] = []

    private init() {
        store = Store()
        screens = ScreenService(roles: store.document.displayRoles)
        router = Router(store: store, screens: screens)
        status = StatusFile(url: Store.directoryURL.appendingPathComponent("status.json"),
                            store: store, router: router, screens: screens)
        backups = BackupService(archive: BackupArchive(sourceDirectory: Store.directoryURL))
        BackupService.current = backups
        roleSync = Self.syncDisplayRoles(store: store, screens: screens)
    }

    /// Harici ekran rolleri iki yönlü: belgedeki kayıt (harita seçimi, yedek
    /// geri yükleme, rules.json yeniden okuma) ScreenService'e gider; yatışmış
    /// her ekran listesi belgeye öğretilir. Döngü yok: öğrenilen kayıt aynı
    /// atamayı verir, ScreenService değişmeyen sonucu yayınlamaz.
    static func syncDisplayRoles(store: Store, screens: ScreenService) -> [AnyCancellable] {
        [
            store.$document.map(\.displayRoles).removeDuplicates()
                .sink { [weak screens] in screens?.roles = $0 },
            // Yalnız yatışmış liste öğretilir (açılış ve her `settled`): ekran
            // değişiminin ilk ölçümü yarım düzenlenmiş olabilir.
            // Belge willSet'te yayınlar: harita seçimi `roles`'ü değiştirip
            // `settled` gönderdiğinde belgede henüz eski kayıt durur. O an
            // öğrenilirse eski kayıt seçimin üstüne yazılır; öğrenme bir
            // sonraki tura kalır.
            screens.settled.prepend(())
                .sink { [weak store, weak screens] in
                    guard let store, let screens, !screens.isSettling else { return }
                    guard store.document.displayRoles == screens.roles else {
                        DispatchQueue.main.async {
                            guard !screens.isSettling else { return }
                            store.learnDisplayRoles(screens.externalAssignment)
                        }
                        return
                    }
                    store.learnDisplayRoles(screens.externalAssignment)
                },
        ]
    }
}

/// `deskmap://` URL'lerini alır. LSUIElement menü çubuğu uygulamasında
/// SwiftUI `.onOpenURL` güvenilir değil (sahne pencere değil); AppKit
/// delegate'i Launch Services'ten gelen URL'leri her durumda alır,
/// uygulama URL ile soğuk başlatılsa bile.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItemMenu.shared.install()
        WelcomeWindow.shared.showIfNeeded()
        AppModel.shared.backups?.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let model = AppModel.shared
        URLCommands.handle(urls, store: model.store, router: model.router, status: model.status)
    }
}

/// Tek kopya koruması. İki Deskmap aynı anda çalışırsa iki Router
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
/// Üç durum: hazır (uygulama simgesi), duraklatıldı, ilgi gerekiyor.
/// Hazırken hiçbir kurulumda pini olmayan pencere varsa simgenin sağ
/// üstünde sayı rozeti çıkar.
struct MenuBarLabel: View {
    let health: AppHealth
    var unassigned = 0
    var indicator: StatusIndicator?

    var body: some View {
        icon.accessibilityLabel(text).help(text)
    }

    private var text: String {
        var text = health.label
        if health == .ready, unassigned > 0 {
            text += " · " + (unassigned == 1
                ? L("1 unassigned window") : L("%ld unassigned windows", unassigned))
        }
        if health == .ready, let indicator { text += " · " + indicator.reason }
        return text
    }

    @ViewBuilder private var icon: some View {
        switch health {
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle")
        case .paused:
            Image(systemName: "pause.rectangle")
        case .ready:
            if let icon = Self.icon {
                let base = unassigned > 0 ? Self.badged(icon, count: unassigned) : icon
                Image(nsImage: Self.described(
                    indicator.map { Self.dotted(base, level: $0.level) } ?? base, as: text))
            } else {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }

    /// Menü çubuğu simgesi resimden çizilir; SwiftUI erişilebilirlik ve
    /// ipucu değiştiricileri ona ulaşmaz. VoiceOver sayıyı resmin
    /// açıklamasından okur (önbellekteki resim değişmesin diye kopya).
    @MainActor private static var describedCache: [String: NSImage] = [:]

    @MainActor static func described(_ image: NSImage, as text: String) -> NSImage {
        let key = "\(ObjectIdentifier(image).hashValue)|\(text)"
        if let cached = describedCache[key] { return cached }
        let copy = image.copy() as? NSImage ?? image
        copy.accessibilityDescription = text
        // Durum/sayı birleşimleri azdır; yine de sınırsız büyümesin.
        if describedCache.count > 64 { describedCache.removeAll() }
        describedCache[key] = copy
        return copy
    }

    /// Rozet metni (saf): 1…9, fazlası "9+".
    static func badgeText(_ count: Int) -> String {
        count > 9 ? "9+" : "\(max(count, 0))"
    }

    /// Sayı başına bir kez çizilir.
    @MainActor private static var badgeCache: [String: NSImage] = [:]

    /// Simgenin sağ üstüne oyulmuş rozet: rozetin çevresi boşaltılır, rozet
    /// dolu çizilir, rakamlar rozetten oyulur. Şablon resim olarak kalır;
    /// açık/koyu menü çubuğunda sistem simgeleri gibi renklenir.
    @MainActor static func badged(_ base: NSImage, count: Int) -> NSImage {
        let text = badgeText(count)
        if let cached = badgeCache[text] { return cached }
        let font = NSFont.systemFont(ofSize: 8, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let height: CGFloat = 10
        let width = max(height, ceil(textSize.width) + 4)
        let iconSize = base.size
        let size = NSSize(width: iconSize.width + width / 2, height: iconSize.height)
        let badge = NSRect(x: size.width - width, y: size.height - height, width: width, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: NSRect(origin: .zero, size: iconSize))
            // Rozetin çevresinde ince boşluk (simgeden ayrılsın).
            context.setBlendMode(.clear)
            context.addPath(CGPath(roundedRect: badge.insetBy(dx: -1.5, dy: -1.5),
                                   cornerWidth: height / 2 + 1.5, cornerHeight: height / 2 + 1.5,
                                   transform: nil))
            context.fillPath()
            context.setBlendMode(.normal)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(CGPath(roundedRect: badge, cornerWidth: height / 2,
                                   cornerHeight: height / 2, transform: nil))
            context.fillPath()
            // Rakamlar rozetten oyulur.
            context.setBlendMode(.destinationOut)
            (text as NSString).draw(
                at: NSPoint(x: badge.midX - textSize.width / 2,
                            y: badge.midY - textSize.height / 2),
                withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        badgeCache[text] = image
        return image
    }

    @MainActor private static var dotCache: [String: NSImage] = [:]

    /// Simgenin sol alt köşesine renkli durum noktası. Renkli olduğu için
    /// resim şablon değil: simge çizim anında menü çubuğunun görünümüne göre
    /// etiket rengiyle boyanır (açık/koyu).
    @MainActor static func dotted(_ base: NSImage, level: StatusIndicator.Level) -> NSImage {
        let key = "\(ObjectIdentifier(base).hashValue)|\(level)"
        if let cached = dotCache[key] { return cached }
        let color: NSColor = switch level {
        case .green: .systemGreen
        case .orange: .systemOrange
        case .red: .systemRed
        }
        let size = base.size
        let diameter: CGFloat = 7
        let dot = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: rect)
            // Şablonu etiket rengine boya.
            context.setBlendMode(.sourceIn)
            context.setFillColor(NSColor.labelColor.cgColor)
            context.fill(rect)
            // Noktanın çevresi boşaltılır, nokta renkli çizilir.
            context.setBlendMode(.clear)
            context.fillEllipse(in: dot.insetBy(dx: -1.5, dy: -1.5))
            context.setBlendMode(.normal)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: dot)
            return true
        }
        image.isTemplate = false
        if dotCache.count > 32 { dotCache.removeAll() }
        dotCache[key] = image
        return image
    }

    private static let icon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 22, height: 16)
        return image
    }()
}

/// Durum noktasını 15 sn'de bir yeniden hesaplatır (takılmış turuncu
/// kırmızıya dönsün); tarama yapmaz.
@MainActor
final class IndicatorTick: ObservableObject {
    @Published private(set) var count = 0
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }
}
