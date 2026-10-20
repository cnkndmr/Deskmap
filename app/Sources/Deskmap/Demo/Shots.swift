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

    /// Kareler üretilirken true: arayüz gerçek kurulum yolu gibi kişisel
    /// ayrıntı göstermesin (bkz. `SettingsView.launchAtLoginHelp`).
    @MainActor static var isRunning = false

    struct Options: Equatable {
        var directory: String
        /// Yalnızca bu adlardaki kareler üretilsin (ör. "01-map"); nil = hepsi.
        var only: Set<String>?
        /// `--scenario crowded`: kalabalık demo dünyası ve görsel harita
        /// kareleri (`g…`); nil = mağaza/kılavuz kareleri.
        var scenario: String? = nil
        /// `--visible-height N`: ekranın kullanılabilir yüksekliği (pt);
        /// küçük pencere kareleri için. nil = 1074.
        var visibleHeight: CGFloat? = nil
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
        var scenario: String?
        if let index = arguments.firstIndex(of: "--scenario"), arguments.indices.contains(index + 1) {
            scenario = arguments[index + 1]
        }
        var visibleHeight: CGFloat?
        if let index = arguments.firstIndex(of: "--visible-height"), arguments.indices.contains(index + 1),
           let value = Double(arguments[index + 1]), value >= 400 {
            visibleHeight = value
        }
        return Options(directory: directory, only: only, scenario: scenario, visibleHeight: visibleHeight)
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
        isRunning = true

        let crowded = options.scenario == "crowded"
        let twoMonitors = options.scenario == "two-monitors"
        let heldMonitor = options.scenario == "held-monitor"
        let sequence = options.scenario == "demo"
        let awayMonitor = options.scenario == "away-monitor"
        let world = crowded ? DemoData.crowded() : twoMonitors ? DemoData.twoMonitors()
            : awayMonitor ? DemoData.awayMonitor()
            : sequence ? DemoData.demoSequence() : DemoData.make()
        var document = world.document
        if heldMonitor {
            // Evdeki monitör hatırlanıyor, bağlı olan başka bir ekran: rolü
            // onay bekler (docs/bug-tables.md A′).
            document.displayRoles = DisplayRoles(remembered: ["external": ["HOME-MONITOR"]])
            // Takılı olmayan ev monitörü kendi soluk kartını alır (rolü şu an
            // onay bekleyen ekranda).
            document.displayRoles.monitorNames = ["HOME-MONITOR": "Acme 27Q"]
            document.displayRoles.lastDesktopCount = ["HOME-MONITOR": 2]
        }
        let store = Store(demo: document)
        let screens = ScreenService(demo: world.screens)
        screens.roles = document.displayRoles
        let router = Router(store: store, screens: screens, demoWindows: world.windows)
        let permission = AccessibilityPermission(demoTrusted: true)
        let ui = UIState()
        ui.persistsPreferences = false
        ui.visualMap = true
        let caption = ShotsCaption()

        // Kareler 1710 × 1074 pt'lik kullanılabilir alana göre (bu Mac'in
        // dahili ekranı): pencere oranlı boyutunu buna göre alır; boy her karede
        // içeriğe göre yeniden ölçülür (açık panel pencereyi uzatır).
        // Demo dizisi (GIF): pencere boyu 826 pt; altyazı çubuğuyla birlikte
        // bu Mac'in ekranına (1074 pt) sığar, yoksa AppKit pencereyi kırpar.
        let visible = sequence ? CGSize(width: 1710, height: 1180)
            : CGSize(width: 1710, height: options.visibleHeight ?? 1074)
        let room = WindowRoom(height: visible.height - RootView.screenMargin, visible: visible)
        let size = NSSize(width: RootView.totalWidth(visibleWidth: room.visible.width),
                          height: RootView.preferredHeight(visibleHeight: room.visible.height))
        let hosting = NSHostingView(rootView:
            ShotsRootView()
                .environment(\.demoRoom, room)
                .environmentObject(store)
                .environmentObject(screens)
                .environmentObject(router)
                .environmentObject(permission)
                .environmentObject(ui)
                .environmentObject(caption))
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
        // kısa süre önde/aktif olması zararsız; kullanıcının canlı kopyası (ayrı
        // süreç, ayrı pencere) etkilenmez. Kareler bitince pencere kapatılır.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // İlk düzen turu: onAppear / onReceive bir kez çalışsın.
        pump(0.3)

        // Gerçek makinenin SkyLight verisi bizim uydurma ekran UUID'lerimizle
        // hiç eşleşmez; "eksik masaüstü" rozetini sergilemek için ekran
        // başına gerçek masaüstü sayısını burada elle sabitliyoruz.
        let fixedDesktopCounts = crowded ? DemoData.crowdedDesktopCounts
            : twoMonitors ? ["builtin": 4, "external": 3, "external-2": 2] : ["builtin": 4, "external": 3]

        func capture(_ name: String) {
            guard shouldCapture(name, options: options) else { return }
            // Demo dizisi sayıları adım başına kendisi verir.
            if !sequence { ui.desktopCounts = fixedDesktopCounts }
            pump(0.15)
            // İki ölçüm: ilk boy değişimi altyazı/iç yerleşimi yeniden akıtabilir.
            // Demo dizisinde birkaç pt pay: içerik üstten kırpılmasın
            // (sarmalayıcı üste hizalı, pay alta düşer).
            let slack: CGFloat = sequence ? 8 : 0
            for _ in 0..<2 {
                var fitting = hosting.fittingSize
                guard fitting.width > 0, fitting.height > 0 else { break }
                fitting.height += slack
                guard fitting != hosting.frame.size else { break }
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

        /// Harita dışındaki bir görünümü kendi boyunda, ayrı bir pencerede çizer.
        func captureView<V: View>(_ name: String, _ view: V) {
            guard shouldCapture(name, options: options) else { return }
            let host = NSHostingView(rootView: ZStack {
                Color(nsColor: .windowBackgroundColor)
                view
            })
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let extra = ShotsWindow(contentRect: host.frame, styleMask: [.borderless],
                                    backing: .buffered, defer: false)
            extra.isReleasedWhenClosed = false
            extra.contentView = host
            extra.makeKeyAndOrderFront(nil)
            pump(0.3)
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    let url = URL(fileURLWithPath: options.directory).appendingPathComponent("\(name).png")
                    try? data.write(to: url, options: .atomic)
                }
            }
            extra.orderOut(nil)
        }

        if awayMonitor {
            // m4 — takılı olmayan 2. monitör: altta dar, soluk kart; Mail'in
            // oradaki yeri hayalet çip; Terminal yedekle Ekstra monitörde.
            // Harita soluk kart sırasına kaydırılır (karenin altında kalmasın).
            // Masaüstü sayıları kaydırmadan önce: sonra gelirse içerik uzar,
            // kaydırma eski yerde kalır. İki kez: ilki yerleşimden önce gelebilir.
            ui.desktopCounts = fixedDesktopCounts
            pump(0.3)
            for seq in 1...2 {
                ui.reveal = RevealRequest(window: MapPlaces.awayAnchorID, seq: seq)
                pump(0.4)
            }
            capture("m4-away-monitor")
            ui.visualMap = false
            for seq in 3...4 {
                ui.reveal = RevealRequest(window: MapPlaces.awayAnchorID, seq: seq)
                pump(0.4)
            }
            capture("m4-away-monitor-list")
            ui.visualMap = true
            // m4b — haritanın en altı: son kartın alt kenarı alt çubuğun
            // üstünde kalmalı (alt boşluk).
            for seq in 5...6 {
                ui.reveal = RevealRequest(window: MapPlaces.mapEndAnchorID, seq: seq)
                pump(0.4)
            }
            capture("m4b-map-bottom")
            // m5 — Mail'in pin paneli: sıralı yerler, kullanılan yer vurgulu.
            ui.panel = .rule(DemoData.awayMailRuleID)
            capture("m5-places-panel")
            window.orderOut(nil)
            exit(0)
        }

        if heldMonitor {
            // m3 — hatırlanmayan monitör: kartta "düzen bekliyor", başlıkta
            // menü, "Sıranın sonuna ekle" ve "Yerine geç…" (K6).
            capture("m3-held-monitor")
            // m3b — evdeki monitör takılı değil, rolü onay bekleyen ekranda:
            // yine kendi soluk kartı var (monitör kimliğinden).
            ui.desktopCounts = fixedDesktopCounts
            pump(0.3)
            for seq in 1...2 {
                ui.reveal = RevealRequest(window: MapPlaces.awayAnchorID, seq: seq)
                pump(0.4)
            }
            capture("m3b-held-monitor-away-card")
            window.orderOut(nil)
            exit(0)
        }

        if sequence {
            captureSequence(ui: ui, router: router, store: store, screens: screens,
                            caption: caption, capture: capture)
            window.orderOut(nil)
            exit(0)
        }

        if twoMonitors {
            // m1 — iki harici monitör: kart başlığı menüsü, (sol)/(sağ), Monitör 2.
            capture("m1-two-monitors")
            ui.visualMap = false
            capture("m1-two-monitors-list")
            // m2 — 2. monitör kartı üstte (yalnız çizim sırası): başlıkta
            // monitör menüsü. Menünün açık hâli ve onay penceresi ayrı
            // pencerelerde açıldığı için bu yolla çizilemez.
            let known = store.document.screens
            store.document.screens = known.filter { $0.id == "external-2" }
                + known.filter { $0.id != "external-2" }
            ui.visualMap = true
            capture("m2-monitor-2-card")
            window.orderOut(nil)
            exit(0)
        }

        if crowded {
            captureCrowded(ui: ui, router: router, store: store, world: world, capture: capture)
            window.orderOut(nil)
            exit(0)
        }

        // 01 — ana görünüm: iki ekran, masaüstleri, pinli çipler, canlı pencereler.
        capture("01-map")

        // 01b — liste görünümü (önizlemeler kapalı).
        ui.visualMap = false
        capture("01-map-list")
        ui.visualMap = true

        // 09 — arama: uyanlar turuncu çerçeveli, diğerleri soluk.
        ui.search = "acme"
        capture("09-search")
        ui.search = ""

        // 10 — "Hepsini olduğu yere sabitle": toplu sabitleme çubuğu sağda.
        ui.selection = Set(ScreenMapView.unownedWindows(
            world.windows, rules: store.document.rules, sessionPins: router.sessionPins)
            .filter { $0.placement != nil && $0.fullscreen == nil }.map(\.id))
        capture("10-pin-all")
        ui.selection = []

        // 02 — yeni pin: pinsiz bir pencere için pin paneli (TokenPicker).
        if let target = world.windows.first(where: { $0.id == DemoData.unpinnedMessagesWindowID }) {
            ui.panel = .pin(PinDraft(
                window: target, target: Router.Placement(screen: "builtin", desktop: 2)))
        }
        capture("02-pin")

        // 03 — düzen seçici: var olan bir pini düzenleme paneli.
        ui.panel = .rule(DemoData.messagesRuleID)
        capture("03-layout")

        // 03b — aynı panelin "Gelişmiş" bölümü açık hâli.
        ui.showAdvanced = true
        capture("03-layout-advanced")

        // 13 — uzun, bölünmeyen başlık parçası + Gelişmiş açık: sağ sütun
        // kendi genişliğinde kalmalı (kaydırma çubuğunun altına taşmamalı).
        store.add(DemoData.longTitleRule())
        ui.panel = .rule(DemoData.longTitleRuleID)
        capture("13-long-title")
        ui.panel = .pin(PinDraft(window: DemoData.longTitleWindow(),
                                 target: Router.Placement(screen: "builtin", desktop: 2)))
        capture("13-long-title-pin")
        ui.showAdvanced = false
        capture("13-long-title-pin-basic")
        // Geri alma kaydı bırakmadan (05'in "Geri al" çubuğu bozulmasın).
        store.document.rules.removeAll { $0.id == DemoData.longTitleRuleID }
        ui.panel = .rule(DemoData.messagesRuleID)

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

        // 07 — Ayarlar penceresi (Genel, Düzenler, macOS ayarları ve Profiller
        // sekmeleri) ve 08 —
        // üst çubuktaki "?" açıklama paneli. Ayrı barındırıcıda çizilir;
        // harita penceresi değişmez.
        let settingsState = SettingsState()
        captureView("07-settings", SettingsView(state: settingsState).environmentObject(store))
        settingsState.tab = .layouts
        captureView("07-settings-layouts", SettingsView(state: settingsState).environmentObject(store))
        // Düzenler sekmesinin tamamı (kaydırmadan) ve ızgara taslağı.
        captureView("07-settings-layouts-full",
                    LayoutSettings(title: SettingsTab.layouts.title)
                        .environmentObject(store)
                        .frame(width: 500, height: 1150))
        captureView("07-settings-layouts-editor",
                    LayoutDraftEditor(title: SettingsTab.layouts.title,
                                      draft: .new(in: store.document.layouts), close: {})
                        .environmentObject(store)
                        .frame(width: 500, height: 460))
        settingsState.tab = .macOS
        captureView("07-settings-macos", SettingsView(state: settingsState).environmentObject(store))
        settingsState.tab = .profiles
        captureView("07-settings-profiles", SettingsView(state: settingsState).environmentObject(store))
        captureView("08-legend", LegendView())

        // 11 — "Son hareketler" paneli, uydurma taşımalarla.
        router.recordActions(["Obsidian (Handbook) → " + L("%@ · Desktop %ld", "Studio Display", 3),
                              "Messages (acme-web) → " + L("%@ · Desktop %ld", "Studio Display", 2)],
                             at: Date().addingTimeInterval(-25 * 60))
        router.recordActions(["Safari (Docs) → " + L("%@ · Desktop %ld", "Built-in Display", 2)])
        captureView("11-log", ActivityLogView().environmentObject(store).environmentObject(router))

        // 12 — başlangıç rehberinin üç adımı.
        for step in 1...3 {
            captureView("12-welcome-\(step)",
                        WelcomeView(demoStep: step, demoTrusted: step > 1) {}
                            .environmentObject(store).environmentObject(router)
                            .environmentObject(screens))
        }

        window.orderOut(nil)
        exit(0)
    }

    /// Kalabalık senaryonun kareleri: görsel harita (canlı ve öbür plan),
    /// arama, seçili pencere ve ayrıntı sütunu, geçici sabitleme, toplu
    /// sabitleme, liste görünümü.
    @MainActor
    private static func captureCrowded(ui: UIState, router: Router, store: Store,
                                       world: DemoData.World, capture: (String) -> Void) {
        // Geçici sabitleme (turuncu kutu) ve serbest hareket (turkuaz kesikli).
        // Demo router diske yazmaz, pencere taşımaz.
        router.pinSession(DemoData.crowdedMessagesWindowID,
                          destination: Destination(screen: "builtin", desktop: 1, layout: .full))
        router.allowFreeMove([DemoData.crowdedFreeWindowID], for: 15 * 60)
        pump(0.2)

        capture("g01-grid")
        // Kalabalık laptop masaüstüne kaydırılmış hâli.
        ui.reveal = RevealRequest(window: 105, seq: 1)
        pump(0.5)
        capture("g01b-grid-crowded")
        // Alt kısım: uzun başlık, penceresi kapalı Preview sabitlemeleri, boş masaüstü.
        ui.reveal = RevealRequest(window: DemoData.crowdedCometWindowID, seq: 10)
        pump(0.5)
        capture("g01c-grid-closed-pins")

        ui.search = "orion"
        ui.reveal = RevealRequest(window: 130, seq: 2)
        pump(0.5)
        capture("g02-grid-search")
        ui.search = ""

        ui.panel = .rule(DemoData.crowdedOutlookRuleID)
        ui.panelSourceWindowID = DemoData.crowdedOutlookWindowID
        ui.reveal = RevealRequest(window: DemoData.crowdedOutlookWindowID, seq: 3)
        pump(0.5)
        capture("g03-selected")

        ui.panel = .rule(DemoData.crowdedCometRuleID)
        ui.panelSourceWindowID = DemoData.crowdedCometWindowID
        capture("g04-selected-long")

        ui.panel = .session(DemoData.crowdedMessagesWindowID)
        ui.panelSourceWindowID = nil
        capture("g05-session")

        // Kalabalık kartın pencere listesi açık ("+1 daha" ya da başlıktaki düğme).
        ui.panel = nil
        ui.listedDesktops = [UIState.listKey(mode: .docked, screen: "builtin", desktop: 1)]
        capture("g05b-crowded-list-open")
        ui.listedDesktops = []

        ui.panel = nil
        ui.selection = Set(QuickStartCard.placeable(ScreenMapView.unownedWindows(
            world.windows, rules: store.document.rules, sessionPins: router.sessionPins)).map(\.id))
        capture("g06-pin-all")
        ui.selection = []

        ui.visualMap = false
        capture("g07-list")
        ui.visualMap = true

        ui.requestedPlan = .undocked
        pump(0.2)
        capture("g08-other-plan")
        ui.panel = .rule(DemoData.crowdedOutlookRuleID)
        capture("g09-other-plan-selected")
    }

    /// Demo dizisinin kareleri (docs/media GIF'i): d1 laptop tek başına,
    /// d2 monitör takıldı, d3 pencereler yerine gitti, d4 ikinci monitör.
    /// Ekranlar, pencereler ve masaüstü sayıları adım adım değiştirilir;
    /// hiçbir gerçek pencereye dokunulmaz (demo Router taşımaz).
    @MainActor
    private static func captureSequence(ui: UIState, router: Router, store: Store,
                                        screens: ScreenService, caption: ShotsCaption,
                                        capture: (String) -> Void) {
        let steps: [(String, DemoData.DemoStage, String)] = [
            ("d1-laptop", .laptopOnly, L("Laptop only: everything piles up on one desktop")),
            ("d2-monitor", .monitorConnected, L("Monitor connected: Deskmap knows where each window belongs")),
            ("d3-placed", .placed, L("Pinned windows go to their screen and desktop on their own")),
            ("d4-monitor-2", .secondMonitor, L("A second monitor keeps its own role: Monitor 2")),
        ]
        for (index, step) in steps.enumerated() {
            let (name, stage, text) = step
            caption.text = text
            caption.step = index + 1
            caption.count = steps.count
            store.document = DemoData.demoDocument(stage)
            screens.replaceDemoScreens(DemoData.demoScreens(stage))
            router.replaceDemoWindows(DemoData.demoWindows(stage))
            router.replaceDemoDesktopCounts(DemoData.demoDesktopCounts(stage))
            ui.desktopCounts = DemoData.demoDesktopCounts(stage)
            pump(0.3)
            // Harita yeni satırlarla kaymasın: ilk üç karede en üste, son
            // karede 2. monitördeki Mail'in satırına kaydır.
            if stage == .secondMonitor {
                ui.reveal = RevealRequest(window: DemoData.demoMailWindowID, seq: index + 1)
            } else if let scroll = ui.autoScroll.scrollView, let document = scroll.documentView {
                let top = document.isFlipped ? 0 : max(document.bounds.height - scroll.contentView.bounds.height, 0)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            pump(0.6)
            capture(name)
        }
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
    @EnvironmentObject private var caption: ShotsCaption

    var body: some View {
        VStack(spacing: 0) {
            RootView()
                // Durum satırı üstten kırpılmasın (ölçülen boy birkaç pt eksik).
                .padding(.top, caption.text.isEmpty ? 0 : 10)
            if !caption.text.isEmpty {
                HStack(spacing: 12) {
                    Text("\(caption.step)/\(caption.count)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(caption.text)
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.accentColor.opacity(0.28))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Demo dizisinin (`--scenario demo`) kare altyazısı; boşsa çizilmez.
/// Yalnız shots modunda vardır.
final class ShotsCaption: ObservableObject {
    @Published var text = ""
    @Published var step = 0
    @Published var count = 0
}
