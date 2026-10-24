import AppKit
import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var permission: AccessibilityPermission
    @EnvironmentObject private var ui: UIState

    @State private var mode: Mode = .undocked
    /// Son görülen gerçek mod; değişince seçici onu izler (kullanıcının
    /// elle seçtiği mod ekran parametreleri değişti diye sıfırlanmaz).
    @State private var liveMode: Mode?
    /// Gerekli macOS ayarlarının canlı durumu (her taramada yenilenir).
    @State private var settingChecks: [MacSettings.Check] = MacSettings.checks()
    /// Üst çubuktaki "?" açıklama paneli açık mı.
    @State private var showLegend = false
    /// "Son hareketler" paneli açık mı.
    @State private var showLog = false
    @FocusState private var searchFocused: Bool
    /// Sürükleme sırasında gelen tarama sonucu; sürükleme bitince uygulanır.
    @State private var pendingWindows: [Router.WindowSnapshot]?
    /// Harita ekranda mı (örtülme bildirimi aynı durumu yineleyebilir).
    @State private var mapShown = false
    /// Harita açıldığında öndeki pencere; listede görününce seçilir. Yeni
    /// açılmış pencere ilk taramayı bekleyebilir; süre dolunca vazgeçilir.
    @State private var pendingFront: (id: CGWindowID, until: Date, applied: Bool)?
    @State private var mapShownAt = Date.distantPast
    @State private var revealSeq = 0
    /// Alt çubuktaki süreli iletiler ("Geri al", son işlem) için saat;
    /// yalnızca bir ileti düşeceği anda yenilenir, sürekli zamanlayıcı yok.
    @State private var now = Date()

    /// Router'ın son işlemi alt çubukta bu kadar kalır; sonra genel ipucu döner.
    static let actionFade: TimeInterval = 30
    /// Bilgi iletisinin (`Store.notice`) alt çubukta kalma süresi.
    static let noticeFade: TimeInterval = 8
    /// Pencere boyutu ve sol kenar çubuğunun genişliği.
    /// Pencere boyutu ekranın kullanılabilir alanına oranlıdır (sabit pt
    /// değil): 1710×1074 pt'lik ekranda ≈ 900×750. Alt/üst sınırlar küçük
    /// ekranda okunurluğu, büyük ekranda gereksiz büyümeyi önler; üst sınır
    /// her zaman ekranın kendisidir (taşma yok).
    nonisolated static let widthFraction: CGFloat = 0.53
    nonisolated static let heightFraction: CGFloat = 0.70
    nonisolated static let minWindowWidth: CGFloat = 660
    nonisolated static let maxWindowWidth: CGFloat = 1100
    nonisolated static let minWindowHeight: CGFloat = 480
    nonisolated static let maxWindowHeight: CGFloat = 900

    /// Pencere genişliği (saf): ekranın oranı, sınırlar içinde, ekrandan
    /// geniş değil.
    nonisolated static func windowWidth(visibleWidth: CGFloat) -> CGFloat {
        let wanted = min(max(visibleWidth * widthFraction, minWindowWidth), maxWindowWidth)
        return max(min(wanted, visibleWidth - 2 * screenMargin), 0)
    }

    /// Panel kapalıyken istenen toplam yükseklik (saf); ekrana sığdırma
    /// `heights` içinde yapılır.
    nonisolated static func preferredHeight(visibleHeight: CGFloat) -> CGFloat {
        min(max(visibleHeight * heightFraction, minWindowHeight), maxWindowHeight)
    }

    /// Sağdaki ayrıntı sütununun genişliği.
    nonisolated static let inspectorWidth: CGFloat = 360
    /// Eski tip (hep görünen) kaydırma çubuğunun kapladığı genişlik (≈15 pt).
    static let scrollerGutter: CGFloat = 16
    /// Sütundaki sabit genişlikli öğelerin (ızgara, döşemeler) her koşulda
    /// sığması gereken genişlik: iç boşluk (2 × 16) ve kaydırma çubuğu hariç.
    static let inspectorBudget: CGFloat = inspectorWidth - 32 - scrollerGutter

    /// Harita, kenar çubuğu ve ayrıntı sütunuyla toplam genişlik (saf):
    /// sütun haritadan yer almaz; ekrana sığmazsa harita daralır.
    nonisolated static func totalWidth(visibleWidth: CGFloat) -> CGFloat {
        min(windowWidth(visibleWidth: visibleWidth) + inspectorWidth + 1,
            max(visibleWidth - 2 * screenMargin, 0))
    }

    /// Sol kenar çubuğu genişliği (saf): pencerenin üçte birine yakın.
    nonisolated static func sidebarWidth(windowWidth: CGFloat) -> CGFloat {
        min(max(windowWidth * 0.32, 220), 300)
    }
    /// Alt panel açıkken bile haritaya kalan en az yükseklik.
    nonisolated static let minMapHeight: CGFloat = 260
    /// Pencerenin ekranın kullanılabilir alanının altında bıraktığı boşluk.
    nonisolated static let screenMargin: CGFloat = 12

    /// Ölçülen yükseklikler: "top" (üst çubuklar), "bottom" (alt çubuk).
    /// Harita alanı bunlardan hesaplanır.
    @State private var heights: [String: CGFloat] = [:]

    /// Pencerenin bulunduğu ekranın kullanılabilir yüksekliği (Dock ve menü
    /// çubuğu hariç), eksi `screenMargin`. `WindowRoomReader` pencere ekran değiştirince ya da
    /// çözünürlük değişince yeniler; bilinmiyorsa nil.
    @State private var room: WindowRoom?
    /// Sistem hep görünen kaydırma çubuğu kullanıyor mu (fare takılıyken);
    /// sağ sütun o zaman çubuğun yerini baştan ayırır.
    @State private var legacyScrollers = NSScroller.preferredScrollerStyle == .legacy
    /// Son görülen bekleyen masaüstü silmeleri (taslağı kapatmak için).
    @State private var lastPendingRemovals: [String: [PendingRemoval]]?

    /// Harita alanı (kenar çubuğu + harita) ve alt panelin tavanı (saf).
    /// `room`: pencereye düşen toplam yükseklik; `chrome`: üst ve alt
    /// çubuklar; `panel`: panelin doğal yüksekliği (kapalıysa 0);
    ///
    /// - Panel kapalıyken pencere `preferredTotal` olur (sığarsa).
    /// - Panel açılınca pencere aşağı uzar, harita daralmaz.
    /// - Sağ sütunun uzunluğu pencereyi büyütmez: boy sabit, sütun kendi
    ///   içinde kayar (seçim değişince pencere sıçramasın).
    /// - Sığmazsa önce harita taşan kadar kısalır, en az `minMapHeight`
    ///   (çok küçük ekranda alanın yarısı) kalır; panel yine sığmazsa
    ///   `panelCap` yüksekliğinde kendi içinde kayar.
    ///
    /// Sonuç her zaman: chrome + map + min(panel, panelCap) ≤ room.
    nonisolated static func heights(chrome: CGFloat, panel: CGFloat, room: CGFloat,
                                    preferredTotal: CGFloat)
        -> (map: CGFloat, panelCap: CGFloat?) {
        let preferred = max(preferredTotal - chrome, 0)
        let space = max(room - chrome, 0)
        let map = max(min(preferred, max(space - panel, min(minMapHeight, space / 2))), 0)
        let left = space - map
        return (map, panel > left ? max(left, 0) : nil)
    }

    /// Son ölçülen üst ve alt çubuk yükseklikleri; uygulama yeniden
    /// açılınca da ilk karede doğru boy için saklanır (yoksa tahmin 90/36).
    @MainActor static var lastChrome: (top: CGFloat, bottom: CGFloat) = {
        let saved = UserDefaults.standard.array(forKey: chromeKey) as? [Double] ?? []
        return saved.count == 2 ? (saved[0], saved[1]) : (90, 36)
    }() {
        didSet {
            guard oldValue != lastChrome else { return }
            UserDefaults.standard.set([Double(lastChrome.top), Double(lastChrome.bottom)],
                                      forKey: chromeKey)
        }
    }
    private static let chromeKey = "MapWindowChromeHeights"

    /// Shots modunda sabit oda (gerçek ekran ve pencere konumu kullanılmaz).
    @Environment(\.demoRoom) private var demoRoom

    /// Ölçüm gelene dek panelin açılacağı ekran (menü çubuğunda tıklanan,
    /// yani imlecin bulunduğu ekran) esas alınır; oda yalnız ekranın
    /// kullanılabilir alanına bağlı olduğundan ilk kare de doğru boyda çizilir.
    private var currentRoom: WindowRoom {
        if let demoRoom { return demoRoom }
        if let room { return room }
        return WindowRoomReader.expectedRoom(margin: Self.screenMargin)
    }

    private var windowWidth: CGFloat { Self.windowWidth(visibleWidth: currentRoom.visible.width) }
    private var totalWidth: CGFloat { Self.totalWidth(visibleWidth: currentRoom.visible.width) }

    private var layoutHeights: (map: CGFloat, panelCap: CGFloat?) {
        let room = currentRoom
        // Çubuk yükseklikleri ölçülene dek son ölçülen değer (ilk açılışta
        // sabit tahmin yerine; panel her açılışta aynı boyda başlasın).
        let top = heights["top"] ?? Self.lastChrome.top
        let bottom = heights["bottom"] ?? Self.lastChrome.bottom
        return Self.heights(chrome: top + bottom,
                            panel: 0,
                            room: room.height,
                            preferredTotal: Self.preferredHeight(visibleHeight: room.visible.height))
    }

    /// Sürüklerken: pinli pencere bırakılınca kaydedilen hedef güncellenir,
    /// pinsiz pencere yalnız bir kez taşınır. Alt çubukta gösterilir:
    /// haritanın akışına eklenen satır bırakma hedeflerini imlecin altından
    /// kaydırıyor, kaymalı tıklama pencereyi bir üst masaüstüne taşıyordu.
    private var dragHint: String? {
        guard case .window(let id)? = ui.drag?.item,
              let window = ui.windows.first(where: { $0.id == id }) else { return nil }
        let pinned = Routing.select(
            rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
            windowID: id, bundleID: window.bundleID, appName: window.appName,
            title: window.title, document: window.document,
            context: mode == screens.mode ? router.routingContext : nil) != nil
        if pinned { return L("Pinned: dropping it updates the saved desktop.") }
        return mode == screens.mode
            ? L("Not pinned: dropping it moves the window once; nothing is saved.")
            : L("Not pinned: dropping it opens a pin for this plan; the window is not moved.")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
            statusLine
                .padding(.horizontal, 14)
                .padding(.top, 8)
            header
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 6)
            toolbar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Divider()
            }
            .measuresHeight("top")

            HStack(spacing: 0) {
            HStack(spacing: 0) {
                // Sol: kurulumlar arası farklar ve sahipsiz pencereler; hep
                // görünür, buradan haritaya yana doğru sürüklenir.
                ScrollView {
                    VStack(spacing: 10) {
                        QuickStartCard(mode: mode)
                        SetupDifferenceTray(mode: mode)
                        // İki sekmede de: sahipsizlik kurulumdan bağımsız.
                        UnownedWindowsTray(mode: mode)
                        FreeMoveTray(mode: mode)
                    }
                    .padding(12)
                    // Uzun içerik (çip + yer) sütunu yana taşırmasın.
                    .frame(width: Self.sidebarWidth(windowWidth: windowWidth))
                }
                .frame(width: Self.sidebarWidth(windowWidth: windowWidth))
                .reportsViewport("sidebar")

                Divider()

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if !permission.isTrusted {
                        PermissionCard()
                    }
                    if permission.isTrusted,
                       let reason = ReducedModeCard.Reason.current(
                           canMove: SkyLight.shared.canMove, health: router.moveHealth.state,
                           version: MoveSupport.versionLabel(ProcessInfo.processInfo.operatingSystemVersion)) {
                        ReducedModeCard(reason: reason) { router.retryMoves() }
                    }
                    if let report = store.migrationReport {
                        MigrationReportCard(
                            report: report,
                            removeEmpty: {
                                let spaces = report.emptyBeyondPlan.keys.sorted()
                                    .flatMap { report.emptyBeyondPlan[$0] ?? [] }
                                Task {
                                    let removed = await router.removeEmptyDesktops(spaces)
                                    if removed < spaces.count {
                                        store.report(L("%ld of %ld empty desktops removed; the others are no longer empty",
                                                       removed, spaces.count))
                                    }
                                    store.dismissMigrationReport()
                                }
                            },
                            undoUpgrade: { store.undoUpgrade() },
                            dismiss: { store.dismissMigrationReport() })
                    }
                    if let status = router.planStatus {
                        PlanStatusCard(status: status, retry: { router.retryPlan() },
                                       dismiss: { router.dismissPlanStatus() })
                    }
                    if let offer = router.revertOffer {
                        RevertOfferCard(offer: offer, moveBack: { router.acceptRevertOffer() },
                                        keep: { router.keepRevertedDesktops() },
                                        dismiss: { router.dismissRevertOffer() })
                    }
                    if !MacSettings.allRequiredOK(settingChecks) || !store.document.setupNoticeDismissed {
                        SetupCard(checks: settingChecks)
                    }
                    if permission.isTrusted && store.document.rules.isEmpty
                        && router.sessionPins.isEmpty {
                        FirstStepsCard()
                    }
                    ScreenMapView(mode: mode)
                    Color.clear.frame(height: 1)
                        .id(WindowAnchor(id: MapPlaces.mapEndAnchorID))
                }
                .padding(14)
                .background(EnclosingScrollViewReader { ui.autoScroll.scrollView = $0 })
            }
            .reportsViewport("map")
            .onChange(of: ui.reveal) { request in
                guard let request else { return }
                // Panel açılınca harita daralır; yerleşim bittikten sonra kaydır.
                DispatchQueue.main.async {
                    MapReveal.scroll(proxy, to: request.window)
                }
            }
            }
            }
            // Sürükleme koordinatları ve bırakma hedefleri iki sütunu da
            // kapsar; hayalet de burada çizilir (sütunlar arasında kırpılmaz).
            .coordinateSpace(name: MapSpace.name)
            .onPreferenceChange(DropTargetPreference.self) {
                ui.targets = $0
                ui.refreshHover()
            }
            .onPreferenceChange(ViewportPreference.self) { ui.viewports = $0 }
            .overlay(alignment: .topLeading) { DragGhost(mode: mode) }
            .onChange(of: ui.drag) { drag in
                ui.autoScroll.update(point: drag?.location,
                                     viewport: ui.viewports["map"] ?? .zero)
            }

                Divider()

                // Sağ: seçili pencerenin ayrıntısı. Sütun hep yerinde durur
                // (pencere tıklamayla genişleyip daralmasın); seçim yoksa
                // ipuçları. İçerik genişliği kaydırma çubuğu çıksa da
                // değişmez (sütun yana kaymasın); pencere boyu sabittir,
                // uzun içerik sütunun içinde kayar.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id(Self.inspectorTop)
                            inspector
                        }
                        .frame(width: Self.inspectorWidth - (legacyScrollers ? Self.scrollerGutter : 0),
                               alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Başka pencere ya da kural seçilince baştan başlar; aynı
                    // pencerenin taslağı güncellenince yerinde kalır.
                    .onChange(of: Self.inspectorSubject(multi: showsMultiPin, panel: ui.panel)) { _ in
                        proxy.scrollTo(Self.inspectorTop, anchor: .top)
                    }
                }
                .frame(width: Self.inspectorWidth)
            }
            .frame(height: layoutHeights.map)

            VStack(spacing: 0) {
                Divider()
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .measuresHeight("bottom")
        }
        .frame(width: totalWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(HeightPreference.self) {
            heights = $0
            if demoRoom == nil, let top = $0["top"], let bottom = $0["bottom"] {
                Self.lastChrome = (top, bottom)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            legacyScrollers = NSScroller.preferredScrollerStyle == .legacy
        }
        .background(WindowRoomReader(margin: Self.screenMargin) { room = $0 })
        .background(.regularMaterial)
        .onAppear {
            ui.watchCommandClicks()
            mode = screens.mode
            liveMode = screens.mode
            ui.windows = router.windows
            syncScreens()
        }
        .onReceive(screens.$screens) { list in
            // `$screens` willSet'te yayınlar: `screens.screens`/`screens.mode`
            // burada hâlâ eski değer, yayınlanan liste kullanılır
            // (docs/bug-tables.md A′, plan seçici satırı).
            syncScreens(list)
            // Monitör takılıp çıkarıldığında seçici gerçek modu izler
            // (pencere bir kez oluşturulduğu için onAppear yeniden gelmez).
            if let next = Self.followedMode(published: list, liveMode: liveMode) {
                liveMode = next
                mode = next
            }
        }
        .onReceive(ui.$requestedPlan) { plan in
            if let plan { mode = plan }
        }
        .onReceive(router.$windows) { windows in
            if ui.drag == nil {
                ui.windows = windows
            } else {
                pendingWindows = windows
            }
            selectFrontWindow(in: windows)
            // Kullanıcı Sistem Ayarları'nda düzeltince kart kendiliğinden güncellensin.
            let checks = MacSettings.checks()
            if checks != settingChecks { settingChecks = checks }
        }
        // Mission Control'de eklenen/silinen masaüstü haritaya yansısın;
        // pencere listesi değişmese de (Router ayrı yayınlar).
        .onReceive(router.$desktopCounts) { counts in
            guard !counts.isEmpty, counts != ui.desktopCounts else { return }
            // Taslağın ekranında masaüstü azaldı (ör. deskmap://remove-desktop):
            // numaralar kaydı, taslak eski numarayla yanlış yere pin yazmasın.
            if let draft = ui.pinDraft, let before = ui.desktopCounts[draft.target.screen],
               let after = counts[draft.target.screen], after < before {
                ui.panel = nil
            }
            ui.desktopCounts = counts
        }
        .onReceive(store.$document.map(\.pendingRemovals).removeDuplicates()) { removals in
            // Etkin olmayan kurulumda sıraya giren silme de numaraları kaydırır.
            defer { lastPendingRemovals = removals }
            guard let before = lastPendingRemovals, let draft = ui.pinDraft else { return }
            let key = Document.planKey(mode: mode, screen: draft.target.screen)
            if removals[key] != before[key] { ui.panel = nil }
        }
        .background(WindowVisibilityObserver { visible in
            router.setMapVisible(visible)
            // Pencere sürükleme sürerken kapandı: jest bitişi gelmez.
            if !visible { ui.drag = nil }
            guard visible != mapShown else { return }
            mapShown = visible
            if visible {
                showFrontWindow()
            } else {
                pendingFront = nil
                ui.releaseFocus()
            }
        })
        .onChange(of: ui.drag == nil) { idle in
            guard idle, let pending = pendingWindows else { return }
            ui.windows = pending
            pendingWindows = nil
        }
        .onChange(of: mode) { _ in
            ui.panel = nil
            // Seçili çipler başka planın kartlarında değil; seçim plana bağlı.
            ui.clearSelection()
            // Sürükleme sürerken sekme değişti: kaynağı görünümden kalkan jestin
            // bitişi gelmez; hayalet, donmuş liste ve kaydırma kalmasın.
            ui.drag = nil
            // Harita açılışı canlı sekmeye geçirdiyse öndeki pencere şimdi seçilir.
            selectFrontWindow(in: router.windows,
                              reapply: Date().timeIntervalSince(mapShownAt) < 0.5)
        }
        .onChange(of: ui.windows) { windows in
            // Kapanan pencereler çoklu seçimden düşer; seçim boşalınca panel döner.
            let open = Set(windows.map(\.id))
            if !ui.selection.isSubset(of: open) { ui.selection.formIntersection(open) }
            // Taslağın ya da geçici pinin penceresi kapandıysa paneli kapat.
            switch ui.panel {
            case .pin(let draft):
                if let current = windows.first(where: { $0.id == draft.window.id }) {
                    // Canlı kurulumda taslak penceresini izler: masaüstü
                    // değiştiyse hedef, çerçeve değiştiyse varsayılan düzen.
                    let followed = draft.following(current, isLive: mode == screens.mode)
                    if followed != draft { ui.panel = .pin(followed) }
                } else {
                    ui.panel = nil
                }
            case .session(let id) where !windows.contains(where: { $0.id == id }):
                ui.panel = nil
            default:
                break
            }
        }
        .onReceive(router.$sessionPins) { pins in
            // Oturum pini kalkınca (kapanan pencere) paneli kapat.
            if case .session(let id) = ui.panel, pins[id] == nil {
                ui.panel = nil
            }
        }
        .onReceive(store.$document) { document in
            // Kuralı silinen (ya da profil değişince kaybolan) panel kapanır.
            if case .rule(let id) = ui.panel, document.rule(id) == nil {
                ui.panel = nil
            }
            // Silinen (ya da profil değişince kaybolan) seçili çipler düşer.
            if !ui.selectedRules.isEmpty {
                let kept = ui.selectedRules.filter { document.rule($0) != nil }
                if kept != ui.selectedRules { ui.selectedRules = kept }
            }
        }
        .task(id: nextFooterDeadline) {
            // Süreli ileti düşeceği anda saati ilerlet; sonraki süre için
            // kimlik değişir ve görev yeniden kurulur.
            guard let deadline = nextFooterDeadline else { return }
            let delay = deadline.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            now = Date()
        }
    }

    /// Alt çubuktaki süreli iletilerden ilk düşecek olanın zamanı.
    private var nextFooterDeadline: Date? {
        [store.history.discardNoticeExpiry,
         router.status.lastActionAt.map { $0.addingTimeInterval(Self.actionFade) },
         store.notice.map { $0.at.addingTimeInterval(Self.noticeFade) }]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }

    /// Store'un bilgi iletisi hâlâ gösterilecek kadar yeni mi?
    private var recentNotice: String? {
        guard let notice = store.notice,
              now.timeIntervalSince(notice.at) < Self.noticeFade else { return nil }
        return notice.text
    }

    /// Son işlem hâlâ gösterilecek kadar yeni mi?
    private var recentAction: String? {
        guard let action = router.status.lastAction, let at = router.status.lastActionAt,
              now.timeIntervalSince(at) < Self.actionFade else { return nil }
        return action
    }

    /// Harita açıldı: önceki açılıştan kalan panel, çoklu seçim ve arama
    /// kapanır, harita şu an geçerli planda açılır; kullanıcının en son
    /// tıkladığı pencere satırına tıklanmış gibi seçilir ve görünür yere
    /// kaydırılır. Öndeki pencere yoksa (masaüstü, penceresiz uygulama)
    /// seçim yapılmaz.
    private func showFrontWindow() {
        ui.panel = nil
        ui.panelSourceWindowID = nil
        ui.clearSelection()
        ui.search = ""
        searchFocused = false
        mapShownAt = Date()
        pendingFront = AX.frontWindowID().map { ($0, Date().addingTimeInterval(2), false) }
        // Sekme değişimi `onChange(of: mode)` ile öndeki pencereyi yeniden seçer.
        mode = screens.mode
        selectFrontWindow(in: router.windows)
    }

    /// `reapply`: seçim yapıldıktan sonra sekme değişimi paneli kapattıysa
    /// yeniden seçilir (uygulamanın ilk açılışında `onAppear` sekmeyi ayarlar,
    /// `onChange` seçimden sonra gelebilir).
    private func selectFrontWindow(in windows: [Router.WindowSnapshot], reapply: Bool = false) {
        guard let pending = pendingFront else { return }
        guard Date() < pending.until else { pendingFront = nil; return }
        guard !pending.applied || reapply else { return }
        guard let window = windows.first(where: { $0.id == pending.id }) else { return }
        // Canlı pencereler yalnız canlı kurulumun sekmesinde listelenir;
        // sekme değişimi paneli kapattıktan sonra burası yeniden çağrılır.
        if mode != screens.mode { mode = screens.mode; return }
        pendingFront?.applied = true
        let sessionPinned = router.sessionPins[window.id] != nil
        let rule: Rule? = Routing.select(
            rules: store.document.rules, sessionPins: [:], mode: mode,
            windowID: window.id, bundleID: window.bundleID,
            appName: window.appName, title: window.title, document: window.document,
                context: router.context(for: mode))?.rule
        ui.panel = UIState.openingPanel(for: window, sessionPinned: sessionPinned,
                                        ruleID: rule?.id)
        ui.panelSourceWindowID = sessionPinned || rule == nil ? nil : window.id
        if let placement = window.placement {
            let group = window.bundleID.isEmpty ? window.appName : window.bundleID
            ui.collapsed.remove(UIState.collapseKey(mode: screens.mode, screen: placement.screen,
                                                    desktop: placement.desktop, group: group))
            // Kazanan kural bir pin grubundaysa satır o grubun kutusunda çizilir;
            // kutu katlıysa açılmazsa kaydırma satırı bulamaz.
            if !sessionPinned, let groupID = rule?.groupID {
                ui.collapsed.remove(UIState.collapseKey(mode: screens.mode, screen: placement.screen,
                                                        desktop: placement.desktop,
                                                        group: PinGroupBox.idPrefix + groupID))
            }
        }
        revealSeq += 1
        ui.reveal = RevealRequest(window: window.id, seq: revealSeq)
        Log.app.notice("Map opened on front window \(window.id) (\(window.appName, privacy: .public))")
    }

    private func syncScreens(_ list: [ScreenInfo]? = nil) {
        let list = list ?? screens.screens
        store.remember(list.map(\.known))
        ui.desktopCounts = Router.desktopCounts(screens: list)
    }

    /// `$screens` yayınından sonra plan seçicinin geçeceği mod; gerçek mod
    /// değişmediyse nil (kullanıcının seçtiği öbür plan korunur). Saf.
    nonisolated static func followedMode(published: [ScreenInfo], liveMode: Mode?) -> Mode? {
        let next = ScreenService.mode(of: published)
        return next == liveMode ? nil : next
    }

    // MARK: - Ayrıntı sütunu

    private static let inspectorTop = "inspectorTop"

    /// Çoklu seçim çubuğu mu gösteriliyor.
    /// Seçili pencere yalnız canlı planda anlamlı; seçili çip (gruplama) her planda.
    private var showsMultiPin: Bool {
        (!ui.selection.isEmpty && mode == screens.mode) || !ui.selectedRules.isEmpty
    }

    /// Sütunda neyin gösterildiği (saf): kaydırma yalnız bu değişince başa
    /// döner. Taslağın kendisi değil penceresi sayılır; pencere hareket edince
    /// ya da hedef sürüklenince taslak yeniden yazılır, sütun zıplamamalı.
    nonisolated static func inspectorSubject(multi: Bool, panel: BottomPanel?) -> String {
        if multi { return "multi" }
        switch panel {
        case .pin(let draft): return "pin-\(draft.window.id)"
        case .rule(let id): return "rule-\(id)"
        case .session(let id): return "session-\(id)"
        case .profile: return "profile"
        case nil: return "none"
        }
    }

    /// Açık panele göre içerik; pin taslağı yalnızca şu anki modda anlamlı.
    @ViewBuilder
    private var inspector: some View {
        if showsMultiPin {
            MultiPinBar(mode: mode)
                .inspectorChrome()
        } else {
            singlePanel
        }
    }

    @ViewBuilder
    private var singlePanel: some View {
        switch ui.panel {
        // Taslak açıldığı sekmenin modundadır (sekme değişince panel kapanır);
        // diğer kurulumun sekmesinde de pin yazılabilir.
        case .pin(let draft):
            // Kimlik pencereye bağlı: başka pencereye geçince @State
            // (başlık parçaları, düzen) eski pencereden kalmasın.
            PinPanel(draft: draft, mode: mode)
                .id(draft.window.id)
                .inspectorChrome()
        case .rule(let id):
            if let rule = store.rule(id) {
                // Kimlik kurala bağlı: başka kurala geçince parça seçimi
                // eski kuraldan kalmasın (macOS 13 onChange'i eski
                // gövdenin kapanışını çağırıp eski başlığı geri yazıyordu).
                RulePanel(rule: rule, mode: mode)
                    .id(rule.id)
                    .inspectorChrome()
            } else {
                InspectorPlaceholder().inspectorChrome()
            }
        case .session(let id):
            if let window = ui.windows.first(where: { $0.id == id }),
               let destination = router.sessionPins[id] {
                SessionPinPanel(window: window, destination: destination)
                    .inspectorChrome()
            } else {
                InspectorPlaceholder().inspectorChrome()
            }
        case .profile:
            ProfilePanel()
                .inspectorChrome()
        default:
            InspectorPlaceholder()
                .inspectorChrome()
        }
    }

    // MARK: - Üst çubuk

    /// En üst satır: menü çubuğundaki durum noktasının nedeni.
    private var statusLine: some View {
        let indicator = StatusIndicator.current(store: store, router: router, screens: screens,
                                                trusted: permission.isTrusted)
        let color: Color = switch indicator.level {
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(indicator.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $store.document.enabled) {
                // İki etiketin genişi yer ayırır: anahtar ve plan seçici
                // tıklamadan sonra kaymaz.
                ZStack(alignment: .leading) {
                    Text(L("Deskmap on")).hidden().accessibilityHidden(true)
                    Text(L("Paused")).hidden().accessibilityHidden(true)
                    Text(store.document.enabled ? L("Deskmap on") : L("Paused"))
                        .foregroundStyle(store.document.enabled ? Color.primary : Color.orange)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(store.document.enabled ? L("Routing on") : L("Routing paused"))

            HStack(spacing: 6) {
                Text(L("Plan:"))
                    .foregroundStyle(.secondary)
                Picker("", selection: $mode) {
                    ForEach(Array(Mode.allCases.enumerated()), id: \.element) { index, candidate in
                        Text(candidate.title)
                            .help(candidate.title + " (⌘\(index + 1))")
                            .tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .background(shortcuts)
                planNote
            }

            Spacer(minLength: 8)

            profileMenu

            Button {
                showLegend.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help(L("What do the colors and badges mean?"))
            .accessibilityLabel(L("What do the colors and badges mean?"))
            .popover(isPresented: $showLegend, arrowEdge: .bottom) { LegendView() }

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L("Settings (⌘,)"))
            .accessibilityLabel(L("Settings"))

            moreMenu
        }
        .font(.callout)
    }

    /// İkinci satır: pencere arama, Görsel / Liste, son hareketler.
    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Search windows (⌘F)"), text: $ui.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .frame(width: 190)
                    .onExitCommand { ui.search = ""; searchFocused = false }
                    // Yalnız odakta ve yazı varken: boş aramada Esc panele kalır.
                    .onChange(of: searchFocused) { ui.setEditing("search", $0 && !ui.search.isEmpty) }
                    .onChange(of: ui.search) { ui.setEditing("search", searchFocused && !$0.isEmpty) }
                // Sayı ve temizleme düğmesi hep yer kaplar (boşken gizli):
                // yazınca kapsül genişleyip Görsel / Liste'yi itmez.
                let searching = !ui.search.trimmingCharacters(in: .whitespaces).isEmpty
                let hits = searching ? searchHits : 0
                HStack(spacing: 6) {
                    ZStack(alignment: .trailing) {
                        Text(L("1 match")).hidden().accessibilityHidden(true)
                        Text(L("%ld matches", 888)).hidden().accessibilityHidden(true)
                        Text(hits == 1 ? L("1 match") : L("%ld matches", hits))
                            .foregroundStyle(hits == 0 ? Color.orange : Color.secondary)
                    }
                    .font(.caption.monospacedDigit())
                    Button {
                        ui.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Clear the search"))
                    .accessibilityLabel(L("Clear the search"))
                }
                .opacity(searching ? 1 : 0)
                .allowsHitTesting(searching)
                .accessibilityHidden(!searching)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            Picker("", selection: $ui.visualMap) {
                Text(L("Visual")).tag(true)
                Text(L("List")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L("Visual: each desktop is a card with its windows drawn where they sit. List: one row per desktop."))

            Spacer()

            Button {
                showLog.toggle()
            } label: {
                Label(L("Recent moves"), systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help(L("What Deskmap moved, when and where"))
            .popover(isPresented: $showLog, arrowEdge: .bottom) { ActivityLogView() }
        }
        .font(.callout)
    }

    /// Seçili planın haritasında aramaya uyan öğe sayısı.
    private var searchHits: Int {
        UIState.searchHits(query: ui.search, windows: ui.windows, rules: store.document.rules,
                           sessionPins: router.sessionPins, mode: mode,
                           isLive: mode == screens.mode)
    }

    /// Seçili planın şu an geçerli olup olmadığı; değilse ne zaman geçerli olacağı.
    @ViewBuilder
    private var planNote: some View {
        if mode == screens.mode {
            ActivePlanBadge()
                .help(L("This plan is in effect right now"))
        } else {
            Text(mode == .undocked ? L("Applies when the monitor is unplugged")
                 : L("Applies when a monitor is connected"))
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .help(L("Changes here do not move any window now; they are used when this plan takes effect."))
        }
    }

    /// Etkin profilin adı; menüde profiller arası geçiş ve yönetim.
    private var profileMenu: some View {
        Menu {
            ForEach(store.profiles) { profile in
                MenuCheck(profile.name, checked: profile.id == store.document.activeProfileID) {
                    // Zaten etkin profili seçmek menüyü kapatır; taslak kalır.
                    guard profile.id != store.document.activeProfileID else { return }
                    ui.panel = nil
                    store.switchProfile(to: profile.id)
                }
            }
            Divider()
            Button(L("New empty profile")) {
                store.addProfile(activate: false)
                openSettings(.profiles)
            }
            Button(L("Import a profile from a file (.deskmap.json)")) {
                ui.panel = nil
                ProfileFiles.importProfile(into: store)
            }
            Button(L("Manage profiles…")) { openSettings(.profiles) }
        } label: {
            Text(L("Profile: %@", store.activeProfile?.name ?? ""))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("Profiles: each one is a separate set of pins"))
    }

    /// Seyrek kullanılan eylemler.
    private var moreMenu: some View {
        Menu {
            Button(L("Place pinned windows now (⌘R)")) { router.reapplyAll() }
            // Onay penceresi yok: menü çubuğu penceresinde sheet'in düğmesine
            // basılınca pencere kapanıyor ve eylem düşüyordu. Diğer yıkıcı
            // işlemler gibi alt çubuktaki "Geri al" ile korunur.
            if mode == .docked {
                Button(L("Copy the Laptop only plan here")) {
                    // S1: etkin kurulumsa plan şimdi uygulanır (masaüstü silinmez).
                    if store.copyLayout(from: .undocked, to: .docked), screens.mode == .docked {
                        router.applyPlanNow(reason: "copy layout")
                    }
                }
                .disabled(!store.document.hasLayout(in: .undocked))
                .help(L("Copy the Laptop only plan here; the current Monitor connected plan is replaced (⌘Z undoes)"))
            }
            Divider()
            Button(L("Settings…")) { openSettings() }
            Button(L("Quit Deskmap")) { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("More"))
        .accessibilityLabel(L("More"))
    }

    private func openSettings(_ tab: SettingsTab? = nil) {
        showLegend = false
        SettingsWindow.shared.show(tab: tab, store: store)
    }

    /// ⌘1 / ⌘2 seçicideki sırayla modu seçer; ⌘R sabit pencereleri yerine
    /// koyar, ⌘, Ayarlar'ı açar. Görünmez, boyutsuz düğmeler; pencere önde
    /// olduğu sürece kısayollar çalışır.
    private var shortcuts: some View {
        HStack(spacing: 0) {
            ForEach(Array(Mode.allCases.enumerated()), id: \.element) { index, candidate in
                Button("") { mode = candidate }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button("") { router.reapplyAll() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Seçili plandaki sabit pencere sayısı; geçici sabitlemeler plandan
    /// bağımsız ama yalnızca şu anki planın haritasında görünür, orada sayılır.
    private var pinSummary: some View {
        let pinned = store.document.rules.filter { $0[mode] != nil }.count
        let session = mode == screens.mode ? router.sessionPins.count : 0
        let pinText = pinCount(pinned)
        return Text(session > 0 ? L("%@ · %ld temporary", pinText, session) : pinText)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .help(session == 0
                  ? L("Pins in the %@ plan: %ld", mode.title, pinned)
                  : session == 1
                    ? L("1 window is pinned for this session only (not saved to the profile)")
                    : L("%ld windows are pinned for this session only (not saved to the profile)", session))
    }

    // MARK: - Alt çubuk

    /// Soldaki durum metni, sağda (varsa) geri alma bağlantısı ve düğmeler.
    /// Geri alma durum metninden bağımsızdır: hata ya da yanıt vermeyen
    /// uygulama iletisi onu gizlemez; yer darsa önce durum metni kısalır.
    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if let hint = dragHint {
                    Label(hint, systemImage: "hand.draw")
                } else if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if let notice = recentNotice {
                    Label(notice, systemImage: "info.circle")
                } else if !router.status.unresponsive.isEmpty {
                    Label(L("%@ not responding; skipped for now",
                            router.status.unresponsive.joined(separator: ", ")),
                          systemImage: "hourglass")
                        .foregroundStyle(.orange)
                        .help(L("The app did not answer Accessibility requests (frozen or stopped in a debugger). It is listed again automatically once it responds."))
                } else if let action = recentAction {
                    Label(action, systemImage: "arrow.turn.down.right")
                } else {
                    Text(store.document.rules.isEmpty
                         ? L("Pin a window, or drag it to another desktop.")
                         : L("Pinned windows are kept in place; others are left alone."))
                }
            }
            .lineLimit(1)

            Spacer()

            if store.history.discardNoticeVisible(at: now),
               let count = store.history.discarded?.entries.count {
                Button {
                    undo()
                } label: {
                    Label(count == 1 ? L("1 redoable step discarded · Undo")
                                     : L("%ld redoable steps discarded · Undo", count),
                          systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .lineLimit(1)
                .layoutPriority(1)
                .help(L("A new change replaced the steps you had undone. Undo brings them back."))
            }

            historyButtons
                .layoutPriority(1)

            pinSummary
                .layoutPriority(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Kalıcı ↶ ↷ düğmeleri; help metni sıradaki adımın etiketi, devre
    /// dışıyken soluk.
    private var historyButtons: some View {
        HStack(spacing: 2) {
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!store.history.canUndo)
            .help(store.history.undoEntry.map { L("Undo: %@ (⌘Z)", $0.label) }
                  ?? L("Nothing to undo"))
            .accessibilityLabel(L("Undo"))

            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!store.history.canRedo)
            .help(store.history.redoEntry.map {
                $0.isRedoable ? L("Redo: %@ (⇧⌘Z)", $0.label)
                              : L("%@ cannot be redone", $0.label)
            } ?? L("Nothing to redo"))
            .accessibilityLabel(L("Redo"))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    /// ⇧⌘Z / "Yinele": metin alanı odaktaysa onun yinelemesi.
    private func redo() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            if let manager = editor.undoManager, manager.canRedo { manager.redo() }
            return
        }
        store.redo()
    }

    /// ⌘Z / "Geri al": odak bir metin alanındaysa (profil adı, yüzde
    /// kutusu) geri alma o metnin geri almasıdır, belgeye dokunulmaz.
    private func undo() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            if let manager = editor.undoManager, manager.canUndo { manager.undo() }
            return
        }
        store.undo()
    }
}

/// Barındıran pencerenin ekranda olup olmadığını bildirir (menü çubuğu
/// penceresi bir kez oluşturulur; `onAppear` her açılışta gelmez).
/// Görünürlük pencerenin örtülme durumundan okunur.
private struct WindowVisibilityObserver: NSViewRepresentable {

    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        // nonisolated(unsafe): yalnızca ana aktörde (viewDidMoveToWindow)
        // değişir, deinit'te kaldırılır; gözlemci belirteci Sendable olmadığı
        // için deinit erişimi başka türlü sıkı eşzamanlılık uyarısı verir.
        nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { onChange?(false); return }
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.willCloseNotification] {
                tokens.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.report(closing: closing) }
                })
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            guard let window else { return }
            onChange?(!closing && window.isVisible
                      && window.occlusionState.contains(.visible))
        }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// Alt görünümlerin ölçülen yükseklikleri (anahtar → yükseklik).
struct HeightPreference: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Görünümün yüksekliğini `HeightPreference` ile bildirir.
    func measuresHeight(_ key: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: HeightPreference.self,
                                   value: [key: geometry.size.height])
        })
    }
}

/// Pencerenin ekranındaki yer: üst kenarından aşağı kullanılabilir yükseklik
/// ve ekranın kullanılabilir alanının boyutu (oranlı pencere boyutu için).
struct WindowRoom: Equatable {
    var height: CGFloat
    var visible: CGSize
}

private struct DemoRoomKey: EnvironmentKey {
    static let defaultValue: WindowRoom? = nil
}

extension EnvironmentValues {
    /// Shots modu: gerçek ekran yerine bu oda; ayrıca kullanıcı tercihleri
    /// (katlanmış kutu) karelere karışmaz.
    var demoRoom: WindowRoom? {
        get { self[DemoRoomKey.self] }
        set { self[DemoRoomKey.self] = newValue }
    }
}

/// Pencerenin bulunduğu ekranın kullanılabilir yüksekliğini bildirir ve
/// pencereyi yerleştirir: gösterim başına bir kez konum verir, sonra yalnız
/// ekrandan taşmayı düzeltir. Pencere başka ekrana geçince ya da ekran
/// ayarları değişince yeniden ölçer.
struct WindowRoomReader: NSViewRepresentable {

    let margin: CGFloat
    let changed: (WindowRoom) -> Void

    func makeNSView(context: Context) -> NSView { Probe(margin: margin, changed: changed) }
    func updateNSView(_ view: NSView, context: Context) {}

    /// Kullanılabilir yükseklik (saf): ekranın kullanılabilir alanı (Dock
    /// ve menü çubuğu hariç) eksi pay. Pencerenin o anki konumuna bağlı
    /// değil; pencere taşınınca ya da boyu değişince oda küçülmez.
    static func room(visible: CGRect, margin: CGFloat) -> CGFloat {
        max(visible.height - margin, 0)
    }

    /// Panel henüz ölçülmeden: imlecin bulunduğu ekran (menü çubuğu
    /// simgesine o ekranda tıklanır), yoksa ana ekran.
    @MainActor static func expectedRoom(margin: CGFloat) -> WindowRoom {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 860)
        return WindowRoom(height: room(visible: visible, margin: margin), visible: visible.size)
    }

    /// Harita penceresinin ilk konumu (saf). Dahili ekranda (laptop) üstte
    /// ortalanır; harici ekranda macOS'un koyduğu yer korunur. Her iki
    /// durumda da pencere ekranın kullanılabilir alanından taşmaz.
    static func placed(_ frame: CGRect, visible: CGRect, builtIn: Bool) -> CGPoint {
        var x = builtIn ? visible.midX - frame.width / 2 : frame.minX
        var y = builtIn ? visible.maxY - frame.height : frame.minY
        x = min(max(x, visible.minX), max(visible.maxX - frame.width, visible.minX))
        y = min(max(y, visible.minY), max(visible.maxY - frame.height, visible.minY))
        return CGPoint(x: x, y: y)
    }

    private final class Probe: NSView {
        let margin: CGFloat
        let changed: (WindowRoom) -> Void
        private var last: WindowRoom?
        // nonisolated(unsafe): ObserverView.tokens ile aynı gerekçe.
        nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []
        /// Kendi `setFrameOrigin` çağrılarımızın ürettiği olaylar yok sayılır.
        private var adjusting = false
        /// Bu gösterimde ilk konum verildi mi (panel gizlenince sıfırlanır).
        private var placedThisShow = false
        /// Korunacak üst kenar ve yatay orta: boy değişince pencere kaymasın.
        private var top: CGFloat?
        private var midX: CGFloat?
        private var left: CGFloat?
        private var right: CGFloat?
        /// Gösterim gizli (alpha 0) başlar; boy ve konum oturunca açılır.
        /// Ekran değiştiyse eski boy (`staleSize`) bitene dek gizli kalır.
        private var revealPending = false
        private var staleSize: CGSize?
        private var revealDeadline = Date.distantPast
        private var shownScreen: NSNumber?
        /// Kendi boy/konum değişikliğimizden hemen sonra macOS'un ürettiği
        /// taşıma (simgenin altına geri koyma) kullanıcı taşıması sayılmaz.
        private var lastAdjust = Date.distantPast

        private func remember() {
            guard let window else { return }
            top = window.frame.maxY
            left = window.frame.minX
            midX = window.frame.midX
            right = window.frame.maxX
        }

        /// Boy değişince yatayda neresi sabit kalır: laptop ekranında orta,
        /// harici ekranda sağ kenar (macOS paneli simgeye sağdan hizalıyor),
        /// kullanıcı taşıdıysa sol kenar. Üst kenar her zaman sabit.
        private func anchor(_ frame: inout CGRect) {
            if let top { frame.origin.y = top - frame.height }
            guard let left, let midX, let right else { return }
            frame.origin.x = userMoved ? left
                : builtIn ? midX - frame.width / 2
                : right - frame.width
        }
        /// Kullanıcı bu gösterimde pencereyi taşıdı (yeniden ortalanmaz).
        private var userMoved = false

        init(margin: CGFloat, changed: @escaping (WindowRoom) -> Void) {
            self.margin = margin
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }

        /// İçerik boyu değişince pencere ona uydurulur.
        override func setFrameSize(_ newSize: NSSize) {
            let sizeChanged = newSize != frame.size
            super.setFrameSize(newSize)
            if sizeChanged { DispatchQueue.main.async { [weak self] in self?.fit() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            placedThisShow = false
            userMoved = false
            top = nil
            midX = nil
            left = nil
            right = nil
            guard let window else { return }
            window.alphaValue = 0
            let center = NotificationCenter.default
            // Gözlemci `queue: .main` ile ana iş parçacığında çalışır;
            // gövde `@MainActor @Sendable`, çağrı assumeIsolated ile yapılır.
            func on(_ name: Notification.Name, _ object: Any?,
                    _ body: @escaping @MainActor @Sendable (Probe) -> Void) {
                tokens.append(center.addObserver(forName: name, object: object, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { if let self { body(self) } } })
            }
            // Gösterim animasyonu alpha'yı kendisi 1'e çekiyor; gizli
            // başlatma (eski karenin görünmemesi) bunu kapatmayı gerektirir.
            window.animationBehavior = .none
            on(NSWindow.didChangeOcclusionStateNotification, window) { $0.visibilityChanged() }
            on(NSWindow.didBecomeKeyNotification, window) { $0.placeOnce() }
            on(NSWindow.didMoveNotification, window) { $0.moved() }
            on(NSWindow.didResizeNotification, window) { $0.resized() }
            on(NSWindow.didChangeScreenNotification, window) { $0.keepOnScreen(); $0.measure() }
            on(NSApplication.didChangeScreenParametersNotification, nil) {
                $0.keepOnScreen(); $0.measure()
            }
            placeOnce()
            measure()
        }

        private var builtIn: Bool {
            guard let screen = window?.screen else { return false }
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }

        private func visibilityChanged() {
            guard let window else { return }
            if window.isVisible && window.occlusionState.contains(.visible) {
                placeOnce()
            } else if !window.isVisible {
                placedThisShow = false
                userMoved = false
                top = nil
                midX = nil
                left = nil
                right = nil
                // Bir sonraki gösterimin ilk karesi (eski boy/konum) görünmesin.
                window.alphaValue = 0
            }
        }

        /// Gösterim başına bir kez: laptop ekranında üst ortaya, harici
        /// ekranda macOS'un yerinde (yalnız ekrana sığdırılarak).
        private func placeOnce() {
            guard !placedThisShow, let window, window.isVisible,
                  let screen = window.screen else { return }
            placedThisShow = true
            window.alphaValue = 0
            let oldSize = window.frame.size
            // Başka ekrandan gelindiyse SwiftUI yeni boya geçene dek gizli.
            // (Ekran değişim bildirimi odayı önceden güncellemiş olabilir;
            // ölçüt son gösterimin ekranı.)
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let roomChanged = measure(now: true)
            let screenChanged = shownScreen != nil && shownScreen != screenID
            shownScreen = screenID
            staleSize = roomChanged || screenChanged ? oldSize : nil
            revealPending = true
            revealDeadline = Date().addingTimeInterval(0.8)
            var frame = window.frame
            if let size = fittedSize(window),
               abs(size.width - frame.width) > 1.5 || abs(size.height - frame.height) > 1.5 {
                frame.size = size
            }
            frame.origin.y = window.frame.maxY - frame.height
            let target = WindowRoomReader.placed(frame, visible: screen.visibleFrame, builtIn: builtIn)
            setFrame(target, size: frame.size)
            remember()
            logFrame("placed")
            DispatchQueue.main.async { [weak self] in self?.fit(); self?.tryReveal() }
        }

        /// Boy içeriğe oturdu ve (ekran değiştiyse) eski boy bittiyse görünür
        /// yap; değilse kısa aralıkla yeniden dene, en geç süre dolunca aç.
        private func tryReveal() {
            guard revealPending, let window else { return }
            guard window.isVisible else { revealPending = false; return }
            let settled: Bool = {
                guard let size = fittedSize(window) else { return false }
                let fits = abs(size.width - window.frame.width) <= 1.5
                    && abs(size.height - window.frame.height) <= 1.5
                guard fits else { return false }
                guard let staleSize else { return true }
                return abs(window.frame.width - staleSize.width) > 1.5
                    || abs(window.frame.height - staleSize.height) > 1.5
            }()
            if settled || Date() >= revealDeadline {
                revealPending = false
                let fromOtherScreen = staleSize != nil
                staleSize = nil
                if fromOtherScreen {
                    // Boy oturdu ama SwiftUI içeriği bir iki kare daha eski
                    // ekranın düzeniyle çiziyor; kısa bir bekleme.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let self, self.placedThisShow, let window = self.window,
                              window.isVisible else { return }
                        window.alphaValue = 1
                    }
                } else {
                    window.alphaValue = 1
                }
                logFrame(settled ? "shown" : "shown (timeout)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.fit(); self?.tryReveal()
            }
        }

        /// SwiftUI içeriğinin istediği pencere boyu. MenuBarExtra penceresi
        /// içerik küçülünce kendiliğinden daralmıyor (kenarda saydam bant
        /// kalıyordu); boy farklıysa üst kenar korunarak tek seferde uyulur.
        private func fittedSize(_ window: NSWindow) -> CGSize? {
            // Bu görünüm kök içeriğin arka planı: boyu içeriğin boyu
            // (barındırıcının fittingSize'ı pencere küçülürken eski boyda kalıyor).
            let fit = bounds.size
            guard fit.width > 1, fit.height > 1 else { return nil }
            return window.frameRect(forContentRect: CGRect(origin: .zero, size: fit)).size
        }

        private func fit() {
            guard let window, window.isVisible, let screen = window.screen,
                  let size = fittedSize(window),
                  // SwiftUI pencereyi tam noktaya yuvarlıyor; 1 pt'lik fark
                  // için boyutlandırılırsa iki taraf birbirini düzeltir durur.
                  abs(size.width - window.frame.width) > 1.5
                    || abs(size.height - window.frame.height) > 1.5 else { return }
            var frame = window.frame
            frame.size = size
            anchor(&frame)
            setFrame(WindowRoomReader.placed(frame, visible: screen.visibleFrame,
                                             builtIn: builtIn && !userMoved),
                     size: size)
            remember()
            logFrame("fitted")
        }

        /// Kullanıcı taşıdı: yeni yer korunur, yalnız ekrandan taşma düzeltilir.
        private func moved() {
            guard !adjusting, window != nil else { return }
            // Kendi boyutlandırmamızın ardından macOS'un yaptığı geri koyma
            // ya da gizliyken olan taşıma kullanıcı taşıması değil.
            if placedThisShow, !revealPending, Date().timeIntervalSince(lastAdjust) > 0.3 {
                userMoved = true
            }
            keepOnScreen()
            remember()
            measure()
        }

        /// Boy değişti: üst kenar yerinde kalır (tek çağrı), ekrana sığdırılır.
        private func resized() {
            guard !adjusting, let window, let screen = window.screen else { return }
            // macOS boy değişince pencereyi simgenin altına geri koyuyor;
            // üst kenar ve yatay orta korunur (tek çağrı).
            var frame = window.frame
            anchor(&frame)
            move(to: WindowRoomReader.placed(frame, visible: screen.visibleFrame, builtIn: false))
            remember()
            logFrame("resized")
            measure()
        }

        private func keepOnScreen() {
            guard let window, let screen = window.screen else { return }
            move(to: WindowRoomReader.placed(window.frame, visible: screen.visibleFrame,
                                             builtIn: false))
        }

        private func move(to origin: CGPoint) {
            guard let window else { return }
            setFrame(origin, size: window.frame.size)
        }

        private func setFrame(_ origin: CGPoint, size: CGSize) {
            guard let window else { return }
            let frame = CGRect(origin: origin, size: size)
            guard abs(frame.minX - window.frame.minX) > 0.5 || abs(frame.minY - window.frame.minY) > 0.5
                    || abs(frame.width - window.frame.width) > 0.5
                    || abs(frame.height - window.frame.height) > 0.5 else { return }
            adjusting = true
            // MenuBarExtra penceresi setFrame'de konumu simgenin altına geri
            // çekiyor; boy ayrı, konum setFrameOrigin ile verilir.
            if abs(frame.width - window.frame.width) > 0.5
                || abs(frame.height - window.frame.height) > 0.5 {
                window.setFrame(frame, display: true)
            }
            window.setFrameOrigin(frame.origin)
            adjusting = false
            lastAdjust = Date()
        }

        private func logFrame(_ why: String) {
            guard let frame = window?.frame else { return }
            Log.app.notice("""
                Map window \(why, privacy: .public): \(Int(frame.minX)),\(Int(frame.minY)) \
                \(Int(frame.width))×\(Int(frame.height))
                """)
        }

        /// `now`: gösterim anında (durum güncellemesi dışında) oda hemen
        /// verilir ki pencere ilk karede o ekranın boyuyla çizilsin.
        @discardableResult
        private func measure(now: Bool = false) -> Bool {
            guard let window, let screen = window.screen else { return false }
            let room = WindowRoom(
                height: WindowRoomReader.room(visible: screen.visibleFrame, margin: margin),
                visible: screen.visibleFrame.size)
            guard room != last else { return false }
            let first = last == nil
            last = room
            Log.app.notice("""
                Map window room: \(Int(room.height)) pt on \(screen.localizedName, privacy: .public) \
                (visible \(Int(room.visible.width))×\(Int(room.visible.height)) pt)
                """)
            if now {
                changed(room)
                window.contentView?.layoutSubtreeIfNeeded()
                return !first
            }
            // Görünüm güncellemesi sırasında durum değiştirilmesin; SwiftUI
            // yeni odayla yerleşince pencere içeriğe uydurulur.
            DispatchQueue.main.async { [weak self, changed] in
                changed(room)
                DispatchQueue.main.async { self?.fit() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.fit() }
            }
            return true
        }
    }
}
