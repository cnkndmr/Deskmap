import AppKit
import ApplicationServices
import Combine

/// Pencere olaylarını dinler: yeni pencere, başlık değişimi, odak değişimi,
/// simge durumundan çıkma, uygulama açılışı/etkinleşmesi ve masaüstü geçişi.
/// Router bu sinyallerle zamanlayıcıyı beklemeden tarama yapar.
@MainActor
final class WindowEvents {

    /// Olay adı ile tetiklenir.
    let changed = PassthroughSubject<String, Never>()
    /// Başlık değişimi ayrı: değişen pencerenin sahibi (pid) ile. Router
    /// yalnız başlığın önemli olduğu uygulamalarda tarar.
    let titleChanged = PassthroughSubject<pid_t, Never>()

    private var observers: [pid_t: AXObserver] = [:]
    /// Kaydı arka kuyrukta sürenler (ikinci kez gönderilmesin).
    private var registering: Set<pid_t> = []
    /// AX kaydı (gözlemci yaratma, bildirim ekleme, pencere listesi okuma)
    /// ana iş parçacığında değil burada yapılır; donmuş bir uygulama
    /// arayüzü kilitlemesin (P0-4). Seri: aynı anda tek uygulama.
    private let registrationQueue = DispatchQueue(label: "deskmap.ax-register", qos: .utility)
    /// Uygulama başına kayıt süre bütçesi: gözlemci ve bildirimler bu
    /// sürede eklenemediyse ya da aşıldıysa pencere başı başlık kaydı
    /// atlanır; kayıt hiç olmadıysa uygulama geri çekilmeye alınır.
    nonisolated static let registrationBudget: TimeInterval = 1.5
    // nonisolated(unsafe): yalnızca init'te (ana aktör) doldurulur, deinit'te
    // kaldırılır; gözlemci belirteçleri Sendable olmadığı için deinit erişimi
    // başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    /// Gözlemci takılamayan uygulama için bekleme: bir sonraki deneme
    /// zamanı ve o denemede kullanılacak gecikme (2 sn → 30 sn, ikiye
    /// katlanır). Uygulama açılınca/etkinleşince/kapanınca silinir.
    private struct Retry {
        var next: Date
        var delay: TimeInterval
    }
    private var retries: [pid_t: Retry] = [:]
    nonisolated static let minRetry: TimeInterval = 2
    nonisolated static let maxRetry: TimeInterval = 30
    /// Bu uygulamaya yapılan AX çağrılarının yanıt süresi (kayıt kuyruğu
    /// donmuş bir uygulamada uzun süre takılmasın).
    nonisolated private static let messagingTimeout: Float = 1.0

    nonisolated private static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    init() {
        let center = NSWorkspace.shared.notificationCenter

        tokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            AX.invalidateRunningApps()
            Task { @MainActor in
                guard let self else { return }
                if let app {
                    self.retries[app.processIdentifier] = nil
                    self.watch(app)
                }
                self.changed.send("launch")
            }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            AX.invalidateRunningApps()
            Task { @MainActor in
                if let app {
                    ActivationPolicyCache.shared.forget(app.processIdentifier)
                    self?.launching[app.processIdentifier] = nil
                    self?.retries[app.processIdentifier] = nil
                    self?.registering.remove(app.processIdentifier)
                    self?.unwatch(app.processIdentifier)
                }
            }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                guard let self else { return }
                // Etkinleşen uygulama artık yanıt veriyordur; beklemeyi kaldır,
                // kaydı zamanlayıcının `refresh()` turu yapar.
                if let app {
                    self.retries[app.processIdentifier] = nil
                    ActivationPolicyCache.shared.forget(app.processIdentifier)
                }
                self.changed.send("activate")
            }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.changed.send("space") }
        })

        refresh()
    }

    /// Shots modu (`--shots`): hiçbir gözlemci eklenmez, `refresh()`
    /// çağrılmaz. Üretim `init()`'i değişmez.
    init(demo: Bool) {}

    deinit {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    /// Henüz izlenmeyen uygulamalara gözlemci takar. Yeni açılan bir
    /// uygulama Accessibility'ye hemen yanıt vermeyebilir; bu yüzden
    /// Router zamanlayıcısından düzenli olarak çağrılır.
    func refresh() {
        guard AXIsProcessTrusted() else { return }
        lastRefresh = Date()
        for app in NSWorkspace.shared.runningApplications { watch(app) }
    }

    /// Zamanlayıcı turu: bütün süreçleri gezmek pahalı (her
    /// `NSRunningApplication` özelliği XPC), bu yüzden yalnız bekleyen bir
    /// yeniden deneme vakti geldiyse ya da `refreshInterval` dolduysa.
    /// Yeni açılan uygulama zaten açılış bildirimiyle izlenir.
    func refreshIfDue(now: Date = Date()) {
        for entry in launching.values where now.timeIntervalSince(entry.since) <= Self.launchWait {
            watch(entry.app)
        }
        if Self.shouldRefresh(now: now, lastRefresh: lastRefresh,
                              nextRetry: retries.values.map(\.next).min()) {
            refresh()
        }
    }

    private var lastRefresh = Date.distantPast
    /// Açılışı henüz bitmemiş, izlenmeyi bekleyen uygulamalar.
    /// Arka plan ajanları çoğu zaman hiç "açılışı bitti" demez; bu yüzden
    /// en fazla `launchWait` sık bakılır; sonra kayıt kalır ama yalnız
    /// 5 dakikalık tam turda denenir (kapanınca silinir).
    private var launching: [pid_t: (app: NSRunningApplication, since: Date)] = [:]
    nonisolated static let launchWait: TimeInterval = 20
    nonisolated static let refreshInterval: TimeInterval = 300

    /// Tur kararı (saf).
    nonisolated static func shouldRefresh(now: Date, lastRefresh: Date, nextRetry: Date?) -> Bool {
        if let nextRetry, now >= nextRetry { return true }
        return now.timeIntervalSince(lastRefresh) >= refreshInterval
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        // Önce ucuz denetimler: çoğu süreç zaten izleniyordur.
        guard observers[pid] == nil,
              !registering.contains(pid),
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        guard app.isFinishedLaunching else {
            // Açılışı bitmemiş uygulama AX'e henüz yanıt vermez (politikası da
            // kesin değil); zamanlayıcı turunda yalnız ona yeniden bakılır.
            if launching[pid] == nil { launching[pid] = (app, Date()) }
            return
        }
        launching[pid] = nil
        guard ActivationPolicyCache.shared.isRegular(app) else { return }
        let now = Date()
        if let retry = retries[pid], retry.next > now { return }

        registering.insert(pid)
        let refcon = UnsafeSendablePointer(Unmanaged.passUnretained(self).toOpaque())
        registrationQueue.async { [weak self] in
            let result = Self.register(pid: pid, refcon: refcon.pointer)
            Task { @MainActor in self?.finishRegistration(app, result: result) }
        }
    }

    /// Arka kuyruktaki kaydın sonucu.
    private struct Registration: @unchecked Sendable {
        /// nil: gözlemci yaratılamadı ya da hiçbir bildirim eklenemedi.
        let observer: AXObserver?
        let elapsed: TimeInterval
        /// Bütçe aşıldığı için mevcut pencerelere başlık kaydı yapılmadı.
        let skippedWindows: Bool
    }

    /// `AXObserverCreate`, bildirim kayıtları ve `kAXWindows` okuması (arka
    /// kuyruk; ana aktöre dokunmaz). Run loop kaynağı burada eklenmez.
    nonisolated private static func register(pid: pid_t, refcon: UnsafeMutableRawPointer)
        -> Registration {
        let start = Date()
        var created: AXObserver?
        guard AXObserverCreate(pid, WindowEvents.callback, &created) == .success,
              let observer = created
        else { return Registration(observer: nil, elapsed: Date().timeIntervalSince(start),
                                   skippedWindows: false) }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        var added = false
        for name in appNotifications {
            if AXObserverAddNotification(observer, appElement, name as CFString, refcon) == .success {
                added = true
            }
        }
        guard added else {
            return Registration(observer: nil, elapsed: Date().timeIntervalSince(start),
                                skippedWindows: false)
        }

        // Başlık değişimi pencere öğesine bağlanır; mevcut pencereler için de
        // tak. Bütçe aşıldıysa atlanır (başlık değişimleri zamanlayıcının
        // boşta taramasıyla yine yakalanır).
        let overBudget = Date().timeIntervalSince(start) > registrationBudget
        if !overBudget {
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw)
                == .success, let windows = raw as? [AXUIElement] {
                for window in windows {
                    _ = AXObserverAddNotification(observer, window,
                                                  kAXTitleChangedNotification as CFString, refcon)
                }
            }
        }
        return Registration(observer: observer, elapsed: Date().timeIntervalSince(start),
                            skippedWindows: overBudget)
    }

    /// Ana aktörde: hazır gözlemcinin run loop kaynağı ana run loop'a eklenir.
    /// Kayıt sürerken uygulama kapandıysa sonuç atılır.
    private func finishRegistration(_ app: NSRunningApplication, result: Registration) {
        let pid = app.processIdentifier
        guard registering.remove(pid) != nil, !app.isTerminated else { return }
        let now = Date()
        guard let observer = result.observer else {
            deferRetry(pid, app: app, now: now,
                       slow: result.elapsed > Self.registrationBudget)
            return
        }
        if result.skippedWindows {
            Log.ax.notice("""
                Window observer for \(app.localizedName ?? "?", privacy: .public) (pid \(pid)) \
                took \(result.elapsed, format: .fixed(precision: 1)) s; per-window title \
                observers skipped
                """)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        retries[pid] = nil
        changed.send("observer")
    }

    /// Kayıt başarısız: bu uygulama artan aralıkla (2 → 30 sn) sonra denenir.
    /// `slow`: kayıt bütçeyi aştı; bekleme en uzun süreden başlar.
    private func deferRetry(_ pid: pid_t, app: NSRunningApplication, now: Date, slow: Bool = false) {
        let delay = Self.retryDelay(previous: retries[pid]?.delay, slow: slow)
        retries[pid] = Retry(next: now.addingTimeInterval(delay), delay: delay)
        if delay == Self.minRetry || slow {
            Log.ax.info("""
                Could not attach window observer to \(app.localizedName ?? "?", privacy: .public) \
                (pid \(pid)); retrying in \(delay, format: .fixed(precision: 0)) s
                """)
        }
    }

    /// Bir sonraki kayıt denemesine kadar bekleme (saf): 2 sn'den başlar,
    /// ikiye katlanır, 30 sn'de durur; bütçeyi aşan kayıtta hemen 30 sn.
    nonisolated static func retryDelay(previous: TimeInterval?, slow: Bool) -> TimeInterval {
        if slow { return maxRetry }
        return min(previous.map { $0 * 2 } ?? minRetry, maxRetry)
    }

    private func unwatch(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    nonisolated private static let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon else { return }
        let events = Unmanaged<WindowEvents>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        if name == kAXWindowCreatedNotification {
            // Yeni pencerenin başlığı çoğu zaman biraz sonra gelir; onu da dinle.
            _ = AXObserverAddNotification(observer, element,
                                          kAXTitleChangedNotification as CFString, refcon)
        }
        if name == kAXTitleChangedNotification {
            var pid: pid_t = 0
            _ = AXUIElementGetPid(element, &pid)
            Task { @MainActor in events.titleChanged.send(pid) }
            return
        }
        Task { @MainActor in events.changed.send(name) }
    }
}

/// Ham işaretçiyi kayıt kuyruğuna taşımak için (yalnız `refcon` olarak
/// AX'e verilir, kuyrukta çözülmez).
private struct UnsafeSendablePointer: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    init(_ pointer: UnsafeMutableRawPointer) { self.pointer = pointer }
}
