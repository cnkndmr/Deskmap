import AppKit
import Foundation
import SwiftUI

/// `Deskmap --shots <dizin>` modu: gerçek `RootView`'ı uydurma demo
/// veriyle (bkz. `DemoData`) çizip App Store / web sitesi için PNG üretir,
/// sonra çıkar. Tarama yok, AX yok, SkyLight yok, zamanlayıcı yok,
/// tek-kopya kontrolü yok; `Store`/`ScreenService`/`Router`'ın disk/tarama
/// yapan üretim yolu hiç çalıştırılmaz (bkz. o tiplerin `demo` init'leri).
///
/// `AppEntry.main()` normal uygulama başlamadan önce argümanlara bakar;
/// `--shots` varsa `DeskmapApp.main()` (ve dolayısıyla `AppModel`,
/// `SingleInstance`) hiç çağrılmaz.
enum Shots {

    struct Options: Equatable {
        var directory: String
        /// Yalnızca bu adlardaki kareler üretilsin (ör. "01-map"); nil = hepsi.
        var only: Set<String>?
    }

    /// `--shots <dizin>` (zorunlu, yoksa nil döner ve normal uygulama açılır)
    /// ve isteğe bağlı `--only <ad1,ad2>` ayrıştırır.
    static func parseOptions(_ arguments: [String]) -> Options? {
        guard let flagIndex = arguments.firstIndex(of: "--shots"),
              arguments.indices.contains(flagIndex + 1)
        else { return nil }
        let directory = arguments[flagIndex + 1]

        var only: Set<String>?
        if let onlyIndex = arguments.firstIndex(of: "--only"),
           arguments.indices.contains(onlyIndex + 1) {
            let names = arguments[onlyIndex + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            only = Set(names)
        }
        return Options(directory: directory, only: only)
    }

    /// Bu kare `--only` süzgeciyle üretilmeli mi (saf).
    static func shouldCapture(_ name: String, options: Options) -> Bool {
        guard let only = options.only else { return true }
        return only.contains(name)
    }

    // MARK: - Çalıştırma

    /// Pencereyi kurar, her kareyi sırayla üretir ve çıkar (`exit(0)`).
    /// Geri dönmez.
    @MainActor
    static func run(_ options: Options) -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)

        let world = DemoData.make()
        let store = Store(demo: world.document)
        let screens = ScreenService(demo: world.screens)
        let router = Router(store: store, screens: screens, demoWindows: world.windows)
        let permission = AccessibilityPermission(demoTrusted: true)
        let ui = UIState()

        // Kareler 1710 × 1074 pt'lik kullanılabilir alana göre (bu Mac'in
        // dahili ekranı): pencere oranlı boyutunu buna göre alır; boy her karede
        // içeriğe göre yeniden ölçülür (açık panel pencereyi uzatır).
        let room = WindowRoom(height: 1074 - RootView.screenMargin,
                              visible: CGSize(width: 1710, height: 1074))
        let size = NSSize(width: RootView.windowWidth(visibleWidth: room.visible.width),
                          height: RootView.preferredHeight(visibleHeight: room.visible.height))
        let hosting = NSHostingView(rootView:
            ShotsRootView()
                .environment(\.demoRoom, room)
                .environmentObject(store)
                .environmentObject(screens)
                .environmentObject(router)
                .environmentObject(permission)
                .environmentObject(ui))
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = ShotsWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        try? FileManager.default.createDirectory(
            atPath: options.directory, withIntermediateDirectories: true)

        // Pencere yalnızca `orderFrontRegardless` ile önde ama "key" ve
        // uygulama "aktif" değilse AppKit vurgu renkli denetimleri (bu
        // anahtar dahil) pasif pencere görünümüyle grileştirir — offscreen
        // `cacheDisplay`'in asıl sorunu buydu. `activate` + `makeKeyAndOrderFront`
        // gerçek (aktif) rengi yakalar. Menü çubuğu yardımcı süreci (Dock
        // simgesi yok, `SingleInstance`/`AppModel` hiç çalışmadı) olduğu için
        // kısa süre önde/aktif olması zararsız; bakımcının canlı kopyası (ayrı
        // süreç, ayrı pencere) etkilenmez. Kareler bitince pencere kapatılır.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // İlk düzen turu: onAppear / onReceive bir kez çalışsın.
        pump(0.3)

        // Gerçek makinenin SkyLight verisi bizim uydurma ekran UUID'lerimizle
        // hiç eşleşmez; "eksik masaüstü" rozetini sergilemek için ekran
        // başına gerçek masaüstü sayısını burada elle sabitliyoruz.
        let fixedDesktopCounts = ["builtin": 4, "external": 3]

        func capture(_ name: String) {
            guard shouldCapture(name, options: options) else { return }
            ui.desktopCounts = fixedDesktopCounts
            pump(0.15)
            let fitting = hosting.fittingSize
            if fitting.width > 0, fitting.height > 0, fitting != hosting.frame.size {
                hosting.setFrameSize(fitting)
                window.setContentSize(fitting)
                pump(0.15)
            }
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                FileHandle.standardError.write(Data("shots: bitmap oluşturulamadı (\(name))\n".utf8))
                return
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("shots: PNG kodlanamadı (\(name))\n".utf8))
                return
            }
            let url = URL(fileURLWithPath: options.directory).appendingPathComponent("\(name).png")
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                FileHandle.standardError.write(Data("shots: \(name) yazılamadı: \(error)\n".utf8))
            }
        }

        // 01 — ana görünüm: iki ekran, masaüstleri, pinli çipler, canlı pencereler.
        capture("01-map")

        // 02 — yeni pin: pinsiz bir pencere için pin paneli (TokenPicker).
        if let target = world.windows.first(where: { $0.id == DemoData.unpinnedMessagesWindowID }) {
            ui.panel = .pin(PinDraft(
                window: target, target: Router.Placement(screen: "builtin", desktop: 2)))
        }
        capture("02-pin")

        // 03 — düzen seçici: var olan bir pini düzenleme paneli.
        ui.panel = .rule(DemoData.messagesRuleID)
        capture("03-layout")

        // 06 — serbest hareket: pinli pencerenin panelinde kalan süre ve
        // satırında sayaç. (Numara sonradan eklendi; sıra burada çünkü aynı
        // panel açık.)
        let freed = world.windows
            .filter { $0.appName == "Messages" && $0.id != DemoData.unpinnedMessagesWindowID }
            .map(\.id)
        router.allowFreeMove(freed, for: 15 * 60)
        capture("06-free-move")
        router.endFreeMove(freed)

        // 04 — profiller: profil paneli, iki profil görünür.
        ui.panel = .profile
        capture("04-profiles")

        // 05 — macOS ayar kartı + eksik masaüstü rozeti + "Geri al" çubuğu.
        ui.panel = nil
        // Sıra önemli: `setupNoticeDismissed` değişimi de bir `document`
        // mutasyonu olduğundan, `remove` sonrasına konursa az önce oluşan
        // "Geri al" kaydını geçersiz kılar (`UndoBuffer.invalidate`).
        store.document.setupNoticeDismissed = false
        store.remove(DemoData.extraRuleID)
        capture("05-setup")

        window.orderOut(nil)
        exit(0)
    }

    /// SwiftUI'nin durum değişikliğini işleyip yeniden çizmesi için ana
    /// run loop'u kısa süre çalıştırır (offscreen render; gerçek bir olay
    /// döngüsü sürmediği için elle pompalanır).
    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

/// Sade `NSWindow`, `.borderless` maskesiyle varsayılan olarak asla "key"
/// olamaz (`canBecomeKey` false döner); bu yüzden `makeKeyAndOrderFront`
/// sessizce işe yaramaz ve vurgu renkli denetimler (üstteki açma/kapama
/// anahtarı gibi) pasif pencere görünümüyle grileşir. Yalnızca bunu açar;
/// üretim yolunda kullanılmaz.
private final class ShotsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Shots modunda `RootView`'ı saran görünüm. `.regularMaterial` gerçek bir
/// pencere art alanı olmadan (offscreen yakalamada) saydam/boş çizilebilir;
/// yalnızca burada, yalnızca shots modunda opak bir art alan eklenir.
/// Üretim yolunda (`DeskmapApp`) bu sarmalayıcı hiç kullanılmaz,
/// `RootView`'ın kendisi değişmez.
private struct ShotsRootView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RootView()
        }
    }
}
