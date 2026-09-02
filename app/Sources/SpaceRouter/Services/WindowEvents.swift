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
    private var tokens: [NSObjectProtocol] = []

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
                if let app { self.watch(app) }
                self.changed.send("launch")
            }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                if let app { self?.unwatch(app.processIdentifier) }
            }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.changed.send("activate") }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.changed.send("space") }
        })

        refresh()
    }

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
        guard app.activationPolicy == .regular,
              pid != ProcessInfo.processInfo.processIdentifier,
              observers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, WindowEvents.callback, &observer) == .success,
              let observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        var added = false
        for name in Self.appNotifications {
            if AXObserverAddNotification(observer, appElement, name as CFString, refcon) == .success {
                added = true
            }
        }
        guard added else { return }

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
