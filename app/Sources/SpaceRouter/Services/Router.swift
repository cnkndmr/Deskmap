import AppKit
import Combine

/// Yönlendirme motoru. Pencere olaylarında (yeni pencere, başlık, odak,
/// masaüstü geçişi) ve yedek olarak düzenli aralıklarla açık pencereleri
/// tarar; kurala uyanları doğru ekranın doğru masaüstüne taşıyıp düzene
/// oturtur. Düzen, pencere gerçekten hedefe oturana kadar yeniden denenir.
///
/// Tarama arka planda çalışır; arayüz yalnızca özet durumu görür.
@MainActor
final class Router: ObservableObject {

    struct Placement: Equatable, Hashable {
        let screen: String
        let desktop: Int
    }

    /// Arayüzde gösterilen pencere anlık görüntüsü; her taramada yenilenir.
    struct WindowSnapshot: Identifiable, Equatable, Hashable {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let bundleID: String
        let title: String
        /// Bulunduğu ekran ve masaüstü (tam ekran ya da bilinmiyorsa nil).
        let placement: Placement?
        /// AX koordinatlarında (sol üst köşe tabanlı) çerçeve.
        let frame: CGRect?
        let isMinimized: Bool
    }

    struct Status: Equatable {
        var routedWindows = 0
        var lastAction: String?
        var lastActionAt: Date?
        /// Accessibility'ye yanıt vermediği için geçici olarak atlanan uygulamalar.
        var unresponsive: [String] = []
    }

    @Published private(set) var status = Status()
    /// Son taramada görülen pencereler (uygulama adı, sonra kimlik sırasında).
    @Published private(set) var windows: [WindowSnapshot] = []
    /// Oturum pinleri: pencere kimliğine (CGWindowID) bağlı, diske
    /// yazılmayan hedefler. Başlığı değişmeyen ama farklı pencereler açan
    /// uygulamalar için "sadece bu pencere" seçeneği. Pencere kapanınca
    /// (birkaç tarama boyunca görünmeyince) kendiliğinden silinir; moddan
    /// bağımsızdır, hedef ekran bağlı değilse o an uygulanmaz.
    @Published private(set) var sessionPins: [CGWindowID: Destination] = [:]
    /// Oturum pinlerinin diske yazılan kaydı (pencere yaşadığı sürece
    /// uygulama yeniden başlasa da geri yüklenir).
    private var sessionRecords: [CGWindowID: SessionPin] = [:]
    /// Oturum pini olan pencerenin pencere sunucusunda art arda kaç
    /// taramada görülmediği.
    private var sessionMisses: [CGWindowID: Int] = [:]
    /// Bu kadar ardışık taramada pencere sunucusunda da yoksa pin düşer.
    private static let sessionMissLimit = 3
    /// Oturum pinleri dosyası; pencere numarası + sahip pid ile eşlenir.
    /// Pencere numaraları ve pid'ler yeniden başlatmada değiştiği için
    /// eski kayıtlar açılışta kendiliğinden elenir.
    static let sessionFileURL = Store.directoryURL.appendingPathComponent("session-pins.json")

    /// Diske yazılan oturum pini kaydı.
    struct SessionPin: Codable, Equatable {
        var windowID: CGWindowID
        var pid: pid_t
        var bundleID: String
        var appName: String
        var title: String
        var destination: Destination
    }

    private let store: Store
    private let screens: ScreenService
    private let events: WindowEvents
    private let queue = DispatchQueue(label: "spacerouter.router", qos: .utility)
    // nonisolated(unsafe): ikisi de yalnızca init'te (ana aktör) doldurulur,
    // deinit'te kapatılır; `Timer` ve gözlemci belirteci Sendable olmadığı
    // için deinit erişimi başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    nonisolated(unsafe) private var sleepTokens: [NSObjectProtocol] = []

    /// (pencere, hedef) çiftleri için düzen bir kez uygulanır; kullanıcı
    /// sonradan pencereyi elle taşırsa yerinden oynatılmaz.
    private var applied: Set<String> = []
    /// (pencere, hedef) başına kaç kez düzen / masaüstü taşıması denendi;
    /// uygulama kabul etmezse belirli sayıdan sonra vazgeçilir.
    private var attempts: [String: Int] = [:]
    /// Masaüstü taşıması anahtarı başına son deneme zamanı; sınıra varılmış
    /// taşıma bir süre sonra yeniden tur alır (`Routing.recordMoveAttempt`).
    /// `attempts` ile birlikte budanır.
    private var lastAttempts: [String: Date] = [:]
    private var isSweeping = false
    private var sweepRequested = false
    /// Ekranlar ya da sistem uyurken tarama yapılmaz; uyanınca hemen taranır.
    private var isPaused = false
    /// Tarama sürerken gelen "düzen belleğini unut" istekleri: tarama
    /// bitince sonucun üstüne uygulanır; yoksa taramanın döndürdüğü eski
    /// küme bu istekleri ezerdi (ör. "Yeniden yerleştir" düğmesi).
    private var invalidatedPrefixes: Set<String> = []
    private var invalidateAll = false
    private var followUp: Task<Void, Never>?

    init(store: Store, screens: ScreenService) {
        self.store = store
        self.screens = screens
        self.events = WindowEvents()
        // Ayrıca ayarlanmamış bütün AX öğeleri için varsayılan yanıt süresi
        // (yoksa ~6 sn; donmuş bir uygulama taramayı o kadar bekletirdi).
        AX.setGlobalTimeout(1.0)
        let sky = SkyLight.shared
        Log.skylight.notice("""
            SkyLight \(sky.isAvailable ? "hazır" : "yok", privacy: .public); \
            masaüstü taşıma yolu: \(sky.movePath, privacy: .public)
            """)
        loadSessionPins()

        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.events.refresh()
                self?.sweep()
            }
        }
        // Sistem zamanlayıcıları gruplayabilsin (güç tüketimi); 2 sn ± 0,5 sn yeter.
        timer.tolerance = 0.5
        self.timer = timer

        // Pencere olayları: art arda gelenleri tek taramada topla.
        events.changed
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.sweep() }
            .store(in: &cancellables)

        screens.settled
            .sink { [weak self] in self?.reapplyAll() }
            .store(in: &cancellables)

        store.$document
            .map(\.rules)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reapplyAll() }
            .store(in: &cancellables)

        // Ekranlar / sistem uyurken tarama durur (pencere sunucusu ve
        // uygulamalar yanıt vermez, boşuna IPC); uyanınca hemen bir tur.
        let center = NSWorkspace.shared.notificationCenter
        // `Notification` Sendable değil; ana aktöre yalnızca adı taşınır.
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            sleepTokens.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                let reason = note.name.rawValue
                Task { @MainActor in self?.setPaused(true, reason: reason) }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            sleepTokens.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                let reason = note.name.rawValue
                Task { @MainActor in self?.setPaused(false, reason: reason) }
            })
        }
    }

    deinit {
        timer?.invalidate()
        followUp?.cancel()
        for token in sleepTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    private func setPaused(_ paused: Bool, reason: String) {
        guard paused != isPaused else { return }
        isPaused = paused
        Log.screens.notice("""
            Tarama \(paused ? "duraklatıldı" : "sürdürülüyor", privacy: .public) (\(reason, privacy: .public))
            """)
        if !paused { sweep() }
    }

    /// Düzen belleğini sıfırlayıp bütün pencereleri yeniden yerleştirir.
    func reapplyAll() {
        applied.removeAll()
        attempts.removeAll()
        lastAttempts.removeAll()
        if isSweeping { invalidateAll = true }
        sweep()
    }

    // MARK: - Oturum pinleri

    /// Bu pencereyi (kimliğiyle) pencere kapanana kadar hedefte tutar.
    /// Kayıt diske yazılır; Space Router yeniden başlarsa pencere hâlâ
    /// açıksa pin geri gelir.
    func pinSession(_ windowID: CGWindowID, destination: Destination) {
        let snapshot = windows.first { $0.id == windowID }
        let previous = sessionRecords[windowID]
        sessionRecords[windowID] = SessionPin(
            windowID: windowID,
            pid: snapshot?.pid ?? previous?.pid ?? 0,
            bundleID: snapshot?.bundleID ?? previous?.bundleID ?? "",
            appName: snapshot?.appName ?? previous?.appName ?? "",
            title: snapshot?.title ?? previous?.title ?? "",
            destination: destination)
        sessionPins[windowID] = destination
        sessionMisses[windowID] = nil
        forgetApplied(for: windowID)
        saveSessionPins()
        sweep()
    }

    func unpinSession(_ windowID: CGWindowID) {
        guard sessionPins.removeValue(forKey: windowID) != nil else { return }
        sessionRecords[windowID] = nil
        sessionMisses[windowID] = nil
        forgetApplied(for: windowID)
        saveSessionPins()
    }

    /// Masaüstü sıralaması değişince bu ekrandaki oturum pinlerinin masaüstü
    /// numaraları da kurallarla aynı haritaya göre kayar (moddan bağımsız).
    func moveDesktop(on screen: String, from: Int, to: Int, count: Int) {
        guard let mapping = Document.desktopMapping(from: from, to: to, count: count)
        else { return }
        var changed = false
        for (id, record) in sessionRecords
        where record.destination.screen == screen {
            guard let updated = mapping[record.destination.desktop],
                  updated != record.destination.desktop else { continue }
            var next = record
            next.destination.desktop = updated
            sessionRecords[id] = next
            sessionPins[id] = next.destination
            forgetApplied(for: id)
            changed = true
        }
        if changed {
            saveSessionPins()
            sweep()
        }
    }

    /// Açılışta: kayıtlı oturum pinlerinden penceresi hâlâ (aynı pid ile)
    /// pencere sunucusunda olanlar geri yüklenir, kalanı atılır.
    private func loadSessionPins() {
        guard let data = try? Data(contentsOf: Self.sessionFileURL),
              let records = try? JSONDecoder().decode([SessionPin].self, from: data)
        else { return }
        let live = AX.liveWindowIDs()
        var restored: [CGWindowID: SessionPin] = [:]
        for record in records where live[record.windowID] == record.pid {
            restored[record.windowID] = record
        }
        sessionRecords = restored
        sessionPins = restored.mapValues(\.destination)
        if restored.count != records.count { saveSessionPins() }
    }

    private func saveSessionPins() {
        do {
            try FileManager.default.createDirectory(
                at: Store.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let records = sessionRecords.values.sorted { $0.windowID < $1.windowID }
            try encoder.encode(records).write(to: Self.sessionFileURL, options: .atomic)
        } catch {
            store.report("session-pins.json yazılamadı: \(error.localizedDescription)")
        }
    }

    /// Bir pencerenin düzen belleğini sıfırlar; hedefi değişince yeniden
    /// yerleştirilsin.
    private func forgetApplied(for windowID: CGWindowID) {
        let prefix = "\(windowID)|"
        applied = applied.filter { !$0.hasPrefix(prefix) }
        attempts = attempts.filter { !$0.key.hasPrefix(prefix) }
        lastAttempts = lastAttempts.filter { !$0.key.hasPrefix(prefix) }
        if isSweeping { invalidatedPrefixes.insert(prefix) }
    }

    /// Kısa bir süre sonra yeniden tara (masaüstü taşıması yerleşsin diye).
    private func scheduleFollowUp(after milliseconds: UInt64) {
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.sweep()
        }
    }

    // MARK: - Elle taşıma

    /// Pinsiz bir pencereyi tek seferlik hedef masaüstüne taşır; kural
    /// yazılmaz. Ekran değişiyorsa ve pencere görünürse çerçeve önce hedef
    /// ekranda aynı oranlara taşınır (görünmeyen pencereye AX çerçeve
    /// uygulanmadığından o durumda yalnızca masaüstü değişir).
    func moveWindow(_ windowID: CGWindowID, to placement: Placement) {
        let connected = screens.screens
        // Son taramadaki pid ile AX öğesi doğrudan üretilir; bütün
        // uygulamaları yeniden taramak yalnızca bu yol tutmazsa gerekir.
        let snapshot = windows.first { $0.id == windowID }
        queue.async { [weak self] in
            let sky = SkyLight.shared
            guard sky.isAvailable,
                  let target = connected.first(where: { $0.id == placement.screen }),
                  let display = sky.displaySpaces(mainUUID: Self.primaryUUID(connected))
                    .first(where: { $0.displayUUID == target.uuid }),
                  !display.desktops.isEmpty
            else { return }
            let desktops = display.desktops
            let index = min(placement.desktop, desktops.count)
            let space = desktops[index - 1]

            var window: AXWindow?
            var frame: CGRect?
            if let snapshot, let element = AX.element(pid: snapshot.pid, windowID: windowID) {
                AXUIElementSetMessagingTimeout(element, 1.0)
                let direct = AXWindow(
                    id: windowID, pid: snapshot.pid, appName: snapshot.appName,
                    bundleID: snapshot.bundleID, title: snapshot.title, element: element)
                if let directFrame = AX.frame(of: direct) {
                    window = direct
                    frame = directFrame
                }
            }
            if frame == nil, let scanned = AX.allWindows().first(where: { $0.id == windowID }) {
                window = scanned
                frame = AX.frame(of: scanned)
            }

            if let window, let frame,
               let source = connected.first(where: { screen in
                   Coordinates.axRect(fromCocoa: screen.frame, screens: connected)
                       .contains(CGPoint(x: frame.midX, y: frame.midY))
               }),
               source.id != target.id {
                let sourceArea = Coordinates.axRect(fromCocoa: source.visibleFrame, screens: connected)
                let targetArea = Coordinates.axRect(fromCocoa: target.visibleFrame, screens: connected)
                let layout = WindowLayout(frame: frame, in: sourceArea)
                AX.setFrame(layout.rect(in: targetArea), of: window)
            }

            let appName = window?.appName ?? snapshot?.appName ?? "?"
            Log.routing.info("""
                Elle taşıma: \(appName, privacy: .public) [\(windowID)] → \
                \(target.name, privacy: .public) · Masaüstü \(index)
                """)
            if !sky.move(window: windowID, to: space.id) {
                Log.routing.error("Elle taşıma başarısız: SkyLight taşıma yolu yok (pencere \(windowID))")
            }
            Task { @MainActor in self?.scheduleFollowUp(after: 200) }
        }
    }

    // MARK: - Tarama

    private func sweep() {
        guard AXIsProcessTrusted(), !isPaused else { return }
        if isSweeping {
            // Tarama sürerken gelen olay kaybolmasın; bitince bir tur daha.
            sweepRequested = true
            return
        }

        // Duraklatılmışken kural uygulanmaz ama pencereler yine listelenir.
        // Ekran değişimi yatışırken de öyle: yarım düzenlenmiş ekranlara
        // göre taşıma yapılmaz; yatışınca `settled` → `reapplyAll`.
        // Özgüllük sıralamasını `Routing.select` yapar.
        let routing = store.document.enabled && !screens.isSettling
        let rules = routing ? store.document.rules : []
        let sessionPins = routing ? self.sessionPins : [:]
        // Duraklatılmışken de geçici pinli pencereler listelenir ve yaşam
        // denetimi sürer.
        let sessionIDs = Set(self.sessionPins.keys)
        let mode = screens.mode
        let connected = screens.screens
        let applied = self.applied
        let attempts = self.attempts
        let lastAttempts = self.lastAttempts
        isSweeping = true
        sweepRequested = false

        queue.async { [weak self] in
            let outcome = Self.route(rules: rules, sessionPins: sessionPins,
                                     sessionIDs: sessionIDs, mode: mode, screens: connected,
                                     applied: applied, attempts: attempts,
                                     lastAttempts: lastAttempts)
            Task { @MainActor in
                guard let self else { return }
                self.isSweeping = false
                var applied = outcome.applied
                var attempts = outcome.attempts
                var lastAttempts = outcome.lastAttempts
                if self.invalidateAll {
                    applied = []
                    attempts = [:]
                    lastAttempts = [:]
                } else if !self.invalidatedPrefixes.isEmpty {
                    let prefixes = self.invalidatedPrefixes
                    applied = applied.filter { key in
                        !prefixes.contains { key.hasPrefix($0) } }
                    attempts = attempts.filter { entry in
                        !prefixes.contains { entry.key.hasPrefix($0) } }
                    lastAttempts = lastAttempts.filter { entry in
                        !prefixes.contains { entry.key.hasPrefix($0) } }
                }
                self.invalidateAll = false
                self.invalidatedPrefixes = []
                // Kapanmış pencerelerin düzen/deneme kayıtları birikmesin.
                let live = outcome.liveWindows
                if !live.isEmpty {
                    func isLive(_ key: String) -> Bool {
                        guard let end = key.firstIndex(of: "|"),
                              let id = CGWindowID(key[..<end]) else { return true }
                        return live[id] != nil
                    }
                    applied = applied.filter(isLive)
                    attempts = attempts.filter { isLive($0.key) }
                    lastAttempts = lastAttempts.filter { isLive($0.key) }
                }
                self.applied = applied
                self.attempts = attempts
                self.lastAttempts = lastAttempts
                if outcome.snapshots != self.windows { self.windows = outcome.snapshots }
                self.expireSessionPins(live: outcome.liveWindows)
                if outcome.needsFollowUp || self.sweepRequested {
                    self.scheduleFollowUp(after: outcome.needsFollowUp ? 200 : 20)
                }
                var status = self.status
                status.routedWindows = outcome.routed
                status.unresponsive = outcome.unresponsive
                if let action = outcome.lastAction {
                    status.lastAction = action
                    status.lastActionAt = Date()
                }
                if status != self.status { self.status = status }
            }
        }
    }

    private struct Outcome {
        var applied: Set<String>
        var attempts: [String: Int]
        var lastAttempts: [String: Date]
        var snapshots: [WindowSnapshot] = []
        /// Pencere sunucusunun bildiği pencere numaraları → pid (oturum
        /// pinlerinin yaşayıp yaşamadığı buradan anlaşılır).
        var liveWindows: [CGWindowID: pid_t] = [:]
        var unresponsive: [String] = []
        var routed = 0
        var lastAction: String?
        /// Bir pencere taşındı ya da düzeni henüz oturmadı; kısa süre sonra
        /// yeniden dene.
        var needsFollowUp = false
    }

    /// Bir pencerenin taramada bir kez okunan durumu; anlık görüntü,
    /// yerleşim ve yönlendirme aynı okumayı kullanır (pencere başına
    /// space, çerçeve ve simge durumu için tekrar IPC yapılmaz).
    struct WindowState {
        /// Bulunduğu space kimlikleri (SkyLight yoksa boş).
        let spaces: [UInt64]
        /// Space'lerden biri normal masaüstü değil (tam ekran uygulama).
        let isFullscreen: Bool
        let frame: CGRect?
        let isMinimized: Bool
    }

    /// Düzen deneme sınırları `Routing.maxAttempts` / `Routing.quickAttempts`;
    /// masaüstü taşıması `Routing.maxMoveAttempts` / `Routing.moveRetryInterval`.
    nonisolated private static func route(
        rules: [Rule], sessionPins: [CGWindowID: Destination], sessionIDs: Set<CGWindowID>,
        mode: Mode, screens: [ScreenInfo], applied: Set<String>, attempts: [String: Int],
        lastAttempts: [String: Date]
    ) -> Outcome {
        var outcome = Outcome(applied: applied, attempts: attempts, lastAttempts: lastAttempts)
        let sky = SkyLight.shared
        let displays = sky.displaySpaces(mainUUID: Self.primaryUUID(screens))
        let visibleSpaces = Set(displays.map(\.current))
        // Space türleri ekran listesinden; listede olmayan kimlik için IPC.
        let spaceTypes = SkyLight.spaceTypes(of: displays)
        func spaceType(_ id: UInt64) -> Int { spaceTypes[id] ?? sky.type(of: id) }
        // Pencere sunucusu taramada bir kez okunur: 2. aşama listeleme ve
        // yaşam denetimi aynı sonuçtan türer.
        let server = AX.windowServerList()
        let windows = AX.allWindows(alwaysInclude: sessionIDs, server: server)
        outcome.unresponsive = AX.unresponsiveApps()
        // Oturum pinlerinin yaşam denetimi ve kapalı pencere kayıtlarının
        // budanması için. Sunucu listesi AX listesinden önce okunduğu için
        // AX'in gördüğü (yani yaşayan) pencereler de eklenir.
        var live = server.live
        for window in windows where live[window.id] == nil { live[window.id] = window.pid }
        outcome.liveWindows = live

        // Pencere başına durum bir kez okunur.
        var states: [CGWindowID: WindowState] = [:]
        for window in windows {
            let spaces = sky.spaces(of: window.id)
            states[window.id] = WindowState(
                spaces: spaces,
                isFullscreen: spaces.contains { spaceType($0) != 0 },
                frame: AX.frame(of: window),
                isMinimized: AX.isMinimized(window))
        }
        func windowState(_ window: AXWindow) -> WindowState {
            states[window.id] ?? WindowState(spaces: [], isFullscreen: false,
                                             frame: nil, isMinimized: false)
        }

        outcome.snapshots = windows.map { window in
            let state = windowState(window)
            return WindowSnapshot(
                id: window.id, pid: window.pid, appName: window.appName, bundleID: window.bundleID,
                title: window.title,
                placement: Self.placement(of: state, displays: displays, screens: screens),
                frame: state.frame,
                isMinimized: state.isMinimized)
        }.sorted {
            let a = $0.appName.localizedCaseInsensitiveCompare($1.appName)
            return a == .orderedSame ? $0.id < $1.id : a == .orderedAscending
        }

        let now = Date()
        for window in windows {
            // Arayüzle aynı seçim: oturum pini, yoksa bu modda hedefi olan
            // en özgül eşleşen kural.
            guard let match = Routing.select(
                rules: rules, sessionPins: sessionPins, mode: mode, windowID: window.id,
                bundleID: window.bundleID, appName: window.appName, title: window.title)
            else { continue }
            let destination = match.destination
            let ruleID = match.ruleID

            guard let screen = screens.first(where: { $0.id == destination.screen })
            else { continue }

            outcome.routed += 1
            let key = "\(window.id)|\(ruleID)|\(mode.rawValue)|\(destination.hashValue)"
            let state = windowState(window)

            let targetFrame = Coordinates.axRect(
                fromCocoa: destination.layout.rect(in: screen.visibleFrame),
                screens: screens)
            var needsLayout = !outcome.applied.contains(key) && !state.isMinimized

            // Hedef masaüstü ve pencerenin şu anki space durumu.
            var target: SkyLight.Space?
            var onTarget = true
            var isVisible = true
            var desktopLabel = ""
            if sky.isAvailable,
               let display = displays.first(where: { $0.displayUUID == screen.uuid }),
               !display.desktops.isEmpty {
                let desktops = display.desktops
                let index = min(destination.desktop, desktops.count)
                let space = desktops[index - 1]
                let current = state.spaces
                // Tam ekran uygulamaya ait pencerelere dokunulmaz.
                if state.isFullscreen { continue }
                target = space
                onTarget = current.contains(space.id)
                isVisible = current.isEmpty || current.contains(where: visibleSpaces.contains)
                desktopLabel = "\(screen.name) · Masaüstü \(index)"
            }

            // 1. Düzen — pencere yalnızca GÖRÜNÜRKEN uygulanır. Görünmeyen
            // bir masaüstündeki pencereye verilen çerçeve uygulama
            // tarafından işlenmez; düzen "beklemede" kalır ve kullanıcı o
            // masaüstüne geçince (activeSpaceDidChange taraması) verilir.
            // Eski "hop" (pencereyi önce görünen masaüstüne uğratma)
            // kaldırıldı: bulunduğun masaüstünde yabancı pencere beliriyor,
            // Dock'tan uygulamaya geçişte macOS yanlış Space'e gidiyordu.
            if !isVisible { needsLayout = false }

            var placed = false
            if needsLayout {
                if let frame = state.frame, Coordinates.close(frame, targetFrame) {
                    placed = true
                } else {
                    AX.setFrame(targetFrame, of: window)
                    // Uygulama çerçeveyi kabul etti mi? Bu okuma gerekli.
                    if let after = AX.frame(of: window), Coordinates.close(after, targetFrame) {
                        placed = true
                    }
                }

                let previousAttempts = outcome.attempts[key] ?? 0
                if Routing.recordLayoutAttempt(
                    key: key, placed: placed,
                    applied: &outcome.applied, attempts: &outcome.attempts) {
                    outcome.needsFollowUp = true
                }
                if !placed, previousAttempts + 1 >= Routing.maxAttempts {
                    Log.routing.notice("""
                        Düzen vazgeçildi: \(window.appName, privacy: .public) [\(window.id)] \
                        '\(window.title, privacy: .private)' \(Routing.maxAttempts) denemede \
                        \(destination.layout.label, privacy: .public) düzenini almadı
                        """)
                }
            }

            // 2. Masaüstü — çerçeve verildikten sonra; aynı ekrandaki
            // masaüstüler arası taşıma çerçeveyi korur.
            let moveKey = "\(window.id)|move|\(ruleID)|\(mode.rawValue)|\(destination.hashValue)"
            if let target, !onTarget {
                if let count = Routing.recordMoveAttempt(
                    key: moveKey, now: now,
                    attempts: &outcome.attempts, lastAttempts: &outcome.lastAttempts) {
                    let moved = sky.move(window: window.id, to: target.id)
                    Log.routing.info("""
                        \(window.appName, privacy: .public) [\(window.id)] \
                        '\(window.title, privacy: .private)' → \(desktopLabel, privacy: .public) \
                        (deneme \(count)/\(Routing.maxMoveAttempts))
                        """)
                    if !moved {
                        Log.routing.error("SkyLight taşıma yolu yok; pencere \(window.id) taşınamadı")
                    }
                    if count == Routing.maxMoveAttempts {
                        Log.routing.notice("""
                            Taşıma son deneme: \(window.appName, privacy: .public) [\(window.id)] \
                            tutmazsa \(Int(Routing.moveRetryInterval)) sn beklenir
                            """)
                    }
                    if count <= Routing.quickAttempts { outcome.needsFollowUp = true }
                    outcome.lastAction = "\(window.appName) → \(desktopLabel)"
                }
            } else if onTarget {
                outcome.attempts[moveKey] = nil
                outcome.lastAttempts[moveKey] = nil
            }
        }
        return outcome
    }

    /// Pencere sunucusunda artık olmayan (kapanmış) pencerelerin oturum
    /// pinlerini birkaç tarama sonra düşürür. AX listesinde görünmemek
    /// yeterli değildir: başka masaüstündeki pencere AX'te eksik çıkabilir
    /// ama sunucuda durur; pin de durur. Sunucu hiç pencere döndürmediyse
    /// (geçici hata) hiçbir pin düşürülmez.
    private func expireSessionPins(live: [CGWindowID: pid_t]) {
        guard !sessionPins.isEmpty, !live.isEmpty else { return }
        var expired: [CGWindowID] = []
        for id in sessionPins.keys {
            let alive = live[id] != nil
                && (sessionRecords[id].map { $0.pid == 0 || $0.pid == live[id] } ?? true)
            if alive {
                sessionMisses[id] = nil
            } else {
                let misses = (sessionMisses[id] ?? 0) + 1
                sessionMisses[id] = misses
                if misses >= Self.sessionMissLimit { expired.append(id) }
            }
        }
        for id in expired {
            let record = sessionRecords[id]
            Log.routing.notice("""
                Oturum pini düştü: \(record?.appName ?? "?", privacy: .public) [\(id)] \
                '\(record?.title ?? "", privacy: .private)' pencere sunucusunda yok
                """)
            sessionPins[id] = nil
            sessionRecords[id] = nil
            sessionMisses[id] = nil
            forgetApplied(for: id)
        }
        if !expired.isEmpty { saveSessionPins() }
    }

    // MARK: - Yardımcılar

    nonisolated static func primaryUUID(_ screens: [ScreenInfo]) -> String? {
        (screens.first { $0.frame.origin == .zero } ?? screens.first)?.uuid
    }

    /// Pencerenin şu an bulunduğu ekran ve masaüstü sırası. Tam ekran
    /// (ya da başka özel) bir space'teyse nil. Saf: taramada bir kez
    /// okunan `WindowState` ile çalışır, IPC yapmaz.
    nonisolated static func placement(
        of state: WindowState, displays: [SkyLight.DisplaySpaces], screens: [ScreenInfo]
    ) -> Placement? {
        let spaces = state.spaces
        if !spaces.isEmpty {
            if state.isFullscreen { return nil }
            for display in displays {
                guard let screen = screens.first(where: { $0.uuid == display.displayUUID })
                else { continue }
                if let index = display.desktops.firstIndex(where: { spaces.contains($0.id) }) {
                    return Placement(screen: screen.id, desktop: index + 1)
                }
            }
        }
        // Space bilgisi yoksa pencere çerçevesinden ekranı bul.
        if let frame = state.frame {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            for screen in screens {
                let axFrame = Coordinates.axRect(fromCocoa: screen.frame, screens: screens)
                if axFrame.contains(center) {
                    return Placement(screen: screen.id, desktop: 1)
                }
            }
        }
        return screens.first.map { Placement(screen: $0.id, desktop: 1) }
    }

    /// Bağlı ekranlardaki gerçek masaüstü sayıları.
    nonisolated static func desktopCounts(screens: [ScreenInfo]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for display in SkyLight.shared.displaySpaces(mainUUID: primaryUUID(screens)) {
            if let screen = screens.first(where: { $0.uuid == display.displayUUID }) {
                counts[screen.id] = display.desktops.count
            }
        }
        return counts
    }
}
