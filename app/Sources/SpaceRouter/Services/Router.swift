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
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// (pencere, hedef) çiftleri için düzen bir kez uygulanır; kullanıcı
    /// sonradan pencereyi elle taşırsa yerinden oynatılmaz.
    private var applied: Set<String> = []
    /// (pencere, hedef) başına kaç kez düzen denendi; uygulama kabul
    /// etmezse belirli sayıdan sonra vazgeçilir.
    private var attempts: [String: Int] = [:]
    private var isSweeping = false
    private var sweepRequested = false
    private var followUp: Task<Void, Never>?

    init(store: Store, screens: ScreenService) {
        self.store = store
        self.screens = screens
        self.events = WindowEvents()
        loadSessionPins()

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.events.refresh()
                self?.sweep()
            }
        }

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
    }

    deinit {
        timer?.invalidate()
        followUp?.cancel()
    }

    /// Düzen belleğini sıfırlayıp bütün pencereleri yeniden yerleştirir.
    func reapplyAll() {
        applied.removeAll()
        attempts.removeAll()
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
        guard let mapping = Store.desktopMapping(from: from, to: to, count: count)
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
        queue.async { [weak self] in
            let sky = SkyLight.shared
            guard sky.isAvailable,
                  let target = connected.first(where: { $0.id == placement.screen }),
                  let display = sky.displaySpaces(mainUUID: Self.primaryUUID(connected))
                    .first(where: { $0.displayUUID == target.uuid }),
                  !display.desktops.isEmpty
            else { return }
            let desktops = display.desktops
            let space = desktops[min(placement.desktop, desktops.count) - 1]

            if let window = AX.allWindows().first(where: { $0.id == windowID }),
               let frame = AX.frame(of: window),
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

            sky.move(window: windowID, to: space.id)
            Task { @MainActor in self?.scheduleFollowUp(after: 200) }
        }
    }

    // MARK: - Tarama

    private func sweep() {
        guard AXIsProcessTrusted() else { return }
        if isSweeping {
            // Tarama sürerken gelen olay kaybolmasın; bitince bir tur daha.
            sweepRequested = true
            return
        }

        // Duraklatılmışken kural uygulanmaz ama pencereler yine listelenir.
        let rules = store.document.enabled ? store.document.rules.bySpecificity : []
        let sessionPins = store.document.enabled ? self.sessionPins : [:]
        // Duraklatılmışken de geçici pinli pencereler listelenir ve yaşam
        // denetimi sürer.
        let sessionIDs = Set(self.sessionPins.keys)
        let mode = screens.mode
        let connected = screens.screens
        let applied = self.applied
        let attempts = self.attempts
        isSweeping = true
        sweepRequested = false

        queue.async { [weak self] in
            let outcome = Self.route(rules: rules, sessionPins: sessionPins,
                                     sessionIDs: sessionIDs, mode: mode, screens: connected,
                                     applied: applied, attempts: attempts)
            Task { @MainActor in
                guard let self else { return }
                self.isSweeping = false
                self.applied = outcome.applied
                self.attempts = outcome.attempts
                if outcome.snapshots != self.windows { self.windows = outcome.snapshots }
                self.expireSessionPins(live: outcome.liveWindows)
                if outcome.needsFollowUp || self.sweepRequested {
                    self.scheduleFollowUp(after: outcome.needsFollowUp ? 200 : 20)
                }
                var status = self.status
                status.routedWindows = outcome.routed
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
        var snapshots: [WindowSnapshot] = []
        /// Pencere sunucusunun bildiği pencere numaraları → pid (oturum
        /// pinlerinin yaşayıp yaşamadığı buradan anlaşılır).
        var liveWindows: [CGWindowID: pid_t] = [:]
        var routed = 0
        var lastAction: String?
        /// Bir pencere taşındı ya da düzeni henüz oturmadı; kısa süre sonra
        /// yeniden dene.
        var needsFollowUp = false
    }

    /// Uygulama düzeni bu kadar denemeden sonra da kabul etmezse bırakılır
    /// (ör. en küçük boyut kısıtı olan pencereler). Çerçeve artık pencere
    /// görünürken verildiği için az deneme yeter.
    nonisolated private static let maxAttempts = 6
    /// İlk denemeler hızlı ardışık; sonrası olaylara ve zamanlayıcıya kalır.
    nonisolated private static let quickAttempts = 4

    nonisolated private static func route(
        rules: [Rule], sessionPins: [CGWindowID: Destination], sessionIDs: Set<CGWindowID>,
        mode: Mode, screens: [ScreenInfo], applied: Set<String>, attempts: [String: Int]
    ) -> Outcome {
        var outcome = Outcome(applied: applied, attempts: attempts)
        let sky = SkyLight.shared
        let displays = sky.displaySpaces(mainUUID: Self.primaryUUID(screens))
        let visibleSpaces = Set(displays.map(\.current))
        let windows = AX.allWindows(alwaysInclude: sessionIDs)
        if !sessionIDs.isEmpty { outcome.liveWindows = AX.liveWindowIDs() }

        outcome.snapshots = windows.map { window in
            WindowSnapshot(
                id: window.id, pid: window.pid, appName: window.appName, bundleID: window.bundleID,
                title: window.title,
                placement: Self.placement(of: window, displays: displays, screens: screens),
                frame: AX.frame(of: window),
                isMinimized: AX.isMinimized(window))
        }.sorted {
            let a = $0.appName.localizedCaseInsensitiveCompare($1.appName)
            return a == .orderedSame ? $0.id < $1.id : a == .orderedAscending
        }

        for window in windows {
            // Oturum pini (pencere kimliği) kalıcı kuraldan önce gelir.
            let destination: Destination
            let ruleID: String
            if let pinned = sessionPins[window.id] {
                destination = pinned
                ruleID = "session"
            } else if let rule = rules.first(where: {
                $0.matches(bundleID: window.bundleID,
                           appName: window.appName, title: window.title)
            }), let ruled = rule[mode] {
                destination = ruled
                ruleID = rule.id
            } else { continue }

            guard let screen = screens.first(where: { $0.id == destination.screen })
            else { continue }

            outcome.routed += 1
            let key = "\(window.id)|\(ruleID)|\(mode.rawValue)|\(destination.hashValue)"

            let targetFrame = Coordinates.axRect(
                fromCocoa: destination.layout.rect(in: screen.visibleFrame),
                screens: screens)
            let needsLayout = !outcome.applied.contains(key) && !AX.isMinimized(window)

            // Hedef masaüstü ve pencerenin şu anki space durumu.
            var target: SkyLight.Space?
            var hop: UInt64?          // hedef ekranın şu an görünen masaüstü
            var onTarget = true
            var isVisible = true
            var desktopLabel = ""
            if sky.isAvailable,
               let display = displays.first(where: { $0.displayUUID == screen.uuid }),
               !display.desktops.isEmpty {
                let desktops = display.desktops
                let index = min(destination.desktop, desktops.count)
                let space = desktops[index - 1]
                let current = sky.spaces(of: window.id)
                // Tam ekran uygulamaya ait pencerelere dokunulmaz.
                if current.contains(where: { sky.type(of: $0) != 0 }) { continue }
                target = space
                onTarget = current.contains(space.id)
                isVisible = current.isEmpty || current.contains(where: visibleSpaces.contains)
                hop = display.current
                desktopLabel = "\(screen.name) · Masaüstü \(index)"
            }

            // 1. Düzen — pencere GÖRÜNÜRKEN uygulanır. Görünmeyen bir
            // masaüstündeki pencereye verilen çerçeve uygulama tarafından
            // seçilene kadar işlenmez; bu yüzden sıra: önce çerçeve, sonra
            // masaüstü taşıması. Görünmeyen pencere önce hedef ekranın
            // görünen masaüstüne uğratılır, çerçevesi verilir, sonra hedefe
            // taşınır.
            var placed = false
            if needsLayout {
                if let frame = AX.frame(of: window), Coordinates.close(frame, targetFrame) {
                    placed = true
                } else {
                    if !isVisible, let hop {
                        sky.move(window: window.id, to: hop)
                        Self.wait(until: { sky.spaces(of: window.id).contains(hop) })
                        onTarget = false
                    }
                    AX.setFrame(targetFrame, of: window)
                    if let after = AX.frame(of: window), Coordinates.close(after, targetFrame) {
                        placed = true
                    }
                }

                if placed {
                    outcome.applied.insert(key)
                    outcome.attempts[key] = nil
                } else {
                    let count = (outcome.attempts[key] ?? 0) + 1
                    outcome.attempts[key] = count
                    if count >= Self.maxAttempts {
                        outcome.applied.insert(key)
                        outcome.attempts[key] = nil
                    } else if count <= Self.quickAttempts {
                        outcome.needsFollowUp = true
                    }
                }
            }

            // 2. Masaüstü — çerçeve verildikten sonra; aynı ekrandaki
            // masaüstüler arası taşıma çerçeveyi korur.
            if let target, !onTarget {
                sky.move(window: window.id, to: target.id)
                outcome.needsFollowUp = true
                outcome.lastAction = "\(window.appName) → \(desktopLabel)"
            }
        }
        return outcome
    }

    /// Pencere sunucusunda artık olmayan (kapanmış) pencerelerin oturum
    /// pinlerini birkaç tarama sonra düşürür. AX listesinde görünmemek
    /// yeterli değildir: başka masaüstündeki pencere AX'te eksik çıkabilir
    /// ama sunucuda durur; pin de durur.
    private func expireSessionPins(live: [CGWindowID: pid_t]) {
        guard !sessionPins.isEmpty else { return }
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
            sessionPins[id] = nil
            sessionRecords[id] = nil
            sessionMisses[id] = nil
            forgetApplied(for: id)
        }
        if !expired.isEmpty { saveSessionPins() }
    }

    // MARK: - Yardımcılar

    /// Koşul sağlanana ya da süre dolana kadar kısa aralıklarla bekler
    /// (arka plan kuyruğunda; space taşıması eşzamansız olabilir).
    nonisolated private static func wait(
        until condition: () -> Bool, timeoutMs: Int = 300
    ) {
        var elapsed = 0
        while elapsed < timeoutMs {
            if condition() { return }
            usleep(20_000)
            elapsed += 20
        }
    }

    nonisolated static func primaryUUID(_ screens: [ScreenInfo]) -> String? {
        (screens.first { $0.frame.origin == .zero } ?? screens.first)?.uuid
    }

    /// Pencerenin şu an bulunduğu ekran ve masaüstü sırası. Tam ekran
    /// (ya da başka özel) bir space'teyse nil.
    nonisolated static func placement(
        of window: AXWindow, displays: [SkyLight.DisplaySpaces], screens: [ScreenInfo]
    ) -> Placement? {
        let sky = SkyLight.shared
        let spaces = sky.spaces(of: window.id)
        if !spaces.isEmpty {
            if spaces.contains(where: { sky.type(of: $0) != 0 }) { return nil }
            for display in displays {
                guard let screen = screens.first(where: { $0.uuid == display.displayUUID })
                else { continue }
                if let index = display.desktops.firstIndex(where: { spaces.contains($0.id) }) {
                    return Placement(screen: screen.id, desktop: index + 1)
                }
            }
        }
        // Space bilgisi yoksa pencere çerçevesinden ekranı bul.
        if let frame = AX.frame(of: window) {
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
