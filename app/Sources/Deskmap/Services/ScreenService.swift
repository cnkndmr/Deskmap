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
        self.screens = screens
    }

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
    var mode: Mode { isDocked ? .docked : .undocked }

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

    private func screensChanged() {
        refresh()
        let now = Date()
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
            self.settleEpisodeStart = nil
            self.refresh()
            self.isSettling = false
            Log.screens.notice("""
                Displays settled\(forced ? " (hard cap)" : "", privacy: .public): \
                \(self.screens.map(\.id).joined(separator: ", "), privacy: .public)
                """)
            self.settled.send()
        }
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
