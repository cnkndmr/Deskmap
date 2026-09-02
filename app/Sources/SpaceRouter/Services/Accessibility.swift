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
    static func allWindows(timeout: Float = 1.0) -> [AXWindow] {
        var result: [AXWindow] = []

        for app in runningApps() {
            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)

            guard let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute)
            else { continue }

            for element in windows {
                let subrole: String? = attribute(element, kAXSubroleAttribute)
                if let subrole,
                   subrole == kAXFloatingWindowSubrole
                    || subrole == kAXSystemDialogSubrole
                    || subrole == kAXSystemFloatingWindowSubrole {
                    continue
                }
                let title: String = attribute(element, kAXTitleAttribute) ?? ""

                var windowID: CGWindowID = 0
                guard let getWindowID,
                      getWindowID(element, &windowID) == .success,
                      windowID != 0 else { continue }

                result.append(AXWindow(
                    id: windowID,
                    pid: app.pid,
                    appName: app.name,
                    bundleID: app.bundleID,
                    title: title,
                    element: element))
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
