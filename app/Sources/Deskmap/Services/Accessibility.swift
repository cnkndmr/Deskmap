import AppKit
import ApplicationServices
import Combine

// MARK: - İzin

/// Accessibility izninin durumunu izler.
@MainActor
final class AccessibilityPermission: ObservableObject {

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    // nonisolated(unsafe): yalnızca init'te (ana aktör) atanır, deinit'te
    // geçersiz kılınır; `Timer` Sendable olmadığı için deinit erişimi
    // başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var timer: Timer?

    init() {
        Log.ax.notice("accessibility trusted: \(self.isTrusted, privacy: .public)")
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = AXIsProcessTrusted()
                if now != self.isTrusted {
                    Log.ax.notice("accessibility trusted: \(now, privacy: .public)")
                    self.isTrusted = now
                }
            }
        }
    }

    /// Shots modu (`--shots`): izin zamanlayıcısı kurulmaz; durum dışarıdan
    /// sabit verilir. Üretim `init()`'i değişmez.
    init(demoTrusted trusted: Bool) {
        isTrusted = trusted
    }

    deinit { timer?.invalidate() }

    func request() {
        let options = [AX.trustedCheckOptionPrompt: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security"
                      + "?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Pencere

/// Bir uygulama penceresinin anlık görüntüsü.
struct AXWindow: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String
    let title: String
    let element: AXUIElement

    static func == (a: AXWindow, b: AXWindow) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Accessibility üzerinden pencere okuma ve taşıma.
enum AX {

    /// `kAXTrustedCheckOptionPrompt` anahtarının değeri. C başlığındaki
    /// simge Swift'e değişebilir bir genel (`var`) olarak gelir ve sıkı
    /// eşzamanlılıkta uyarı verir; değeri sabit olduğu için burada yazılır
    /// (`EngineHelperTests` eşitliğini doğrular).
    static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"

    // MARK: - Yanıt vermeyen uygulamalar

    /// Bir uygulama Accessibility sorularına bu kadar sürede yanıt vermezse
    /// (donmuş, hata ayıklayıcıda duran) sonraki taramalarda bir süre
    /// atlanır; süre her tekrarında ikiye katlanır (2 sn → 30 sn).
    private struct Backoff {
        var until: Date
        var delay: TimeInterval
        let name: String
    }

    // nonisolated(unsafe): her erişim `backoffLock` altında yapılır
    // (isBackedOff / note / pruneBackoffs / unresponsiveApps).
    nonisolated(unsafe) private static var backoffs: [pid_t: Backoff] = [:]
    private static let backoffLock = NSLock()
    /// Tek bir AX çağrısı bu kadar sürerse uygulama yanıt vermiyor sayılır:
    /// donmuş uygulama ilk çağrıda `timeout` (1 sn) zaman aşımına takılır.
    /// Çok pencereli ama yanıt veren uygulamaların (Electron, tarayıcı)
    /// toplam süresi bunu tetiklemez.
    static let slowCallThreshold: TimeInterval = 0.5
    /// Emniyet: tek çağrılar kısa olsa da uygulamanın toplamı bunu aşarsa
    /// yine atlanır (tarama bir uygulamaya kilitlenmesin).
    static let slowTotalThreshold: TimeInterval = 4
    private static let minBackoff: TimeInterval = 2
    private static let maxBackoff: TimeInterval = 30

    /// Bir uygulamanın taramadaki AX çağrı süreleri.
    struct AppTiming: Equatable {
        var total: TimeInterval = 0
        /// En uzun tek çağrı.
        var maxCall: TimeInterval = 0

        /// Çağrıyı çalıştırıp süresini işler.
        mutating func measure<T>(_ call: () -> T) -> T {
            let started = Date()
            let value = call()
            let elapsed = Date().timeIntervalSince(started)
            total += elapsed
            maxCall = max(maxCall, elapsed)
            return value
        }
    }

    /// Backoff kararı (saf): en uzun tek çağrı ya da toplam eşiği aştı mı.
    static func isUnresponsive(maxSingleCall: TimeInterval, total: TimeInterval) -> Bool {
        maxSingleCall >= slowCallThreshold || total >= slowTotalThreshold
    }

    private static func isBackedOff(_ pid: pid_t, now: Date) -> Bool {
        backoffLock.lock(); defer { backoffLock.unlock() }
        guard let entry = backoffs[pid] else { return false }
        return entry.until > now
    }

    /// Uygulamanın bu taramadaki çağrı sürelerini kaydeder: yavaşsa
    /// atlama süresi başlar/uzar, hızlıysa kayıt silinir.
    private static func note(pid: pid_t, name: String, timing: AppTiming, now: Date) {
        backoffLock.lock(); defer { backoffLock.unlock() }
        let previous = backoffs[pid]
        if isUnresponsive(maxSingleCall: timing.maxCall, total: timing.total) {
            let delay = min((previous?.delay).map { $0 * 2 } ?? minBackoff, maxBackoff)
            backoffs[pid] = Backoff(until: now.addingTimeInterval(delay), delay: delay, name: name)
            if previous == nil {
                Log.ax.notice("""
                    \(name, privacy: .public) (pid \(pid)) not responding: longest call \
                    \(timing.maxCall, format: .fixed(precision: 2)) s, total \
                    \(timing.total, format: .fixed(precision: 2)) s; skipping for \(delay, format: .fixed(precision: 0)) s
                    """)
            }
        } else {
            backoffs[pid] = nil
            if previous != nil {
                Log.ax.notice("\(name, privacy: .public) (pid \(pid)) responding again")
            }
        }
    }

    /// Süreç geneli varsayılan AX yanıt süresi. Sistem geneli öğeye
    /// verilen değer, ayrıca ayarlanmamış bütün öğeler için geçerlidir
    /// (`kAXWindows` ile gelen pencere öğeleri ~6 sn varsayılanı
    /// kullanmasın). Router açılışta bir kez çağırır.
    static func setGlobalTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }

    /// Kapanmış uygulamaların kayıtlarını temizler.
    private static func pruneBackoffs(running: Set<pid_t>) {
        backoffLock.lock(); defer { backoffLock.unlock() }
        backoffs = backoffs.filter { running.contains($0.key) }
    }

    /// En yakın geri çekilme bitişi (sonrasında o uygulama yeniden taranır);
    /// süren geri çekilme yoksa nil.
    static func nextBackoffEnd(now: Date = Date()) -> Date? {
        backoffLock.lock(); defer { backoffLock.unlock() }
        return backoffs.values.map(\.until).filter { $0 > now }.min()
    }

    /// Şu an atlanan (yanıt vermeyen) uygulamaların adları.
    static func unresponsiveApps() -> [String] {
        backoffLock.lock(); defer { backoffLock.unlock() }
        let now = Date()
        return backoffs.values.filter { $0.until > now }.map(\.name).sorted()
    }

    private typealias GetWindowFn =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// `_AXUIElementGetWindow`: AX öğesinden CGWindowID. Dışa açık değil
    /// ama HIServices içinde dlsym ile bulunur (Hammerspoon da kullanır).
    private static let getWindowID: GetWindowFn? = {
        guard let pointer = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow")
        else { return nil }
        return unsafeBitCast(pointer, to: GetWindowFn.self)
    }()

    private typealias CreateWithRemoteTokenFn =
        @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    /// `_AXUIElementCreateWithRemoteToken`: pid + pencere numarasından AX
    /// öğesi. Uygulamanın kendi listelemediği (başka masaüstündeki)
    /// pencerelere böyle erişilir (yabai / AeroSpace yöntemi).
    private static let createWithRemoteToken: CreateWithRemoteTokenFn? = {
        guard let pointer = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementCreateWithRemoteToken")
        else { return nil }
        return unsafeBitCast(pointer, to: CreateWithRemoteTokenFn.self)
    }()

    /// Pencere numarasından AX öğesi. Belirteç 20 bayt: pid (4), 0 (4),
    /// "coco" 0x636f636f (4), AX öğe kimliği (8). Öğe kimliği pencere
    /// numarası DEĞİL (eskiden öyle sanılıyordu; çoğu uygulamada -25201
    /// dönüyor, başka masaüstündeki Claude/ChatGPT/Finder pencereleri hiç
    /// listelenmiyordu; ölçüldü 25.09.2026). alt-tab-macos yöntemi: kimlikler
    /// 0'dan taranır, `_AXUIElementGetWindow` ile eşleşen AXWindow bulunur.
    ///
    /// Tarama uygulama (pid) başına: bir tam geçiş o uygulamanın bütün
    /// pencerelerini önbelleğe yazar; `remoteRescan` dolmadan o geçişte
    /// aranıp bulunamayan numaralar yeniden taranmaz (yardımcı pencereler
    /// her taramada 1000 IPC yapmasın). Geçişten sonra doğan pencere kapıya
    /// takılmaz (bkz. `RemoteScanGate`). Zaman aşımı (yanıt vermeyen
    /// uygulama) ya da süre bütçesi aşılırsa tarama kesilir, kısa süre sonra
    /// yeniden denenir.
    /// `unlisted`: aynı uygulamanın bu turda aranacak öbür numaraları; tam
    /// geçiş hepsi için karar verir, her biri ayrı tarama başlatmaz.
    static func element(pid: pid_t, windowID: CGWindowID,
                        unlisted: Set<CGWindowID> = []) -> AXUIElement? {
        guard createWithRemoteToken != nil, let getWindowID else { return nil }
        let now = Date()
        remoteLock.lock()
        let gate = remoteGates[pid] ?? RemoteScanGate()
        remoteLock.unlock()

        if let cached = gate.ids[windowID],
           let element = remoteElement(pid: pid, elementID: cached) {
            AXUIElementSetMessagingTimeout(element, 0.2)
            var found: CGWindowID = 0
            if getWindowID(element, &found) == .success, found == windowID { return element }
        }
        guard gate.shouldScan(for: windowID, now: now) else { return nil }

        var discovered: [CGWindowID: UInt64] = [:]
        var aborted = false
        for id in UInt64(0)..<remoteScanLimit {
            if Date().timeIntervalSince(now) > remoteScanBudget { aborted = true; break }
            guard let element = remoteElement(pid: pid, elementID: id) else { continue }
            AXUIElementSetMessagingTimeout(element, 0.2)
            var found: CGWindowID = 0
            let result = getWindowID(element, &found)
            if result == .cannotComplete { aborted = true; break }
            guard result == .success, found != 0, discovered[found] == nil else { continue }
            // Pencerenin alt öğeleri de aynı numarayı döndürür (Claude'da
            // ilk eşleşen AXUnknown, Finder'da AXOutline); yalnız pencere.
            let role: String? = attribute(element, kAXRoleAttribute)
            guard role == kAXWindowRole else { continue }
            discovered[found] = id
        }
        remoteLock.lock()
        remoteGates[pid, default: RemoteScanGate()].record(
            discovered, aborted: aborted, wanted: unlisted.union([windowID]), now: now)
        remoteLock.unlock()
        if aborted {
            Log.ax.notice("Remote window scan cut short for pid \(pid) (timeout or budget)")
        }
        return discovered[windowID].flatMap { remoteElement(pid: pid, elementID: $0) }
    }

    private static func remoteElement(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }
        var token = [UInt8](repeating: 0, count: 20)
        withUnsafeBytes(of: pid.littleEndian) { for (i, b) in $0.enumerated() { token[i] = b } }
        withUnsafeBytes(of: UInt32(0x636f636f).littleEndian) {
            for (i, b) in $0.enumerated() { token[8 + i] = b }
        }
        withUnsafeBytes(of: elementID.littleEndian) {
            for (i, b) in $0.enumerated() { token[12 + i] = b }
        }
        return createWithRemoteToken(Data(token) as CFData)?.takeRetainedValue()
    }

    /// Taranan en yüksek öğe kimliği (alt-tab-macos 1000 kullanıyor).
    private static let remoteScanLimit: UInt64 = 1000
    /// Bulunamayan numaraların yeniden taranmadığı süre (bir tarama ~20 ms, ölçüldü).
    static let remoteRescan: TimeInterval = 30
    /// Kesilen taramadan sonra yeniden deneme.
    static let remoteAbortRetry: TimeInterval = 5
    /// Tek taramanın süre bütçesi (yavaş ama yanıt veren uygulama).
    private static let remoteScanBudget: TimeInterval = 0.3
    nonisolated(unsafe) private static var remoteGates: [pid_t: RemoteScanGate] = [:]
    private static let remoteLock = NSLock()

    /// Bir uygulamanın uzak tarama durumu ve kapısı (saf). Kapı pencere
    /// başına: süre dolmadan yalnız son tam geçişte aranıp bulunamayan
    /// numaralar bekletilir. Pid başına olsaydı geçişten sonra açılan
    /// pencere, başka masaüstüne taşındığı anda süre dolana kadar
    /// listeden düşerdi.
    struct RemoteScanGate: Equatable {
        /// Pencere numarası → AX öğe kimliği.
        var ids: [CGWindowID: UInt64] = [:]
        /// Tam geçişte aranıp bulunamayan numaralar (yardımcı pencereler).
        var misses: Set<CGWindowID> = []
        var nextScan: Date?
        /// Son tarama kesildi: `nextScan`'e kadar hiçbir numara taranmaz
        /// (yanıt vermeyen uygulama pencere başına yeniden taranmasın).
        var cutShort = false

        func shouldScan(for windowID: CGWindowID, now: Date) -> Bool {
            guard let nextScan, now < nextScan else { return true }
            return !cutShort && !misses.contains(windowID)
        }

        /// Biten taramayı işler. `wanted`: bu geçişin yanıtladığı numaralar
        /// (aranan pencere ve aynı uygulamanın listelenmeyen öbür pencereleri).
        mutating func record(_ discovered: [CGWindowID: UInt64], aborted: Bool,
                             wanted: Set<CGWindowID>, now: Date) {
            let expired = nextScan.map { now >= $0 } ?? true
            cutShort = aborted
            if aborted {
                ids.merge(discovered) { _, new in new }
                nextScan = now.addingTimeInterval(AX.remoteAbortRetry)
                return
            }
            // Tam geçiş: kimlikler yeniden kullanılabilir, eski harita atılır.
            ids = discovered
            // Süresi dolan kayıtlar atılır (kapanmış pencereler birikmesin);
            // süre içindeki geçiş öncekileri de yeniden aramış sayılır.
            misses = (expired ? [] : misses).union(wanted).subtracting(discovered.keys)
            nextScan = now.addingTimeInterval(AX.remoteRescan)
        }
    }

    /// Kapanmış uygulamaların öğe kimliği önbelleğini atar.
    static func pruneRemoteCache(running: Set<pid_t>) {
        remoteLock.lock(); defer { remoteLock.unlock() }
        remoteGates = remoteGates.filter { running.contains($0.key) }
    }

    /// Dock'ta görünen bir uygulama.
    struct App: Identifiable, Hashable {
        let pid: pid_t
        let name: String
        let bundleID: String
        var id: pid_t { pid }
    }

    /// `runningApps()` önbelleği: `NSWorkspace.runningApplications` her
    /// çağrıda yeni nesneler döndürür ve her özellik okuması (pid dahil)
    /// LaunchServices'e XPC yapar; her taramada yüzlerce süreç için bu,
    /// boşta CPU'nun en büyük kalemiydi. Uygulama açılınca/kapanınca/
    /// etkinleşince `invalidateRunningApps()`; en geç `runningAppsTTL`.
    nonisolated(unsafe) private static var cachedApps: (apps: [App], at: Date)?
    private static let appsLock = NSLock()
    static let runningAppsTTL: TimeInterval = 60

    static func invalidateRunningApps() {
        appsLock.lock(); defer { appsLock.unlock() }
        cachedApps = nil
    }

    /// Dock'ta görünen, çalışan bütün uygulamalar (kendimiz hariç); önbellekli.
    static func runningApps() -> [App] {
        let now = Date()
        appsLock.lock()
        if let cached = cachedApps, now.timeIntervalSince(cached.at) < runningAppsTTL {
            appsLock.unlock()
            return cached.apps
        }
        appsLock.unlock()
        let apps = freshRunningApps()
        appsLock.lock(); defer { appsLock.unlock() }
        cachedApps = (apps, now)
        return apps
    }

    private static func freshRunningApps() -> [App] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && ActivationPolicyCache.shared.isRegular($0) }
            .map { App(pid: $0.processIdentifier,
                       name: $0.localizedName ?? "?",
                       bundleID: $0.bundleIdentifier ?? "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Tüm normal uygulamaların pencereleri. Başlıksız pencereler de
    /// listelenir (uygulama geneli kurallar için); yalnızca yüzen
    /// paneller ve sistem diyalogları atlanır.
    /// `timeout`: uygulama başına Accessibility yanıt süresi. Bir uygulamaya
    /// ilk kez sorulduğunda yanıt yavaş olabilir; kısa değer uygulamayı
    /// sessizce listeden düşürür.
    /// `alwaysInclude`: pencere sunucusunda var olan bu numaralar, uzak
    /// belirteçle üretilen öğe rol sorusuna yanıt vermese de listelenir
    /// (geçici pinli pencereler: kullanıcı onları işaretledi, başka
    /// masaüstündeyken de görünmeli).
    /// `server`: aynı taramada zaten okunmuş pencere sunucusu listesi;
    /// verilmezse burada okunur.
    static func allWindows(timeout: Float = 1.0,
                           alwaysInclude: Set<CGWindowID> = [],
                           server: WindowServerList? = nil) -> [AXWindow] {
        var result: [AXWindow] = []
        var seen: Set<CGWindowID> = []
        let apps = runningApps()
        let now = Date()
        pruneBackoffs(running: Set(apps.map(\.pid)))
        pruneRemoteCache(running: Set(apps.map(\.pid)))
        /// Bu taramada uygulama başına AX çağrı süreleri (yanıt vermeyeni bulmak için).
        var timings: [pid_t: AppTiming] = [:]
        let active = apps.filter { !isBackedOff($0.pid, now: now) }

        // 1. Uygulamanın kendi listesi (görünen masaüstündekiler kesin).
        for app in active {
            let pid = app.pid
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)

            guard let windows: [AXUIElement] = timings[pid, default: AppTiming()]
                .measure({ attribute(appElement, kAXWindowsAttribute) })
            else { continue }

            for element in windows {
                guard timings[pid, default: AppTiming()].measure({ isStandardWindow(element) })
                else { continue }
                let title: String = timings[pid, default: AppTiming()]
                    .measure({ attribute(element, kAXTitleAttribute) }) ?? ""

                var windowID: CGWindowID = 0
                guard let getWindowID,
                      timings[pid, default: AppTiming()]
                        .measure({ getWindowID(element, &windowID) }) == .success,
                      windowID != 0, !seen.contains(windowID) else { continue }
                seen.insert(windowID)

                result.append(AXWindow(
                    id: windowID,
                    pid: pid,
                    appName: app.name,
                    bundleID: app.bundleID,
                    title: title,
                    element: element))
            }
        }

        // 2. Uygulamanın listelemediği pencereler (başka masaüstü / ekran):
        //    pencere sunucusundan numaralarını alıp uzak belirteçle AX
        //    öğesi üret.
        let byPID = Dictionary(uniqueKeysWithValues: active.map { ($0.pid, $0) })
        let serverWindows = (server ?? windowServerList()).windows
        // Uygulama başına listelenmeyen numaralar: tek tam geçiş hepsini
        // yanıtlar (yardımcı pencereler sırayla ayrı tarama başlatmasın).
        var unlisted: [pid_t: Set<CGWindowID>] = [:]
        for info in serverWindows where !seen.contains(info.id) {
            unlisted[info.pid, default: []].insert(info.id)
        }
        for info in serverWindows {
            guard !seen.contains(info.id), let app = byPID[info.pid] else { continue }
            let pid = app.pid
            // Bu taramada zaten yavaş kalan uygulamaya uzak tarama yapılmaz;
            // süre uygulamanın hesabına yazılır (backoff kararı görsün).
            if let timing = timings[pid],
               isUnresponsive(maxSingleCall: timing.maxCall, total: timing.total) { continue }
            guard let element = timings[pid, default: AppTiming()]
                .measure({ element(pid: pid, windowID: info.id, unlisted: unlisted[pid] ?? []) })
            else { continue }
            AXUIElementSetMessagingTimeout(element, timeout)
            guard alwaysInclude.contains(info.id)
                    || timings[pid, default: AppTiming()]
                        .measure({ isStandardWindow(element, strict: true) })
            else { continue }
            let title: String = timings[pid, default: AppTiming()]
                .measure({ attribute(element, kAXTitleAttribute) }) ?? info.name
            seen.insert(info.id)
            result.append(AXWindow(
                id: info.id,
                pid: pid,
                appName: app.name,
                bundleID: app.bundleID,
                title: title,
                element: element))
        }

        for app in active {
            note(pid: app.pid, name: app.name, timing: timings[app.pid] ?? AppTiming(), now: now)
        }
        return result
    }

    /// Rolü pencere olan ve yüzen panel / sistem diyaloğu olmayan öğe.
    /// `strict`: rol okunamıyorsa da ele (uzak belirteçle üretilen öğeler
    /// için; yanıt vermeyen öğe gerçek pencere olmayabilir).
    private static func isStandardWindow(_ element: AXUIElement, strict: Bool = false) -> Bool {
        let role: String? = attribute(element, kAXRoleAttribute)
        guard role == kAXWindowRole || (!strict && role == nil) else { return false }
        let subrole: String? = attribute(element, kAXSubroleAttribute)
        if let subrole,
           subrole == kAXFloatingWindowSubrole
            || subrole == kAXSystemDialogSubrole
            || subrole == kAXSystemFloatingWindowSubrole
            || subrole == kAXUnknownSubrole {
            return false
        }
        return true
    }

    struct ServerWindow {
        let id: CGWindowID
        let pid: pid_t
        let name: String
    }

    /// Tek bir `CGWindowListCopyWindowInfo` okumasından türeyen iki görünüm.
    struct WindowServerList {
        /// Bütün masaüstlerindeki normal katman (0) pencereleri: saydam
        /// (alpha 0) ve 50 pt'den küçük olanlar elenmiş. Yardımcı/gizli
        /// pencereler sonra AX rol denetimiyle elenir.
        let windows: [ServerWindow]
        /// Sunucunun şu an bildiği bütün pencere numaraları (katman/boyut
        /// süzgeci yok) → sahip pid. Bir pencerenin hâlâ var olup olmadığını
        /// AX listesinden bağımsız söyler; AX listesi başka masaüstündeki
        /// pencereleri anlık kaçırabilir, sunucu kaçırmaz.
        let live: [CGWindowID: pid_t]
    }

    /// Pencere sunucusunu bir kez okur; tarama başına tek çağrı yeter.
    static func windowServerList() -> WindowServerList {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return WindowServerList(windows: [], live: [:]) }
        var windows: [ServerWindow] = []
        var live: [CGWindowID: pid_t] = [:]
        for entry in list {
            guard let (number, pid) = liveEntry(from: entry) else { continue }
            live[number] = pid
            if let window = serverWindow(from: entry) { windows.append(window) }
        }
        return WindowServerList(windows: windows, live: live)
    }

    /// Pencere sunucusu imzasının bir satırı: katman 0 penceresinin
    /// numarası, sahibi, tam sayıya yuvarlanmış sınırları, ekranda olup olmadığı.
    struct SignatureRow: Equatable {
        let id: CGWindowID
        let pid: pid_t
        let bounds: [Int]
        let onscreen: Bool
    }

    /// Zamanlayıcı turunun ucuz değişim denetimi için imza. Karşılaştırma
    /// satır satır yapılır; özet (hash) çakışması değişimi gizleyemez.
    struct WindowServerSignature: Equatable {
        let rows: [SignatureRow]
    }

    /// Zamanlayıcı turunun ucuz değişim denetimi: pencere sunucusunu tek
    /// çağrıyla okur, AX'e hiç sormaz. Okunamazsa nil (tam tarama yapılır).
    static func windowServerSignature() -> WindowServerSignature? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return serverSignature(list)
    }

    /// Sunucu listesinin imzası (saf). Numaraya göre sıralanır; odak
    /// değişince değişen z-sırası imzayı değiştirmez. Yeni/kapanan pencere,
    /// taşıma, boyut, simge durumu ve masaüstleri arası geçiş imzaya
    /// yansır; başlık yansımaz (başlık değişimi AX olayıyla gelir). Katman 0
    /// dışı kayıtlar (menü çubuğu, Dock, bildirimler) sürekli oynadığı için
    /// sayılmaz.
    static func serverSignature(_ list: [[String: Any]]) -> WindowServerSignature {
        var rows: [SignatureRow] = []
        for entry in list {
            guard let (number, pid) = liveEntry(from: entry),
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }
            var bounds: [Int] = []
            if let rect = entry[kCGWindowBounds as String] as? [String: Any] {
                bounds = ["X", "Y", "Width", "Height"].map {
                    Int(((rect[$0] as? Double) ?? 0).rounded())
                }
            }
            let onscreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            rows.append(SignatureRow(id: number, pid: pid, bounds: bounds, onscreen: onscreen))
        }
        rows.sort { $0.id < $1.id }
        return WindowServerSignature(rows: rows)
    }

    /// Sunucu kaydından pencere numarası ve sahip pid (saf); biri yoksa nil.
    /// `WindowServerList.live` için: katman/boyut süzgeci uygulanmaz.
    static func liveEntry(from entry: [String: Any]) -> (id: CGWindowID, pid: pid_t)? {
        guard let number = entry[kCGWindowNumber as String] as? UInt32,
              let pid = entry[kCGWindowOwnerPID as String] as? Int32
        else { return nil }
        return (number, pid)
    }

    /// Sunucu kaydını 2. aşama listelemesi için süzer (saf): numara ve pid
    /// zorunlu; katman 0 olmalı (yoksa ya da farklıysa elenir); alpha 0 ya
    /// da genişlik/yükseklik 50 pt'den küçükse elenir (alpha ya da sınırlar
    /// yoksa geçer); ad yoksa boş.
    static func serverWindow(from entry: [String: Any]) -> ServerWindow? {
        guard let (number, pid) = liveEntry(from: entry) else { return nil }
        guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
        if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha == 0 { return nil }
        if let bounds = entry[kCGWindowBounds as String] as? [String: Any],
           let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double,
           w < 50 || h < 50 {
            return nil
        }
        let name = entry[kCGWindowName as String] as? String ?? ""
        return ServerWindow(id: number, pid: pid, name: name)
    }

    /// Pencere sunucusunun şu an bildiği bütün pencere numaraları → sahip
    /// pid (bkz. `WindowServerList.live`). Açılışta oturum pinleri için.
    static func liveWindowIDs() -> [CGWindowID: pid_t] {
        windowServerList().live
    }

    static func isMinimized(_ window: AXWindow) -> Bool {
        let value: Bool? = attribute(window.element, kAXMinimizedAttribute)
        return value ?? false
    }

    /// Pencere çerçevesi; ekranın sol üst köşesi (0,0) olacak biçimde.
    static func frame(of window: AXWindow) -> CGRect? {
        guard let positionValue: AXValue = attribute(window.element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(window.element, kAXSizeAttribute)
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Çerçeve yazımı için öğe başına yanıt süresi. Okumalar süreç geneli
    /// 1 sn ile hızlı düşer (donmuş uygulama ilk çağrıda takılır ve
    /// `setFrame`'e gelmeden backoff'a alınır); yazım ise yavaş ama çalışan
    /// bir uygulamanın (büyük belge, yoğun tarayıcı) yeniden çizimi
    /// bitirmesini beklemeli, yoksa boyut hiç uygulanmaz.
    static let setFrameTimeout: Float = 3.0

    /// Pencereyi verilen çerçeveye (sol üst köşe tabanlı) taşır.
    static func setFrame(_ frame: CGRect, of window: AXWindow) {
        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }

        // Yazımlar için daha uzun süre; ardından sıfırlanır ki yazım sonrası
        // çerçeve okuması yine süreç geneli süreyle (1 sn) çalışsın.
        AXUIElementSetMessagingTimeout(window.element, setFrameTimeout)
        defer { AXUIElementSetMessagingTimeout(window.element, 0) }
        // Boyutu iki kez vermek, ekran sınırına takılan pencereler için gerekir.
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success
        else { return nil }
        return raw as? T
    }
}

// MARK: - Koordinatlar

enum Coordinates {

    /// Cocoa (sol alt köşe tabanlı) dikdörtgeni AX (sol üst köşe tabanlı)
    /// dikdörtgene çevirir.
    static func axRect(fromCocoa rect: CGRect, screens: [ScreenInfo]) -> CGRect {
        // Birincil ekranın sol alt köşesi (0,0); AX koordinatları onun
        // sol üst köşesinden başlar.
        let primaryHeight = screens.first { $0.frame.origin == .zero }?.frame.height
            ?? screens.first?.frame.height ?? 0
        return CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height)
    }

    static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// İki nokta yakın mı (yalnız konum; boyutu uygulamanın belirlediği
    /// sabit boyutlu yerleşim için).
    static func close(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 4) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }
}

/// `NSRunningApplication.activationPolicy` her okunuşta LaunchServices'e
/// eşzamanlı XPC yapar; her taramada yüzlerce süreç için sormak boşta
/// CPU'nun en büyük kalemiydi (sample, 19.09.2026). Sonuç pid başına
/// `ttl` süre saklanır; uygulama etkinleşince/kapanınca kayıt silinir.
final class ActivationPolicyCache: @unchecked Sendable {

    static let shared = ActivationPolicyCache()

    /// Politika değişimi (ör. sonradan Dock simgesi gösteren uygulama)
    /// en geç bu kadar sürede fark edilir.
    static let ttl: TimeInterval = 60

    private struct Entry { let regular: Bool; let at: Date }
    private let lock = NSLock()
    private var entries: [pid_t: Entry] = [:]

    func isRegular(_ app: NSRunningApplication, now: Date = Date()) -> Bool {
        isRegular(pid: app.processIdentifier, finishedLaunching: app.isFinishedLaunching,
                  now: now) { app.activationPolicy == .regular }
    }

    /// `fetch` yalnız kayıt yoksa ya da süresi dolduysa çağrılır. Açılışı
    /// bitmemiş uygulamanın politikası henüz kesin değil; saklanmaz.
    func isRegular(pid: pid_t, finishedLaunching: Bool, now: Date,
                   fetch: () -> Bool) -> Bool {
        lock.lock()
        if let entry = entries[pid], now.timeIntervalSince(entry.at) < Self.ttl {
            lock.unlock()
            return entry.regular
        }
        lock.unlock()
        let regular = fetch()
        guard finishedLaunching else { return regular }
        lock.lock(); defer { lock.unlock() }
        entries[pid] = Entry(regular: regular, at: now)
        return regular
    }

    func forget(_ pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        entries[pid] = nil
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }
}
