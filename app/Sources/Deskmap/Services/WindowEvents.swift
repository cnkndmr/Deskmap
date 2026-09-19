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

    private var observers: [pid_t: AXObserver] = [:]
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
    private static let minRetry: TimeInterval = 2
    private static let maxRetry: TimeInterval = 30
    /// Bu uygulamaya yapılan AX çağrılarının yanıt süresi; kayıt ana
    /// iş parçacığında yapıldığı için donmuş uygulama arayüzü kilitlemesin.
    private static let messagingTimeout: Float = 1.0

    private static let appNotifications: [String] = [
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
            Task { @MainActor in
                if let app {
                    self?.retries[app.processIdentifier] = nil
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
                if let app { self.retries[app.processIdentifier] = nil }
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
        for app in NSWorkspace.shared.runningApplications { watch(app) }
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        // Önce ucuz denetimler: zamanlayıcı her turda bütün süreçleri gezer,
        // çoğu zaten izleniyordur.
        guard observers[pid] == nil,
              pid != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular,
              // Açılışı bitmemiş uygulama AX'e henüz yanıt vermez; zamanlayıcı
              // bir sonraki turda yeniden dener.
              app.isFinishedLaunching else { return }
        let now = Date()
        if let retry = retries[pid], retry.next > now { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, WindowEvents.callback, &observer) == .success,
              let observer else { deferRetry(pid, app: app, now: now); return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        var added = false
        for name in Self.appNotifications {
            if AXObserverAddNotification(observer, appElement, name as CFString, refcon) == .success {
                added = true
            }
        }
        guard added else { deferRetry(pid, app: app, now: now); return }

        // Başlık değişimi pencere öğesine bağlanır; mevcut pencereler için de tak.
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw) == .success,
           let windows = raw as? [AXUIElement] {
            for window in windows {
                _ = AXObserverAddNotification(observer, window,
                                              kAXTitleChangedNotification as CFString, refcon)
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        retries[pid] = nil
    }

    /// Kayıt başarısız: bu uygulama artan aralıkla (2 → 30 sn) sonra denenir.
    private func deferRetry(_ pid: pid_t, app: NSRunningApplication, now: Date) {
        let delay = min((retries[pid]?.delay).map { $0 * 2 } ?? Self.minRetry, Self.maxRetry)
        retries[pid] = Retry(next: now.addingTimeInterval(delay), delay: delay)
        if delay == Self.minRetry {
            Log.ax.info("""
                Could not attach window observer to \(app.localizedName ?? "?", privacy: .public) \
                (pid \(pid)); retrying in \(delay, format: .fixed(precision: 0)) s
                """)
        }
    }

    private func unwatch(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private static let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon else { return }
        let events = Unmanaged<WindowEvents>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        if name == kAXWindowCreatedNotification {
            // Yeni pencerenin başlığı çoğu zaman biraz sonra gelir; onu da dinle.
            _ = AXObserverAddNotification(observer, element,
                                          kAXTitleChangedNotification as CFString, refcon)
        }
        Task { @MainActor in events.changed.send(name) }
    }
}
