import AppKit
import ApplicationServices
import Combine

// MARK: - İzin

/// Accessibility izninin durumunu izler.
@MainActor
final class AccessibilityPermission: ObservableObject {

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = AXIsProcessTrusted()
                if now != self.isTrusted { self.isTrusted = now }
            }
        }
    }

    deinit { timer?.invalidate() }

    func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
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

    // MARK: - Yanıt vermeyen uygulamalar

    /// Bir uygulama Accessibility sorularına bu kadar sürede yanıt vermezse
    /// (donmuş, hata ayıklayıcıda duran) sonraki taramalarda bir süre
    /// atlanır; süre her tekrarında ikiye katlanır (2 sn → 30 sn).
    private struct Backoff {
        var until: Date
        var delay: TimeInterval
        let name: String
    }

    private static var backoffs: [pid_t: Backoff] = [:]
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
                    \(name, privacy: .public) (pid \(pid)) yanıt vermiyor: en uzun çağrı \
                    \(timing.maxCall, format: .fixed(precision: 2)) sn, toplam \
                    \(timing.total, format: .fixed(precision: 2)) sn; \(delay, format: .fixed(precision: 0)) sn atlanacak
                    """)
            }
        } else {
            backoffs[pid] = nil
            if previous != nil {
                Log.ax.notice("\(name, privacy: .public) (pid \(pid)) yeniden yanıt veriyor")
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

    /// Pencere numarasından AX öğesi üretir. Belirteç: 20 bayt —
    /// pid (4), 0 (4), "coco" 0x636f636f (4), windowID (4), 0 (4).
    static func element(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }
        var token = [UInt8](repeating: 0, count: 20)
        func put(_ value: UInt32, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes in
                for (i, byte) in bytes.enumerated() { token[offset + i] = byte }
            }
        }
        put(UInt32(bitPattern: pid), at: 0)
        put(0x636f636f, at: 8)
        put(UInt32(windowID), at: 12)
        let data = Data(token) as CFData
        return createWithRemoteToken(data)?.takeRetainedValue()
    }

    /// Dock'ta görünen bir uygulama.
    struct App: Identifiable, Hashable {
        let pid: pid_t
        let name: String
        let bundleID: String
        var id: pid_t { pid }
    }

    /// Dock'ta görünen, çalışan bütün uygulamalar (kendimiz hariç).
    static func runningApps() -> [App] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
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
        for info in (server ?? windowServerList()).windows {
            guard !seen.contains(info.id), let app = byPID[info.pid],
                  let element = element(pid: app.pid, windowID: info.id)
            else { continue }
            let pid = app.pid
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
            guard let number = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32
            else { continue }
            live[number] = pid

            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }
            if let bounds = entry[kCGWindowBounds as String] as? [String: Any],
               let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double,
               w < 50 || h < 50 {
                continue
            }
            let name = entry[kCGWindowName as String] as? String ?? ""
            windows.append(ServerWindow(id: number, pid: pid, name: name))
        }
        return WindowServerList(windows: windows, live: live)
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

    /// Pencereyi verilen çerçeveye (sol üst köşe tabanlı) taşır.
    static func setFrame(_ frame: CGRect, of window: AXWindow) {
        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }

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
}
