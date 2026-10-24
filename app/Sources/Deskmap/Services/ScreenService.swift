import AppKit
import Combine

/// Bağlı bir ekranın anlık görüntüsü.
struct ScreenInfo: Identifiable, Equatable, Hashable {
    /// Rol kimliği: builtin, external, external-2 ...
    let id: String
    let uuid: String
    let name: String
    let isBuiltin: Bool
    /// Cocoa koordinatları (sol alt köşe tabanlı).
    let frame: CGRect
    let visibleFrame: CGRect

    var known: KnownScreen {
        KnownScreen(id: id, name: name,
                    aspect: frame.height > 0 ? frame.width / frame.height : 1.6,
                    visibleWidth: visibleFrame.width, visibleHeight: visibleFrame.height)
    }

    static func uuid(of screen: NSScreen?) -> String? {
        guard let screen,
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(
                CGDirectDisplayID(number.uint32Value))?.takeRetainedValue()
        else { return nil }
        return normalize(CFUUIDCreateString(nil, cfUUID) as String)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func normalize(_ uuid: String) -> String {
        uuid.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

/// Bağlı ekranları ve dock durumunu izler.
@MainActor
final class ScreenService: ObservableObject {

    @Published private(set) var screens: [ScreenInfo] = []
    /// Ekran değişiminden yatışmaya kadar true. Bu sürede macOS ekranları
    /// yeniden düzenler; Router listelemeyi sürdürür ama hiçbir pencereyi
    /// taşımaz (yarım düzenlenmiş ekrana göre yanlış yere yerleşmesin).
    @Published private(set) var isSettling = false
    /// Son ekran değişimi bildirimi (Tablo E: bundan 15 sn sonraya dek
    /// Mission Control'de ekran değiştiren masaüstü geri alınmaz).
    private(set) var lastChangeAt: Date?

    /// Ekran değişimi yatıştıktan sonra tetiklenir.
    let settled = PassthroughSubject<Void, Never>()

    // nonisolated(unsafe): yalnızca init'te (ana aktör) atanır, deinit'te
    // kaldırılır; gözlemci belirteci Sendable olmadığı için deinit erişimi
    // başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var launchObserver: NSObjectProtocol?
    /// Açılış bittikten sonra ikinci ölçüme kadar beklenen süre.
    nonisolated static let launchRecheckDelay: TimeInterval = 2
    private var settleTask: Task<Void, Never>?
    /// Süren yatışma bölümünün ilk ekran değişimi (üst sınır için).
    private var settleEpisodeStart: Date?
    /// Son ekran değişiminden sonra bu kadar sessizlik "yatıştı" sayılır
    /// (monitör takılınca macOS birkaç saniye boyunca yeniden düzenler).
    nonisolated static let settleInterval: TimeInterval = 2.5
    /// Değişimler hiç durmazsa (titrek kablo, sürekli bildirim) yatışma en
    /// geç bölümün başından bu kadar sonra zorla biter; yoksa `isSettling`
    /// hiç düşmez ve yönlendirme sonsuza dek kapalı kalırdı.
    nonisolated static let settleHardCap: TimeInterval = 10

    /// Ham ekran kaynağı; üretimde `NSScreen`, testte enjekte edilir.
    private var displaySource: () -> [RawDisplay]

    /// Hatırlanan harici ekran rolleri (belgedeki `displayRoles`). Değişince
    /// roller hemen yeniden hesaplanır; sonuç değiştiyse yeniden yerleştirme
    /// (`settled`) tetiklenir.
    var roles: DisplayRoles {
        didSet {
            guard roles != oldValue, !isSettling else { return }
            let detected = Self.detect(displaySource(), roles: roles)
            guard detected != screens else { return }
            screens = detected
            Log.screens.notice("""
                Display roles changed: \
                \(detected.map { "\($0.id)=\($0.name)" }.joined(separator: ", "), privacy: .public)
                """)
            settled.send()
        }
    }

    init(roles: DisplayRoles = DisplayRoles()) {
        displaySource = { Self.currentDisplays() }
        self.roles = roles
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
        // İlk ölçüm `AppModel` kurulurken, uygulama pencere sunucusuna tam
        // bağlanmadan yapılır: o anda harici ekranın kullanılabilir alanı
        // menü çubuğu düşülmeden (tam çerçeve) gelir ve ekran bildirimi
        // olmadan düzelmez. Üst kenara dayanan her düzen menü çubuğunun
        // altına hedeflenir, pencere tutmaz ("Layout given up"); ortalanan
        // sabit boyut yarım menü çubuğu kadar yukarı kayar. Açılış bitince
        // ve kısa bir süre sonra yeniden ölçülür.
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.remeasureAfterLaunch() }
        }
    }

    private func remeasureAfterLaunch() {
        adoptIfChanged()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.launchRecheckDelay * 1_000_000_000))
            self?.adoptIfChanged()
        }
    }

    /// Ölçüm değiştiyse benimser ve yeniden yerleştirmeyi tetikler. Ekran
    /// değişimi yatışırken dokunmaz: yatışma zaten yeniden ölçer.
    private func adoptIfChanged() {
        guard !isSettling else { return }
        let detected = Self.detect(displaySource(), roles: roles)
        guard detected != screens else { return }
        screens = detected
        Log.screens.notice("""
            Usable area re-measured after launch: \
            \(detected.map { "\($0.id) \(Int($0.visibleFrame.width))×\(Int($0.visibleFrame.height))" }
                .joined(separator: ", "), privacy: .public)
            """)
        settled.send()
    }

    /// Shots modu (`--shots`): `NSScreen` gözlemcisi eklenmez, `refresh()`
    /// çağrılmaz. Ekran listesi dışarıdan sabit verilir. Üretim `init()`'i
    /// değişmez.
    init(demo screens: [ScreenInfo]) {
        let raw = screens.map {
            RawDisplay(uuid: $0.uuid, name: $0.name, isBuiltin: $0.isBuiltin,
                       frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        displaySource = { raw }
        roles = DisplayRoles()
        isDemo = true
        self.screens = screens
    }

    /// Yalnız Shots modunda: demo ekran listesini değiştirir (monitör
    /// takıldı/söküldü karesi). Üretimde (`isDemo` false) hiçbir şey yapmaz.
    func replaceDemoScreens(_ screens: [ScreenInfo]) {
        guard isDemo else { return }
        self.screens = screens
    }

    /// Shots modunda true; üretim init'leri değiştirmez.
    private var isDemo = false

    /// Test: ekran gözlemcisi yok; ölçüm verilen ham listeden yapılır.
    init(displays: @escaping () -> [RawDisplay], roles: DisplayRoles = DisplayRoles()) {
        displaySource = displays
        self.roles = roles
        refresh()
    }

    /// Test: ekran değişimini (gözlemci bildirimi) ve yatışmayı taklit eder.
    func simulateChangeForTesting(settle: Bool) {
        refresh()  // üretimdeki sıra: önce ölçüm, sonra yatışma bayrağı
        if !settle { isSettling = true; return }
        isSettling = false
        settled.send()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let launchObserver { NotificationCenter.default.removeObserver(launchObserver) }
    }

    var isDocked: Bool { screens.contains { !$0.isBuiltin } }
    var mode: Mode { Self.mode(of: screens) }

    /// Verilen ekran listesinin modu (saf). `$screens` aboneleri bunu yayınlanan
    /// değerle çağırmalı: `@Published` willSet'te yayınlar, o anda `mode` hâlâ
    /// eski listeyi okur.
    nonisolated static func mode(of screens: [ScreenInfo]) -> Mode {
        screens.contains { !$0.isBuiltin } ? .docked : .undocked
    }

    func refresh() {
        screens = Self.detect(displaySource(), roles: roles)
    }

    /// Şu an bağlı harici ekranlar, rol sırasında (menü için).
    var connectedExternals: [(role: String, display: DisplayRoles.Display)] {
        screens.filter { !$0.isBuiltin }.map {
            (role: $0.id, display: DisplayRoles.Display(
                uuid: $0.uuid, minX: $0.frame.minX, minY: $0.frame.minY, name: $0.name))
        }
    }

    /// Rolü öğrenilecek ve onaylanacak harici ekranlar: test ekranı
    /// ("Deskmap Test Display") hiç öğrenilmez, onay da beklemez.
    var externalAssignment: [(role: String, uuid: String)] {
        screens.filter { !$0.isBuiltin && !Store.isTestDisplay($0.name) }
            .map { (role: $0.id, uuid: $0.uuid) }
    }

    /// Onay bekleyen roller (`DisplayRoles.unconfirmed`): düzen uygulanmaz.
    var heldRoles: Set<String> { roles.unconfirmed(externalAssignment) }

    /// Bağlı ve onay beklemeyen roller: sıralı yerlerin kullanılabildiği
    /// ekranlar (`Routing.resolvePlace`, `Rule.place`).
    var usableRoles: Set<String> { Set(screens.map(\.id)).subtracting(heldRoles) }

    private func screensChanged() {
        refresh()
        let now = Date()
        noteChangeForProbe(at: now)
        lastChangeAt = now
        if !isSettling {
            isSettling = true
            settleEpisodeStart = now
            Log.screens.notice("Display change: \(self.screens.count) display(s), waiting to settle")
        }
        let delay = Self.settleDelay(episodeStart: settleEpisodeStart ?? now, now: now)
        let forced = delay < Self.settleInterval
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.finishSettle(reason: forced ? " (hard cap)" : "")
        }
        startProbeIfNeeded()
    }

    private func finishSettle(reason: String) {
        settleTask?.cancel()
        settleTask = nil
        probeTask?.cancel()
        probeTask = nil
        if let start = settleEpisodeStart {
            probeEpisodeLog(settledAfter: Date().timeIntervalSince(start))
        }
        settleEpisodeStart = nil
        refresh()
        isSettling = false
        Log.screens.notice("""
            Displays settled\(reason, privacy: .public): \
            \(self.screens.map(\.id).joined(separator: ", "), privacy: .public)
            """)
        settled.send()
    }

    // MARK: - Durum yoklamalı yatışma (perf/PLAN-perf.md §4.4 B2)

    /// `perf.settlePollShadow`: yoklama "şimdi yatışırdım" anını ve ondan
    /// sonra gelen ekran bildirimlerini loglar; karar bugünkü 2,5 sn kuralıyla.
    /// `perf.settlePoll`: yoklama yatışmayı erken bitirir (10 sn tavan kalır).
    nonisolated static var settlePollShadow: Bool { UserDefaults.standard.bool(forKey: "perf.settlePollShadow") }
    nonisolated static var settlePoll: Bool { UserDefaults.standard.bool(forKey: "perf.settlePoll") }
    nonisolated static let probeInterval: TimeInterval = 0.2

    /// Bir yoklama örneği: NSScreen ekranları (UUID + çerçeve) ve SkyLight'ın
    /// ekran → masaüstü listesi.
    struct SettleSample: Equatable {
        let screens: [String: CGRect]
        let spaces: [String: [UInt64]]
        /// NSScreen ve SkyLight aynı ekran kümesini görüyor mu.
        var consistent: Bool { !screens.isEmpty && Set(screens.keys) == Set(spaces.keys) }
    }

    /// Yatışma kararı (saf): tutarlı ve en az `stableFor` boyunca değişmeyen örnek.
    struct SettleProbe {
        static let stableFor: TimeInterval = 0.5
        private(set) var sample: SettleSample?
        private(set) var stableSince: Date?

        /// Yeni örneği işler; yatıştıysa true.
        mutating func feed(_ next: SettleSample, at now: Date) -> Bool {
            if next != sample { sample = next; stableSince = now }
            guard next.consistent, let since = stableSince else { return false }
            return now.timeIntervalSince(since) >= Self.stableFor
        }

        /// Ekran bildirimi geldi: kararlılık baştan sayılır.
        mutating func reset(at now: Date) { stableSince = now }
    }

    private var probeTask: Task<Void, Never>?
    private var probe = SettleProbe()
    /// Bu bölümde yoklamanın yatıştığı an (bölüm başından saniye) ve ondan sonraki bildirim sayısı.
    private var probeSettledAt: TimeInterval?
    private var lateNotifications = 0

    static func currentSettleSample() -> SettleSample {
        let raw = currentDisplays()
        var screens: [String: CGRect] = [:]
        for display in raw { screens[display.uuid] = display.frame }
        let main = raw.first { $0.frame.origin == .zero }?.uuid
        var spaces: [String: [UInt64]] = [:]
        for display in SkyLight.shared.displaySpaces(mainUUID: main) {
            spaces[display.displayUUID] = display.spaces.map(\.id)
        }
        return SettleSample(screens: screens, spaces: spaces)
    }

    private func noteChangeForProbe(at now: Date) {
        guard Self.settlePollShadow || Self.settlePoll else { return }
        if isSettling, let start = settleEpisodeStart, let at = probeSettledAt {
            lateNotifications += 1
            Log.screens.notice("""
                Settle probe: display notification \(String(format: "%.2f", now.timeIntervalSince(start) - at), privacy: .public) s \
                after the probe had settled
                """)
        }
        probe.reset(at: now)
    }

    private func startProbeIfNeeded() {
        guard Self.settlePollShadow || Self.settlePoll, probeTask == nil else { return }
        if settleEpisodeStart != nil, probeSettledAt == nil { lateNotifications = 0 }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.probeInterval * 1_000_000_000))
                guard !Task.isCancelled, let self, self.isSettling, let start = self.settleEpisodeStart else { return }
                let now = Date()
                guard self.probe.feed(Self.currentSettleSample(), at: now) else { continue }
                if self.probeSettledAt == nil {
                    self.probeSettledAt = now.timeIntervalSince(start)
                    Log.screens.notice("""
                        Settle probe: stable after \(String(format: "%.2f", now.timeIntervalSince(start)), privacy: .public) s\
                        \(Self.settlePoll ? "" : " (shadow)", privacy: .public)
                        """)
                }
                self.probeTask = nil
                if Self.settlePoll { self.finishSettle(reason: " (probe)") }
                return
            }
        }
    }

    /// Bölüm sonu özeti (gölge verisi): yoklama ne zaman yatışırdı, gerçek
    /// yatışma ne zaman oldu, aradaki bildirim sayısı.
    private func probeEpisodeLog(settledAfter actual: TimeInterval) {
        guard Self.settlePollShadow || Self.settlePoll else { return }
        let at = probeSettledAt.map { String(format: "%.2f", $0) } ?? "-"
        Log.screens.notice("""
            Settle probe episode: probe \(at, privacy: .public) s, settled \(String(format: "%.2f", actual), privacy: .public) s, \
            notifications after probe \(self.lateNotifications)
            """)
        probeSettledAt = nil
        lateNotifications = 0
        probe = SettleProbe()
    }

    /// Bu ekran değişiminden sonra ne kadar beklenir (saf): normalde
    /// `settleInterval`; bölüm başlangıcından `settleHardCap` sonrasını
    /// aşmaz, sınır geçildiyse 0.
    nonisolated static func settleDelay(episodeStart: Date, now: Date) -> TimeInterval {
        let remaining = settleHardCap - now.timeIntervalSince(episodeStart)
        return max(0, min(settleInterval, remaining))
    }

    /// Harici ekranların rol sırası (`external`, `external-2` …): soldan
    /// sağa; aynı sütundaysa yukarıdan aşağı (Cocoa'da küçük minY alttadır,
    /// yine de sabit bir sıra verir); ikisi de eşitse UUID. Böylece aynı
    /// yerleşim her açılışta aynı rolleri üretir.
    nonisolated static func externalOrder(
        _ a: (minX: CGFloat, minY: CGFloat, uuid: String),
        _ b: (minX: CGFloat, minY: CGFloat, uuid: String)
    ) -> Bool {
        if a.minX != b.minX { return a.minX < b.minX }
        if a.minY != b.minY { return a.minY < b.minY }
        return a.uuid < b.uuid
    }

    /// `NSScreen`'den okunan ham ekran (saf `detect` girdisi).
    struct RawDisplay: Equatable {
        let uuid: String
        let name: String
        let isBuiltin: Bool
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// Bağlı ekranların ham listesi (`NSScreen` sırasında).
    static func currentDisplays() -> [RawDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = ScreenInfo.displayID(of: screen),
                  let uuid = ScreenInfo.uuid(of: screen) else { return nil }
            return RawDisplay(uuid: uuid, name: screen.localizedName,
                              isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
                              frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    /// Ham ekranlardan rol listesi (saf): ilk dahili ekran `builtin`; aynı
    /// UUID'li harici ekranlar bir kez sayılır; roller `DisplayRoles.assign`
    /// ile (kayıt yoksa eski konum sırası).
    nonisolated static func detect(_ raw: [RawDisplay], roles: DisplayRoles) -> [ScreenInfo] {
        var externals: [String: RawDisplay] = [:]
        var displays: [DisplayRoles.Display] = []
        for display in raw where !display.isBuiltin && externals[display.uuid] == nil {
            externals[display.uuid] = display
            displays.append(DisplayRoles.Display(uuid: display.uuid, minX: display.frame.minX,
                                                 minY: display.frame.minY, name: display.name))
        }
        var result: [ScreenInfo] = []
        if let screen = raw.first(where: \.isBuiltin) {
            result.append(ScreenInfo(
                id: "builtin", uuid: screen.uuid, name: screen.name,
                isBuiltin: true, frame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        for (role, display) in roles.assign(displays) {
            guard let screen = externals[display.uuid] else { continue }
            result.append(ScreenInfo(
                id: role, uuid: display.uuid, name: screen.name, isBuiltin: false,
                frame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        return result
    }
}
