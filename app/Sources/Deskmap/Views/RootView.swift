import AppKit
import ServiceManagement
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
    /// "Girişte başlat" kaydının gerçek durumu; her taramada ve kayıt
    /// değişince yeniden okunur (kullanıcı Sistem Ayarları'ndan kapatabilir).
    @State private var loginStatus: SMAppService.Status = SMAppService.mainApp.status
    /// Sürükleme sırasında gelen tarama sonucu; sürükleme bitince uygulanır.
    @State private var pendingWindows: [Router.WindowSnapshot]?
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

    /// Sol kenar çubuğu genişliği (saf): pencerenin üçte birine yakın.
    nonisolated static func sidebarWidth(windowWidth: CGFloat) -> CGFloat {
        min(max(windowWidth * 0.32, 220), 300)
    }
    /// Alt panel açıkken bile haritaya kalan en az yükseklik.
    static let minMapHeight: CGFloat = 260
    /// Pencerenin ekranın kullanılabilir alanının altında bıraktığı boşluk.
    static let screenMargin: CGFloat = 12

    /// Ölçülen yükseklikler: "top" (üst çubuklar), "panel" (alt panel),
    /// "bottom" (alt çubuk). Harita alanı bunlardan hesaplanır.
    @State private var heights: [String: CGFloat] = [:]

    /// Pencerenin üst kenarından, bulunduğu ekranın kullanılabilir alt
    /// kenarına (Dock ve menü çubuğu hariç) kadar olan yükseklik, eksi
    /// `screenMargin`. `WindowRoomReader` pencere ekran değiştirince ya da
    /// çözünürlük değişince yeniler; bilinmiyorsa nil.
    @State private var room: WindowRoom?

    /// Harita alanı (kenar çubuğu + harita) ve alt panelin tavanı (saf).
    /// `room`: pencereye düşen toplam yükseklik; `chrome`: üst ve alt
    /// çubuklar; `panel`: panelin doğal yüksekliği (kapalıysa 0).
    ///
    /// - Panel kapalıyken pencere `preferredTotal` olur (sığarsa).
    /// - Panel açılınca pencere aşağı uzar, harita daralmaz.
    /// - Sığmazsa önce harita taşan kadar kısalır, en az `minMapHeight`
    ///   (çok küçük ekranda alanın yarısı) kalır; panel yine sığmazsa
    ///   `panelCap` yüksekliğinde kendi içinde kayar.
    ///
    /// Sonuç her zaman: chrome + map + min(panel, panelCap) ≤ room.
    nonisolated static func heights(chrome: CGFloat, panel: CGFloat, room: CGFloat,
                                    preferredTotal: CGFloat)
        -> (map: CGFloat, panelCap: CGFloat?) {
        let preferred = preferredTotal - chrome
        let space = max(room - chrome, 0)
        let map = max(min(preferred, max(space - panel, min(minMapHeight, space / 2))), 0)
        let left = space - map
        return (map, panel > left ? max(left, 0) : nil)
    }

    /// Ölçüm gelene dek ana ekrana göre tahmin.
    private var currentRoom: WindowRoom {
        if let room { return room }
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 860)
        return WindowRoom(height: visible.height - Self.screenMargin, visible: visible)
    }

    private var windowWidth: CGFloat { Self.windowWidth(visibleWidth: currentRoom.visible.width) }

    private var layoutHeights: (map: CGFloat, panelCap: CGFloat?) {
        let room = currentRoom
        return Self.heights(chrome: (heights["top"] ?? 90) + (heights["bottom"] ?? 36),
                            panel: heights["panel"] ?? 0,
                            room: room.height,
                            preferredTotal: Self.preferredHeight(visibleHeight: room.visible.height))
    }

    /// Sürüklerken: pinli pencere bırakılınca kaydedilen hedef güncellenir,
    /// pinsiz pencere yalnız bir kez taşınır.
    private var dragHint: String? {
        guard case .window(let id)? = ui.drag?.item,
              let window = ui.windows.first(where: { $0.id == id }) else { return nil }
        let pinned = Routing.select(
            rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
            windowID: id, bundleID: window.bundleID, appName: window.appName,
            title: window.title) != nil
        return pinned
            ? L("Pinned: dropping it updates the saved desktop.")
            : L("Not pinned: dropping it moves the window once; nothing is saved.")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Tek profil varken çubuk gizli; yeni profil / içe aktarma
            // üst çubuktaki menüde.
            if store.profiles.count > 1 {
                ProfileBar()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider()
            }
            .measuresHeight("top")

            HStack(spacing: 0) {
                // Sol: kurulumlar arası farklar ve sahipsiz pencereler; hep
                // görünür, buradan haritaya yana doğru sürüklenir.
                ScrollView {
                    VStack(spacing: 10) {
                        SetupDifferenceTray(mode: mode)
                        if mode == screens.mode {
                            UnownedWindowsTray(mode: mode)
                        }
                    }
                    .padding(12)
                    // Uzun içerik (çip + yer) sütunu yana taşırmasın.
                    .frame(width: Self.sidebarWidth(windowWidth: windowWidth))
                }
                .frame(width: Self.sidebarWidth(windowWidth: windowWidth))
                .reportsViewport("sidebar")

                Divider()

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
                    if let hint = dragHint {
                        Label(hint, systemImage: "hand.draw")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ScreenMapView(mode: mode)
                }
                .padding(14)
                .background(EnclosingScrollViewReader { ui.autoScroll.scrollView = $0 })
            }
            .reportsViewport("map")
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
            .frame(height: layoutHeights.map)

            // Panel haritadan yer almaz: pencere aşağı doğru uzar. Ekrana
            // sığmazsa kendi içinde kayar (doğal boyu içeride ölçülür).
            if let cap = layoutHeights.panelCap {
                ScrollView {
                    bottomPanel
                        .measuresHeight("panel")
                }
                .frame(height: cap)
            } else {
                bottomPanel
                    .measuresHeight("panel")
            }

            VStack(spacing: 0) {
                Divider()
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .measuresHeight("bottom")
        }
        .frame(width: windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(HeightPreference.self) { heights = $0 }
        .background(WindowRoomReader(margin: Self.screenMargin) { room = $0 })
        .background(.regularMaterial)
        .onAppear {
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
            // Kullanıcı Sistem Ayarları'nda düzeltince kart kendiliğinden güncellensin.
            let checks = MacSettings.checks()
            if checks != settingChecks { settingChecks = checks }
            refreshLoginStatus()
        }
        // Mission Control'de eklenen/silinen masaüstü haritaya yansısın;
        // pencere listesi değişmese de (Router ayrı yayınlar).
        .onReceive(router.$desktopCounts) { counts in
            guard !counts.isEmpty, counts != ui.desktopCounts else { return }
            ui.desktopCounts = counts
        }
        .background(WindowVisibilityObserver { router.setMapVisible($0) })
        .onChange(of: ui.drag == nil) { idle in
            guard idle, let pending = pendingWindows else { return }
            ui.windows = pending
            pendingWindows = nil
        }
        .onChange(of: mode) { _ in
            ui.panel = nil
        }
        .onChange(of: ui.windows) { windows in
            // Taslağın ya da geçici pinin penceresi kapandıysa paneli kapat.
            switch ui.panel {
            case .pin(let draft) where !windows.contains(where: { $0.id == draft.window.id }):
                ui.panel = nil
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

    private func syncScreens() {
        store.remember(screens.screens.map(\.known))
        ui.desktopCounts = Router.desktopCounts(screens: screens.screens)
    }

    // MARK: - Alt panel

    /// Açık panele göre içerik; pin taslağı yalnızca şu anki modda anlamlı.
    @ViewBuilder
    private var bottomPanel: some View {
        switch ui.panel {
        case .pin(let draft) where mode == screens.mode:
            // Kimlik pencereye bağlı: başka pencereye geçince @State
            // (başlık parçaları, düzen) eski pencereden kalmasın.
            PinPanel(draft: draft, mode: mode)
                .id(draft.window.id)
                .bottomPanelChrome()
        case .rule(let id):
            if let rule = store.rule(id) {
                // Kimlik kurala bağlı: başka kurala geçince parça seçimi
                // eski kuraldan kalmasın (macOS 13 onChange'i eski
                // gövdenin kapanışını çağırıp eski başlığı geri yazıyordu).
                RulePanel(rule: rule, mode: mode)
                    .id(rule.id)
                    .bottomPanelChrome()
            }
        case .session(let id):
            if let window = ui.windows.first(where: { $0.id == id }),
               let destination = router.sessionPins[id] {
                SessionPinPanel(window: window, destination: destination)
                    .bottomPanelChrome()
            }
        case .profile:
            ProfilePanel()
                .bottomPanelChrome()
        default:
            EmptyView()
        }
    }

    // MARK: - Üst çubuk

    private var header: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $store.document.enabled) {
                Image(systemName: "power")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(store.document.enabled ? L("Routing on") : L("Routing paused"))
            .accessibilityLabel(store.document.enabled ? L("Routing on") : L("Routing paused"))

            Picker("", selection: $mode) {
                ForEach(Array(Mode.allCases.enumerated()), id: \.element) { index, candidate in
                    Image(systemName: candidate.symbol)
                        .help(candidate.title + " (⌘\(index + 1))")
                        .accessibilityLabel(candidate.title)
                        .tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .background(modeShortcuts)

            if mode == screens.mode {
                Text(L("now"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Onay penceresi yok: menü çubuğu penceresinde sheet'in düğmesine
            // basılınca pencere kapanıyor ve eylem düşüyordu. Diğer yıkıcı
            // işlemler gibi alt çubuktaki "Geri al" ile korunur.
            if mode == .docked {
                Button {
                    store.copyLayout(from: .undocked, to: .docked)
                } label: {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!store.document.rules.contains { $0.undocked != nil })
                .help(L("Copy the Laptop only layout here; the current Monitor connected setup is replaced (⌘Z undoes)"))
                .accessibilityLabel(L("Copy the Laptop only layout here"))
            }

            Spacer()

            if store.profiles.count <= 1 {
                Menu {
                    Button(L("New empty profile")) {
                        store.addProfile()
                        ui.panel = .profile
                    }
                    Button(L("Import a profile from a file (.deskmap.json)")) {
                        ui.panel = nil
                        ProfileFiles.importProfile(into: store)
                    }
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Profiles: each one is a separate set of pins"))
                .accessibilityLabel(L("Profiles: each one is a separate set of pins"))
            }

            // Seçili moddaki pin sayısı; geçici pinler moddan bağımsız ama
            // yalnızca şu anki modun haritasında görünür, orada sayılır.
            let pinned = store.document.rules.filter { $0[mode] != nil }.count
            let session = mode == screens.mode ? router.sessionPins.count : 0
            let pinText = pinned == 0 ? L("no pins")
                : pinned == 1 ? L("1 pin") : L("%ld pins", pinned)
            Text(session > 0 ? L("%@ · %ld temporary", pinText, session) : pinText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help(session == 0
                      ? L("Pins in %@ mode: %ld", mode.title, pinned)
                      : session == 1
                        ? L("1 window is pinned for this session only (not saved to the profile)")
                        : L("%ld windows are pinned for this session only (not saved to the profile)", session))

            Button {
                router.reapplyAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
            .help(L("Place pinned windows now (⌘R)"))
            .accessibilityLabel(L("Place pinned windows now"))
        }
    }

    /// ⌘1 / ⌘2 seçicideki sırayla modu seçer. Görünmez, boyutsuz düğmeler;
    /// pencere önde olduğu sürece kısayollar çalışır.
    private var modeShortcuts: some View {
        HStack(spacing: 0) {
            ForEach(Array(Mode.allCases.enumerated()), id: \.element) { index, candidate in
                Button("") { mode = candidate }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Alt çubuk

    /// Soldaki durum metni, sağda (varsa) geri alma bağlantısı ve düğmeler.
    /// Geri alma durum metninden bağımsızdır: hata ya da yanıt vermeyen
    /// uygulama iletisi onu gizlemez; yer darsa önce durum metni kısalır.
    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if let error = store.lastError {
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

            Toggle(L("Launch at login"), isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: { setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .layoutPriority(1)
                .help(launchAtLoginHelp)

            if loginStatus == .requiresApproval {
                // Kayıt var ama macOS onay bekliyor (Login Items'ta kapalı).
                Button(L("Approval needed")) { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .foregroundStyle(.orange)
                    .help(L("Turn on Deskmap in System Settings › General › Login Items"))
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .layoutPriority(1)
            .help(L("Quit Deskmap"))
            .accessibilityLabel(L("Quit Deskmap"))
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

    // MARK: - Girişte başlat

    /// Bu kopya /Applications dışındaysa (build/ içinden çalışıyorsa)
    /// girişte bu yol açılır; taşınır ya da silinirse kayıt boşa düşer.
    private var launchAtLoginHelp: String {
        let path = Bundle.main.bundleURL.path
        if path.hasPrefix("/Applications/") {
            return L("Deskmap starts when you log in to macOS")
        }
        return L("This copy opens at login: %@. For a permanent install, copy it to /Applications.", path)
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        if status != loginStatus { loginStatus = status }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            store.report(enabled
                ? L("Could not turn on launch at login: %@", error.localizedDescription)
                : L("Could not turn off launch at login: %@", error.localizedDescription))
        }
        // Gerçek durumu oku: register sonrası .requiresApproval da olabilir.
        refreshLoginStatus()
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
