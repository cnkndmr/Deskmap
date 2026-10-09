import AppKit
import ApplicationServices

/// Kapalı pinli pencereyi yeniden açmak için hatırlanan hedef: pencere
/// açıkken okunan dosya yolu, klasör ya da sayfa adresi. Kuraldan ayrı
/// (`reopen.json`) tutulur: kural değişince Router bütün pencereleri
/// yeniden yerleştirir ve geri alma kaydı düşer; adres her sayfa
/// değişiminde güncellenebilir.
struct ReopenTarget: Codable, Equatable, Hashable {
    /// file:// ya da http(s):// adresi.
    var url: String
    var seenAt: Date
}

enum Reopen {

    /// Sayfa adresi okunan tarayıcılar (AXWebArea'nın AXURL'i).
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser",
    ]
    static let finder = "com.apple.finder"
    static let vsCode = "com.microsoft.VSCode"

    /// Pencerenin şu an gösterdiği şey (arka plan kuyruğunda çağrılır):
    /// belge uygulamalarında AXDocument, Finder'da yol çubuğunun son öğesi,
    /// tarayıcıda sayfa adresi. VS Code'da dosya yerine başlıktaki klasör
    /// (" — Klasör") açılır ki aynı çalışma alanı gelsin.
    static func capture(_ window: AXUIElement, bundleID: String, title: String) -> URL? {
        if bundleID == finder {
            // Özel konum (Recents…) başlıktan; ağacı dolaşmaya gerek yok (Recents
            // listesi binlerce öğe, dolaşmak dakikalar sürüyordu, 08.10).
            return finderLocation(named: title) ?? finderFolder(window, title: title)
        }
        if browsers.contains(bundleID) { return webAddress(window) }
        guard let raw = value(window, kAXDocumentAttribute) else { return nil }
        let text = (raw as? String) ?? (raw as? URL)?.absoluteString ?? ""
        guard let url = URL(string: text), url.isFileURL else { return nil }
        if bundleID == vsCode, let folder = workspaceFolder(of: url, title: title) { return folder }
        return url
    }

    /// Finder'ın klasör olmayan konumları (Recents, AirDrop, iCloud Drive,
    /// Network, Computer): Finder.app içindeki küçük uygulamalar; açılınca
    /// Finder o konumun penceresini açar.
    static let finderLocations = URL(
        fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications")

    static func finderLocation(named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let app = finderLocations.appendingPathComponent("\(trimmed).app")
        return FileManager.default.fileExists(atPath: app.path) ? app : nil
    }

    /// "dosya — Klasör" başlığındaki klasör, dosyanın üst klasörlerinden biriyse.
    static func workspaceFolder(of file: URL, title: String) -> URL? {
        guard let name = title.components(separatedBy: " — ").last?
            .trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        var dir = file.deletingLastPathComponent()
        while dir.path != "/" {
            if dir.lastPathComponent == name { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// Finder: yol çubuğu (AXList içindeki AXStaticText'lerin AXURL'i, kökten
    /// açık klasöre; dosya seçiliyse sonunda o dosya). Dosya referansları
    /// (/.file/id=…) gerçek yola çevrilir. Sütun görünümündeki listeler de
    /// AXStaticText taşıyabildiği için yalnız her öğenin bir öncekinin içinde
    /// olduğu zincir kabul edilir; zincirdeki son klasör döner. Yol çubuğu
    /// kapalıysa nil.
    private static func finderFolder(_ window: AXUIElement, title: String) -> URL? {
        // Dosya listeleri (AXScrollArea/AXOutline/AXTable/AXBrowser ve uzun
        // AXList'ler) dolaşılmaz; yol çubuğu kısa bir AXList. Süre sınırı da var.
        let deadline = Date().addingTimeInterval(0.3)
        let skipped: Set<String> = ["AXScrollArea", "AXOutline", "AXTable", "AXBrowser", "AXWebArea"]
        var found: URL?
        func walk(_ element: AXUIElement, depth: Int) {
            guard found == nil, depth > 0, Date() < deadline else { return }
            for child in children(element) {
                guard Date() < deadline else { return }
                let role = value(child, kAXRoleAttribute) as? String ?? ""
                if skipped.contains(role) { continue }
                if role == "AXList" {
                    let items = children(child)
                    if items.count <= 40, let folder = pathBarFolder(items, title: title) {
                        found = folder
                        return
                    }
                    continue
                }
                walk(child, depth: depth - 1)
                if found != nil { return }
            }
        }
        walk(window, depth: 6)
        return found
    }

    private static func pathBarFolder(_ items: [AXUIElement], title: String) -> URL? {
        let urls = items.compactMap { item -> URL? in
            guard (value(item, kAXRoleAttribute) as? String) == kAXStaticTextRole,
                  let raw = value(item, "AXURL"),
                  let reference = (raw as? URL) ?? URL(string: "\(raw)") else { return nil }
            return (reference as NSURL).filePathURL ?? reference
        }
        return chainFolder(urls.count == items.count ? urls : [], title: title)
    }

    /// Kökten başlayan iç içe yol zincirinde pencerenin klasörü (saf):
    /// adı başlıkla aynı olan en derin öğe (seçili alt klasör/dosya varsa
    /// zincirin sonu odur, açık klasör değil); yoksa son klasör. Zincir
    /// değilse nil.
    static func chainFolder(_ urls: [URL], title: String) -> URL? {
        guard urls.count >= 2 else { return nil }
        let paths = urls.map { $0.standardizedFileURL.path }
        for (parent, child) in zip(paths, paths.dropFirst()) {
            let prefix = parent.hasSuffix("/") ? parent : parent + "/"
            guard child.hasPrefix(prefix) else { return nil }
        }
        if let named = urls.last(where: { $0.lastPathComponent == title }) {
            return URL(fileURLWithPath: named.path, isDirectory: true)
        }
        for url in urls.reversed() {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: url.path, isDirectory: true)
            }
        }
        return nil
    }

    /// Tarayıcı: ilk AXWebArea'nın AXURL'i (sekme içeriği).
    private static func webAddress(_ window: AXUIElement) -> URL? {
        let deadline = Date().addingTimeInterval(1.5)
        func walk(_ element: AXUIElement, depth: Int) -> URL? {
            guard depth > 0, Date() < deadline else { return nil }
            for child in children(element) {
                if (value(child, kAXRoleAttribute) as? String) == "AXWebArea",
                   let raw = value(child, "AXURL") {
                    let url = (raw as? URL) ?? URL(string: "\(raw)")
                    if let url, url.scheme == "http" || url.scheme == "https" { return url }
                }
                if let found = walk(child, depth: depth - 1) { return found }
            }
            return nil
        }
        return walk(window, depth: 14)
    }

    /// Kapalı pinli pencereyi açar: hatırlanan adres varsa onu kuralın
    /// uygulamasıyla, yoksa yalnız uygulamayı. Açılan pencereyi Router
    /// pinli masaüstüne kendisi yerleştirir. Uygulama bulunamazsa false.
    enum OpenResult { case opened, appOnly, noApp }

    @MainActor
    static func open(rule: Rule, target: ReopenTarget?) -> OpenResult {
        let workspace = NSWorkspace.shared
        let byName = ["/Applications", "/System/Applications"]
            .map { URL(fileURLWithPath: "\($0)/\(rule.appName).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        let appURL = rule.bundleID.isEmpty
            ? byName : workspace.urlForApplication(withBundleIdentifier: rule.bundleID) ?? byName
        guard let appURL else { return .noApp }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        var url = target.flatMap { URL(string: $0.url) } ?? rule.path.map { URL(fileURLWithPath: $0) }
        if let file = url, file.isFileURL, !FileManager.default.fileExists(atPath: file.path) {
            url = nil
        }
        // Finder'ın özel konumu (Recents…): başlıktan, hatırlanan hedef yoksa da.
        if rule.bundleID == finder, url == nil,
           let location = rule.tokens.lazy.compactMap({ finderLocation(named: $0) }).first {
            workspace.openApplication(at: location, configuration: configuration)
            return .opened
        }
        if let url, url.pathExtension == "app", url.path.hasPrefix(finderLocations.path) {
            workspace.openApplication(at: url, configuration: configuration)
            return .opened
        }
        if let url {
            workspace.open([url], withApplicationAt: appURL, configuration: configuration)
            return .opened
        }
        // Hedef bilinmiyor: çalışan uygulamada yalnız öne gelir, yeni pencere
        // açılmaz (Finder böyle). Kullanıcıya söylenir.
        let running = !NSRunningApplication.runningApplications(
            withBundleIdentifier: rule.bundleID).isEmpty
        workspace.openApplication(at: appURL, configuration: configuration)
        return running && !rule.isAppWide ? .appOnly : .opened
    }

    // MARK: - Safari

    static let safari = "com.apple.Safari"

    /// Safari'de kapalı pinli pencereyi açar. Dışarıdan gönderilen adres
    /// öndeki (çoğu zaman başka masaüstündeki) pencerede sekme olur; menüden
    /// "New Window" ise öndeki pencerenin sekme grubunda açılır ve grubun
    /// sekmelerini (oynayan video dahil) o pencereye çeker (ölçüldü 08.10).
    /// Bu yüzden adres AppleScript `make new document` ile hiçbir gruba bağlı
    /// olmayan ayrı pencerede açılır; başlık pinin parçasını (çoğu zaman
    /// sekme grubu adı) taşımayabileceği için yeni pencere bir kez pinli
    /// masaüstüne taşınır (oturum pini yazılmaz: kalıcı kilit olmasın). Sekme grubunun kendisi geri
    /// getirilmez (Safari bunu otomasyona açmıyor). İlk kullanımda macOS
    /// "Deskmap Safari'yi denetlemek istiyor" izni sorar.
    @MainActor
    static func openSafari(rule: Rule, target: ReopenTarget?, destination: Destination?,
                           router: Router) async -> Bool {
        let address = target.flatMap { URL(string: $0.url) }.flatMap {
            $0.scheme == "http" || $0.scheme == "https" ? $0.absoluteString : nil
        }
        let before = NSRunningApplication.runningApplications(withBundleIdentifier: safari).first
            .map { windowIDs(pid: $0.processIdentifier) } ?? []
        let escaped = (address ?? "").replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = address == nil
            ? "tell application id \"\(safari)\" to make new document"
            : "tell application id \"\(safari)\" to make new document with properties {URL:\"\(escaped)\"}"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.app.error("Safari reopen failed: \(error, privacy: .public)")
            return false
        }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: safari)
                .first?.processIdentifier else { return false }
        NSRunningApplication(processIdentifier: pid)?.activate()
        var window: CGWindowID?
        for _ in 0..<30 where window == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
            window = windowIDs(pid: pid).subtracting(before).first
        }
        guard let window else { return true }
        if let destination {
            for _ in 0..<30 where !router.windows.contains(where: { $0.id == window }) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Tek seferlik taşıma: oturum pini pencereyi bu kuruluma
            // kilitlerdi; sonrasında pencere kurala normal uyar.
            router.moveWindow(window, to: Router.Placement(screen: destination.screen,
                                                          desktop: destination.desktop))
        }
        return true
    }

    /// Uygulamanın pencere sunucusundaki normal pencereleri (bütün masaüstleri).
    private static func windowIDs(pid: pid_t) -> Set<CGWindowID> {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return Set(list.compactMap { entry -> CGWindowID? in
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  (bounds["Height"] as? Double ?? 0) > 100 else { return nil }
            return entry[kCGWindowNumber as String] as? CGWindowID
        })
    }

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success
        else { return nil }
        return result
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
