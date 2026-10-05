import CoreGraphics
import Foundation

/// Bir pencere bir ekrandan ötekine geçtiğinde kullanıcının komutunu çalıştırır.
/// Tanımlar `hooks.json`'da (rules.json ile aynı klasör):
///
///     [{"app": "cmux", "from": "*", "to": "builtin", "run": "~/bin/cmux-layout grid"}]
///
/// `app` bundle kimliği ya da uygulama adı; `from`/`to` ekran rol kimliği
/// (builtin, external, external-2 …) ya da ekran adı. `*` ya da alanın hiç
/// olmaması her şeye uyar. Komut `/bin/sh -c` ile, arka planda çalışır.
struct ScreenHook: Codable, Equatable {
    var app: String?
    var from: String?
    var to: String?
    var run: String

    func matches(_ change: ScreenChange) -> Bool {
        Self.field(app, matches: [change.bundleID, change.appName])
            && Self.field(from, matches: [change.from.id, change.from.name])
            && Self.field(to, matches: [change.to.id, change.to.name])
    }

    private static func field(_ pattern: String?, matches values: [String]) -> Bool {
        guard let pattern = pattern?.trimmingCharacters(in: .whitespaces),
              !pattern.isEmpty, pattern != "*" else { return true }
        return values.contains { $0.caseInsensitiveCompare(pattern) == .orderedSame }
    }
}

/// Bir pencerenin ekran değiştirmesi.
struct ScreenChange: Equatable {
    struct Screen: Equatable {
        let id: String
        let name: String
    }
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String
    let from: Screen
    let to: Screen

    /// İki tarama arasında ekranı değişen pencereler. Yalnız iki taramada da
    /// görülen, ikisinde de normal masaüstünde olan pencereler sayılır (yeni
    /// açılan, tam ekrana geçen, simge durumundaki pencere tetiklemez). Ekran
    /// listesi değiştiyse (monitör takıldı/çıkarıldı) hiç sayılmaz: o
    /// taşımayı kullanıcı değil sistem yapmıştır.
    static func detect(old: [Router.WindowSnapshot], new: [Router.WindowSnapshot],
                       oldScreens: [ScreenInfo], newScreens: [ScreenInfo]) -> [ScreenChange] {
        guard !old.isEmpty, oldScreens.map(\.id) == newScreens.map(\.id) else { return [] }
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(newScreens.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return new.compactMap { window in
            guard let prev = before[window.id],
                  !window.isMinimized, !prev.isMinimized,
                  window.fullscreen == nil, prev.fullscreen == nil,
                  let to = window.placement?.screen, let from = prev.placement?.screen,
                  to != from
            else { return nil }
            return ScreenChange(windowID: window.id, pid: window.pid,
                                appName: window.appName, bundleID: window.bundleID,
                                from: Screen(id: from, name: names[from] ?? from),
                                to: Screen(id: to, name: names[to] ?? to))
        }
    }

    /// Komuta verilen ortam değişkenleri.
    var environment: [String: String] {
        ["DESKMAP_APP": appName, "DESKMAP_BUNDLE_ID": bundleID,
         "DESKMAP_PID": String(pid), "DESKMAP_WINDOW_ID": String(windowID),
         "DESKMAP_FROM": from.id, "DESKMAP_FROM_NAME": from.name,
         "DESKMAP_TO": to.id, "DESKMAP_TO_NAME": to.name]
    }
}

/// `hooks.json`'u okur (değiştiyse yeniden) ve eşleşen komutları çalıştırır.
@MainActor
final class ScreenHooks {


    private let url: URL
    private var hooks: [ScreenHook] = []
    private var loadedStamp: Date?

    init(url: URL) {
        self.url = url
    }

    func fire(_ changes: [ScreenChange]) {
        guard !changes.isEmpty else { return }
        reloadIfNeeded()
        for change in changes {
            Log.routing.notice("""
                Screen change: \(change.appName, privacy: .public) window \(change.windowID) \
                \(change.from.id, privacy: .public) → \(change.to.id, privacy: .public)
                """)
            for hook in hooks where hook.matches(change) {
                Self.launch(hook.run, environment: change.environment)
            }
        }
    }

    private func reloadIfNeeded() {
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        guard stamp != loadedStamp else { return }
        loadedStamp = stamp
        guard stamp != nil, let data = try? Data(contentsOf: url) else {
            hooks = []
            return
        }
        do {
            hooks = try JSONDecoder().decode([ScreenHook].self, from: data)
            Log.app.notice("Loaded \(self.hooks.count) screen hook(s)")
        } catch {
            hooks = []
            Log.app.error("hooks.json unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func launch(_ command: String, environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ProcessInfo.processInfo.environment
            .merging(environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            if status != 0 {
                Log.app.error("Screen hook exited \(status): \(command, privacy: .public)")
            }
        }
        do {
            try process.run()
            Log.app.notice("Screen hook started: \(command, privacy: .public)")
        } catch {
            Log.app.error("Screen hook failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }
}
