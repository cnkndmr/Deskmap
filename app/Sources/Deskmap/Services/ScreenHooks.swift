import AppKit
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


    /// Komuta verilen ortam değişkenleri.
    var environment: [String: String] {
        ["DESKMAP_APP": appName, "DESKMAP_BUNDLE_ID": bundleID,
         "DESKMAP_PID": String(pid), "DESKMAP_WINDOW_ID": String(windowID),
         "DESKMAP_FROM": from.id, "DESKMAP_FROM_NAME": from.name,
         "DESKMAP_TO": to.id, "DESKMAP_TO_NAME": to.name]
    }
}

/// Her pencerenin en son görüldüğü ekran. Yalnız bir önceki taramayla
/// karşılaştırmak yetmez: yanıt vermeyen uygulama birkaç tarama atlanır, o
/// arada pencere listeden düşer ve geri gelince yeni sanılırdı (geçiş
/// kaybolurdu). Burada `forgetAfter` boyunca hatırlanır.
struct ScreenMemory {
    struct Entry: Equatable {
        var screen: String
        var seen: Date
    }

    static let forgetAfter: TimeInterval = 60

    private(set) var entries: [CGWindowID: Entry] = [:]
    private var screenIDs: [String]?

    /// Taramayı işler, ekranı değişen pencereleri döner. Yalnız normal
    /// masaüstündeki pencereler sayılır (simge durumundaki ve tam ekran
    /// pencere ne tetikler ne kaydedilir); ilk kez görülen pencere tetiklemez.
    /// Ekran listesi değiştiyse (monitör takıldı/çıkarıldı) hiç sayılmaz: o
    /// taşımayı kullanıcı değil sistem yapmıştır.
    mutating func update(windows: [Router.WindowSnapshot], screens: [ScreenInfo],
                         now: Date = Date()) -> [ScreenChange] {
        let ids = screens.map(\.id)
        let screensStable = screenIDs == ids
        screenIDs = ids
        let names = Dictionary(screens.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var changes: [ScreenChange] = []
        for window in windows {
            guard !window.isMinimized, window.fullscreen == nil,
                  let to = window.placement?.screen else { continue }
            if screensStable, let from = entries[window.id]?.screen, from != to {
                changes.append(ScreenChange(
                    windowID: window.id, pid: window.pid,
                    appName: window.appName, bundleID: window.bundleID,
                    from: .init(id: from, name: names[from] ?? from),
                    to: .init(id: to, name: names[to] ?? to)))
            }
            entries[window.id] = Entry(screen: to, seen: now)
        }
        entries = entries.filter { now.timeIntervalSince($0.value.seen) < Self.forgetAfter }
        return changes
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

    /// Sürükleme sürerken (sol fare tuşu basılı) gelen değişimler bekletilir,
    /// tuş bırakılınca pencere başına tek değişim olarak çalışır; pencere
    /// başladığı ekrana geri bırakıldıysa hiç çalışmaz.
    private var pending: [ScreenChange] = []
    private var releaseWatch: Timer?

    func fire(_ changes: [ScreenChange]) {
        guard !changes.isEmpty || !pending.isEmpty else { return }
        pending = Self.coalesce(pending + changes)
        if NSEvent.pressedMouseButtons & 1 != 0 {
            watchForRelease()
            return
        }
        let ready = pending.filter { $0.from != $0.to }
        pending = []
        guard !ready.isEmpty else { return }
        reloadIfNeeded()
        for change in ready {
            Log.routing.notice("""
                Screen change: \(change.appName, privacy: .public) window \(change.windowID) \
                \(change.from.id, privacy: .public) → \(change.to.id, privacy: .public)
                """)
            for hook in hooks where hook.matches(change) {
                Self.launch(hook.run, environment: change.environment)
            }
        }
    }

    /// Aynı pencerenin art arda değişimleri tek değişime iner: ilkinin
    /// çıkışı, sonuncusunun varışı (sıra korunur). Çıkış ve varış aynıysa
    /// değişim yine listede kalır; çağıran ayıklar.
    nonisolated static func coalesce(_ changes: [ScreenChange]) -> [ScreenChange] {
        var order: [CGWindowID] = []
        var merged: [CGWindowID: ScreenChange] = [:]
        for change in changes {
            if let first = merged[change.windowID] {
                merged[change.windowID] = ScreenChange(
                    windowID: change.windowID, pid: change.pid, appName: change.appName,
                    bundleID: change.bundleID, from: first.from, to: change.to)
            } else {
                order.append(change.windowID)
                merged[change.windowID] = change
            }
        }
        return order.compactMap { merged[$0] }
    }

    private func watchForRelease() {
        guard releaseWatch == nil else { return }
        releaseWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            Task { @MainActor in
                guard let self else { return }
                self.releaseWatch = nil
                self.fire([])
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

    /// Bu süreyi aşan komut durdurulur.
    nonisolated static let timeout: TimeInterval = 30

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
            // Takılan komut her geçişte birikmesin.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                Log.app.error("Screen hook timed out after \(Int(timeout)) s: \(command, privacy: .public)")
            }
        } catch {
            Log.app.error("Screen hook failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }
}
