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
    static func allWindows(timeout: Float = 1.0,
                           alwaysInclude: Set<CGWindowID> = []) -> [AXWindow] {
        var result: [AXWindow] = []
        var seen: Set<CGWindowID> = []
        let apps = runningApps()

        // 1. Uygulamanın kendi listesi (görünen masaüstündekiler kesin).
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)

            guard let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute)
            else { continue }

            for element in windows {
                guard isStandardWindow(element) else { continue }
                let title: String = attribute(element, kAXTitleAttribute) ?? ""

                var windowID: CGWindowID = 0
                guard let getWindowID,
                      getWindowID(element, &windowID) == .success,
                      windowID != 0, !seen.contains(windowID) else { continue }
                seen.insert(windowID)

                result.append(AXWindow(
                    id: windowID,
                    pid: app.pid,
                    appName: app.name,
                    bundleID: app.bundleID,
                    title: title,
                    element: element))
            }
        }

        // 2. Uygulamanın listelemediği pencereler (başka masaüstü / ekran):
        //    pencere sunucusundan numaralarını alıp uzak belirteçle AX
        //    öğesi üret.
        let byPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0) })
        for info in windowServerWindows() {
            guard !seen.contains(info.id), let app = byPID[info.pid],
                  let element = element(pid: app.pid, windowID: info.id)
            else { continue }
            AXUIElementSetMessagingTimeout(element, timeout)
            guard alwaysInclude.contains(info.id) || isStandardWindow(element, strict: true)
            else { continue }
            let title: String = attribute(element, kAXTitleAttribute) ?? info.name
            seen.insert(info.id)
            result.append(AXWindow(
                id: info.id,
                pid: app.pid,
                appName: app.name,
                bundleID: app.bundleID,
                title: title,
                element: element))
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

    private struct ServerWindow {
        let id: CGWindowID
        let pid: pid_t
        let name: String
    }

    /// Pencere sunucusunun bildiği, bütün masaüstlerindeki normal katman
    /// (0) pencereleri. Yardımcı/gizli pencereler AX rol denetimiyle elenir.
    private static func windowServerWindows() -> [ServerWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32
            else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha == 0 { return nil }
            if let bounds = entry[kCGWindowBounds as String] as? [String: Any],
               let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double,
               w < 50 || h < 50 {
                return nil
            }
            let name = entry[kCGWindowName as String] as? String ?? ""
            return ServerWindow(id: number, pid: pid, name: name)
        }
    }

    /// Pencere sunucusunun şu an bildiği bütün pencere numaraları (tüm
    /// masaüstleri, katman/boyut süzgeci yok) → sahip pid. Bir pencerenin
    /// hâlâ var olup olmadığını AX listesinden bağımsız söyler; AX listesi
    /// başka masaüstündeki pencereleri anlık kaçırabilir, sunucu kaçırmaz.
    static func liveWindowIDs() -> [CGWindowID: pid_t] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var result: [CGWindowID: pid_t] = [:]
        for entry in list {
            if let number = entry[kCGWindowNumber as String] as? UInt32,
               let pid = entry[kCGWindowOwnerPID as String] as? Int32 {
                result[number] = pid
            }
        }
        return result
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
