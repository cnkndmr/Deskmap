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

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ProfileBar()
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    if !permission.isTrusted {
                        PermissionCard()
                    }
                    if !settingChecks.allSatisfy(\.ok) || !store.document.setupNoticeDismissed {
                        SetupCard(checks: settingChecks)
                    }
                    if permission.isTrusted && store.document.rules.isEmpty
                        && router.sessionPins.isEmpty {
                        FirstStepsCard()
                    }
                    ScreenMapView(mode: mode)
                }
                .padding(14)
            }

            bottomPanel

            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 560, height: 640)
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
            // Mission Control'de eklenen/silinen masaüstü haritaya yansısın.
            let counts = Router.desktopCounts(screens: screens.screens)
            if counts != ui.desktopCounts { ui.desktopCounts = counts }
            // Kullanıcı Sistem Ayarları'nda düzeltince kart kendiliğinden güncellensin.
            let checks = MacSettings.checks()
            if checks != settingChecks { settingChecks = checks }
            refreshLoginStatus()
        }
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
            PinPanel(draft: draft, mode: mode)
                .bottomPanelChrome()
        case .rule(let id):
            if let rule = store.rule(id) {
                RulePanel(rule: rule, mode: mode)
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
            .help(store.document.enabled ? "Yönlendirme açık" : "Yönlendirme duraklatıldı")
            .accessibilityLabel(store.document.enabled ? "Yönlendirme açık" : "Yönlendirme duraklatıldı")

            Picker("", selection: $mode) {
                ForEach(Array(Mode.allCases.enumerated()), id: \.element) { index, candidate in
                    Image(systemName: candidate.symbol)
                        .help("\(candidate.title) (⌘\(index + 1))")
                        .accessibilityLabel(candidate.title)
                        .tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .background(modeShortcuts)

            if mode == screens.mode {
                Text("şu an")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Seçili moddaki pin sayısı; geçici pinler moddan bağımsız ama
            // yalnızca şu anki modun haritasında görünür, orada sayılır.
            let pinned = store.document.rules.filter { $0[mode] != nil }.count
            let session = mode == screens.mode ? router.sessionPins.count : 0
            Text((pinned == 0 ? "pin yok" : "\(pinned) pin")
                 + (session > 0 ? " · \(session) geçici" : ""))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help(session > 0
                      ? "\(session) pencere yalnızca bu oturum için pinli (profile yazılmaz)"
                      : "\(mode.title) modunda \(pinned) pin")

            Button {
                router.reapplyAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r", modifiers: .command)
            .help("Pinli pencereleri şimdi yerleştir (⌘R)")
            .accessibilityLabel("Pinli pencereleri şimdi yerleştir")
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
                    Label("\(router.status.unresponsive.joined(separator: ", ")) yanıt vermiyor; geçici olarak atlanıyor",
                          systemImage: "hourglass")
                        .foregroundStyle(.orange)
                        .help("Uygulama Accessibility sorularına yanıt vermedi (donmuş ya da hata ayıklayıcıda). Yanıt verince otomatik olarak yeniden listelenir.")
                } else if let action = recentAction {
                    Label(action, systemImage: "arrow.turn.down.right")
                } else if !SkyLight.shared.isAvailable {
                    Label("Masaüstü taşıma bu macOS'ta kullanılamıyor; yalnızca ekran ve düzen uygulanır",
                          systemImage: "rectangle.on.rectangle.slash")
                        .foregroundStyle(.orange)
                        .help("SkyLight çağrıları bulunamadı. Pencereler doğru ekrana ve düzene oturtulur ama başka masaüstüne taşınmaz.")
                } else {
                    Text(store.document.rules.isEmpty
                         ? "Bir pencereyi pinleyin ya da başka masaüstüne sürükleyin."
                         : "Pinli pencereler yerinde tutulur; diğerlerine dokunulmaz.")
                }
            }
            .lineLimit(1)

            Spacer()

            if let entry = store.undoBuffer.entry, store.undoBuffer.isVisible(at: now) {
                Button {
                    undo()
                } label: {
                    Label("\(entry.label) · Geri al", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .keyboardShortcut("z", modifiers: .command)
                .lineLimit(1)
                .layoutPriority(1)
                .help("Son işlemi geri al (⌘Z)")
            }

            Toggle("Girişte başlat", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: { setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .layoutPriority(1)
                .help(launchAtLoginHelp)

            if loginStatus == .requiresApproval {
                // Kayıt var ama macOS onay bekliyor (Login Items'ta kapalı).
                Button("Onay gerekli") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .foregroundStyle(.orange)
                    .help("System Settings › General › Login Items'ta Space Router'ı açın")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .layoutPriority(1)
            .help("Space Router'dan çık")
            .accessibilityLabel("Space Router'dan çık")
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
            return "macOS oturumu açılınca Space Router başlar"
        }
        return "Girişte bu kopya açılır: \(path). Kalıcı kurulum için /Applications'a kopyalayın."
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
            store.report("Girişte başlatma \(enabled ? "açılamadı" : "kapatılamadı"): \(error.localizedDescription)")
        }
        // Gerçek durumu oku: register sonrası .requiresApproval da olabilir.
        refreshLoginStatus()
    }
}
