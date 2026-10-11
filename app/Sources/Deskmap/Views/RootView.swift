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
    /// Pencere boyutu ve sol kenar çubuğunun genişliği.
    /// Pencere boyutu ekranın kullanılabilir alanına oranlıdır (sabit pt
    /// değil): 1710×1074 pt'lik ekranda ≈ 900×750. Alt/üst sınırlar küçük
    /// ekranda okunurluğu, büyük ekranda gereksiz büyümeyi önler; üst sınır
    /// her zaman ekranın kendisidir (taşma yok).
    static let widthFraction: CGFloat = 0.53
    static let heightFraction: CGFloat = 0.70
    static let minWindowWidth: CGFloat = 660
    static let maxWindowWidth: CGFloat = 1100
    static let minWindowHeight: CGFloat = 480
    static let maxWindowHeight: CGFloat = 900

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
    static let inspectorWidth: CGFloat = 360
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
    static let minMapHeight: CGFloat = 260
    /// Pencerenin ekranın kullanılabilir alanının altında bıraktığı boşluk.
    static let screenMargin: CGFloat = 12

    /// Ölçülen yükseklikler: "top" (üst çubuklar), "inspector" (sağ
    /// sütunun doğal içeriği), "bottom" (alt çubuk). Harita alanı bunlardan
    /// hesaplanır.
    @State private var heights: [String: CGFloat] = [:]

    /// Pencerenin üst kenarından, bulunduğu ekranın kullanılabilir alt
    /// kenarına (Dock ve menü çubuğu hariç) kadar olan yükseklik, eksi
    /// `screenMargin`. `WindowRoomReader` pencere ekran değiştirince ya da
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
    /// `inspector`: haritanın yanındaki sağ sütunun doğal yüksekliği.
    ///
    /// - Panel kapalıyken pencere `preferredTotal` olur (sığarsa).
    /// - Panel açılınca pencere aşağı uzar, harita daralmaz.
    /// - Sağ sütun uzunsa harita satırı (sütun onun yanında) en çok alanın
    ///   kalanı kadar uzar; sütun yalnız ekran dolunca kendi içinde kayar.
    /// - Sığmazsa önce harita taşan kadar kısalır, en az `minMapHeight`
    ///   (çok küçük ekranda alanın yarısı) kalır; panel yine sığmazsa
    ///   `panelCap` yüksekliğinde kendi içinde kayar.
    ///
    /// Sonuç her zaman: chrome + map + min(panel, panelCap) ≤ room.
    nonisolated static func heights(chrome: CGFloat, panel: CGFloat, room: CGFloat,
                                    preferredTotal: CGFloat, inspector: CGFloat = 0)
        -> (map: CGFloat, panelCap: CGFloat?) {
        let preferred = max(preferredTotal - chrome, inspector)
        let space = max(room - chrome, 0)
        let map = max(min(preferred, max(space - panel, min(minMapHeight, space / 2))), 0)
        let left = space - map
        return (map, panel > left ? max(left, 0) : nil)
    }

    /// Shots modunda sabit oda (gerçek ekran ve pencere konumu kullanılmaz).
    @Environment(\.demoRoom) private var demoRoom

    /// Ölçüm gelene dek ana ekrana göre tahmin.
    private var currentRoom: WindowRoom {
        if let demoRoom { return demoRoom }
        if let room { return room }
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 860)
        return WindowRoom(height: visible.height - Self.screenMargin, visible: visible)
    }

    private var windowWidth: CGFloat { Self.windowWidth(visibleWidth: currentRoom.visible.width) }
    private var totalWidth: CGFloat { Self.totalWidth(visibleWidth: currentRoom.visible.width) }

    private var layoutHeights: (map: CGFloat, panelCap: CGFloat?) {
        let room = currentRoom
        return Self.heights(chrome: (heights["top"] ?? 90) + (heights["bottom"] ?? 36),
                            panel: 0,
                            room: room.height,
                            preferredTotal: Self.preferredHeight(visibleHeight: room.visible.height),
                            inspector: heights["inspector"] ?? 0)
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
            title: window.title, document: window.document) != nil
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
                        SetupDifferenceTray(mode: mode)
                        // İki sekmede de: sahipsizlik kurulumdan bağımsız.
                        UnownedWindowsTray(mode: mode)
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
                    if permission.isTrusted
                        && (!SkyLight.shared.canMove || router.moveHealth.state == .degraded) {
                        ReducedModeCard(canMove: SkyLight.shared.canMove) { router.retryMoves() }
                    }
                    if !MacSettings.allRequiredOK(settingChecks) || !store.document.setupNoticeDismissed {
                        SetupCard(checks: settingChecks)
                    }
                    if permission.isTrusted && store.document.rules.isEmpty
                        && router.sessionPins.isEmpty {
                        FirstStepsCard()
                    }
                    ScreenMapView(mode: mode)
                }
                .padding(14)
                .background(EnclosingScrollViewReader { ui.autoScroll.scrollView = $0 })
            }
            .reportsViewport("map")
            .onChange(of: ui.reveal) { request in
                guard let request else { return }
                // Panel açılınca harita daralır; yerleşim bittikten sonra kaydır.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(WindowAnchor(id: request.window), anchor: .center)
                    }
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
                // değişmez (sütun yana kaymasın); yüksekliği ölçülür, pencere
                // önce uzar, sütun yalnız ekran dolunca kayar.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id(Self.inspectorTop)
                            inspector
                        }
                        .frame(width: Self.inspectorWidth - (legacyScrollers ? Self.scrollerGutter : 0),
                               alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .measuresHeight("inspector")
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
        .onPreferenceChange(HeightPreference.self) { heights = $0 }
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
        .onReceive(screens.$screens) { _ in
            syncScreens()
            // Monitör takılıp çıkarıldığında seçici gerçek modu izler
            // (pencere bir kez oluşturulduğu için onAppear yeniden gelmez).
            if liveMode != screens.mode {
                liveMode = screens.mode
                mode = screens.mode
            }
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
            // Sürükleme sürerken sekme değişti: kaynağı görünümden kalkan jestin
            // bitişi gelmez; hayalet, donmuş liste ve kaydırma kalmasın.
            ui.drag = nil
            // Harita açılışı canlı sekmeye geçirdiyse öndeki pencere şimdi seçilir.
            selectFrontWindow(in: router.windows,
                              reapply: Date().timeIntervalSince(mapShownAt) < 0.5)
        }
        .onChange(of: ui.windows) { windows in
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
        [store.undoBuffer.expiry,
         router.status.lastActionAt.map { $0.addingTimeInterval(Self.actionFade) }]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }

    /// Son işlem hâlâ gösterilecek kadar yeni mi?
    private var recentAction: String? {
        guard let action = router.status.lastAction, let at = router.status.lastActionAt,
              now.timeIntervalSince(at) < Self.actionFade else { return nil }
        return action
    }

    /// Harita açıldı: önceki açılıştan kalan panel kapanır, kullanıcının en
    /// son tıkladığı pencere satırına tıklanmış gibi seçilir ve görünür
    /// yere kaydırılır. Öndeki pencere yoksa (masaüstü, penceresiz uygulama)
    /// yalnız panel kapanır.
    private func showFrontWindow() {
        ui.panel = nil
        ui.panelSourceWindowID = nil
        mapShownAt = Date()
        pendingFront = AX.frontWindowID().map { ($0, Date().addingTimeInterval(2), false) }
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
            appName: window.appName, title: window.title, document: window.document)?.rule
        ui.panel = UIState.openingPanel(for: window, sessionPinned: sessionPinned,
                                        ruleID: rule?.id)
        ui.panelSourceWindowID = sessionPinned || rule == nil ? nil : window.id
        if let placement = window.placement {
            let group = window.bundleID.isEmpty ? window.appName : window.bundleID
            ui.collapsed.remove("\(placement.screen)|\(placement.desktop)|\(group)")
        }
        revealSeq += 1
        ui.reveal = RevealRequest(window: window.id, seq: revealSeq)
        Log.app.notice("Map opened on front window \(window.id) (\(window.appName, privacy: .public))")
    }

    private func syncScreens() {
        store.remember(screens.screens.map(\.known))
        ui.desktopCounts = Router.desktopCounts(screens: screens.screens)
    }

    // MARK: - Ayrıntı sütunu

    private static let inspectorTop = "inspectorTop"

    /// Çoklu seçim çubuğu mu gösteriliyor.
    private var showsMultiPin: Bool { !ui.selection.isEmpty && mode == screens.mode }

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
                Text(store.document.enabled ? L("Deskmap on") : L("Paused"))
                    .foregroundStyle(store.document.enabled ? Color.primary : Color.orange)
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
                if !ui.search.trimmingCharacters(in: .whitespaces).isEmpty {
                    let hits = ui.windows.filter {
                        UIState.matches(query: ui.search, appName: $0.appName, title: $0.title)
                    }.count
                    Text(hits == 1 ? L("1 match") : L("%ld matches", hits))
                        .font(.caption)
                        .foregroundStyle(hits == 0 ? Color.orange : Color.secondary)
                    Button {
                        ui.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Clear the search"))
                    .accessibilityLabel(L("Clear the search"))
                }
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
            .help(L("Visual shows a small picture of each desktop next to its windows"))

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

    /// Seçili planın şu an geçerli olup olmadığı; değilse ne zaman geçerli olacağı.
    @ViewBuilder
    private var planNote: some View {
        if mode == screens.mode {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(L("active now"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
                    ui.panel = nil
                    store.switchProfile(to: profile.id)
                }
            }
            Divider()
            Button(L("New empty profile")) {
                store.addProfile()
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
                    store.copyLayout(from: .undocked, to: .docked)
                }
                .disabled(!store.document.rules.contains { $0.undocked != nil })
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

    private func openSettings(_ tab: SettingsTab = .general) {
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

            if let entry = store.undoBuffer.entry, store.undoBuffer.isVisible(at: now) {
                Button {
                    undo()
                } label: {
                    Label(L("%@ · Undo", entry.label), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .keyboardShortcut("z", modifiers: .command)
                .lineLimit(1)
                .layoutPriority(1)
                .help(L("Undo the last action (⌘Z)"))
            }

            pinSummary
                .layoutPriority(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
        private var tokens: [NSObjectProtocol] = []

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

/// Pencerenin bulunduğu ekranda aşağıya doğru ne kadar yer olduğunu
/// bildirir: pencerenin üst kenarı (menü çubuğunun altı) ile ekranın
/// kullanılabilir alanının alt kenarı arası, eksi pay. Pencere başka ekrana
/// geçince, taşınınca ya da ekran ayarları değişince yeniden ölçer.
struct WindowRoomReader: NSViewRepresentable {

    let margin: CGFloat
    let changed: (WindowRoom) -> Void

    func makeNSView(context: Context) -> NSView { Probe(margin: margin, changed: changed) }
    func updateNSView(_ view: NSView, context: Context) {}

    /// Kullanılabilir yükseklik (saf). Pencere üstü ekranın kullanılabilir
    /// alanının dışındaysa (henüz yerleşmemiş) kullanılabilir üst kenar esas
    /// alınır.
    static func room(windowTop: CGFloat, visible: CGRect, margin: CGFloat) -> CGFloat {
        let top = (visible.minY...visible.maxY).contains(windowTop) ? windowTop : visible.maxY
        return max(top - visible.minY - margin, 0)
    }

    private final class Probe: NSView {
        let margin: CGFloat
        let changed: (WindowRoom) -> Void
        private var last: WindowRoom?
        private var tokens: [NSObjectProtocol] = []

        init(margin: CGFloat, changed: @escaping (WindowRoom) -> Void) {
            self.margin = margin
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didMoveNotification,
                         NSWindow.didBecomeKeyNotification] {
                tokens.append(center.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in self?.measure() })
            }
            tokens.append(center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in self?.measure() })
            measure()
        }

        private func measure() {
            guard let window, let screen = window.screen else { return }
            let room = WindowRoom(
                height: WindowRoomReader.room(windowTop: window.frame.maxY,
                                              visible: screen.visibleFrame, margin: margin),
                visible: screen.visibleFrame.size)
            guard room != last else { return }
            last = room
            Log.app.notice("""
                Map window room: \(Int(room.height)) pt on \(screen.localizedName, privacy: .public) \
                (visible \(Int(room.visible.width))×\(Int(room.visible.height)) pt)
                """)
            // Görünüm güncellemesi sırasında durum değiştirilmesin.
            DispatchQueue.main.async { [changed] in changed(room) }
        }
    }
}
