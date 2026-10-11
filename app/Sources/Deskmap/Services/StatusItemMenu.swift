import AppKit

/// Menü çubuğu simgesine sağ tık: hızlı eylemler. Öndeki pencere sabitse
/// serbest hareket süresi, değilse "olduğu yere sabitle"; ayrıca 15 dakika
/// duraklat / devam et, profil, Ayarlar ve çıkış. Sol tık haritayı açar.
/// SwiftUI `MenuBarExtra` sağ tıkı ayrı vermediği için olay, simgenin durum
/// çubuğu penceresinde yerel izleyiciyle yakalanır.
@MainActor
final class StatusItemMenu: NSObject {

    static let shared = StatusItemMenu()

    private var monitor: Any?
    private var windowID: CGWindowID = 0
    /// "15 dakika duraklat" süresi dolunca devam ettiren görev.
    private var resumeTask: Task<Void, Never>?
    /// Hızlı duraklatmanın süresi.
    nonisolated static let quickPause: TimeInterval = 15 * 60

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Yerel izleyici ana iş parçacığında çağrılır.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { StatusItemMenu.shared.handle(event) }
            return handled ? nil : event
        }
    }

    /// Sağ tık simgenin penceresindeyse menüyü açar; olay tüketildiyse true.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window, window.className.contains("StatusBarWindow"),
              let menu = menu()
        else { return false }
        // Simgenin hemen altı (ekran koordinatı, menünün sol üst köşesi).
        let origin = NSPoint(x: window.frame.minX, y: window.frame.minY - 4)
        DispatchQueue.main.async { menu.popUp(positioning: nil, at: origin, in: nil) }
        return true
    }

    /// Öndeki pencere canlı kurulumda pinliyse o pencere (saf); değilse nil.
    nonisolated static func pinnedFront(
        _ front: CGWindowID?, windows: [Router.WindowSnapshot], rules: [Rule],
        sessionPins: [CGWindowID: Destination], mode: Mode
    ) -> Router.WindowSnapshot? {
        guard let front, let window = windows.first(where: { $0.id == front }),
              Routing.select(rules: rules, sessionPins: sessionPins, mode: mode,
                             windowID: window.id, bundleID: window.bundleID,
                             appName: window.appName, title: window.title, document: window.document) != nil
        else { return nil }
        return window
    }

    /// Menü başlığı (saf): uygulama adı ve kısaltılmış pencere başlığı.
    nonisolated static func header(for window: Router.WindowSnapshot, limit: Int = 48) -> String {
        guard !window.title.isEmpty, window.title != window.appName else { return window.appName }
        let title = window.title.count > limit
            ? String(window.title.prefix(limit - 1)) + "…" : window.title
        return window.appName + " — " + title
    }

    /// Öndeki pencere canlı kurulumda sabit değilse ve bir masaüstündeyse
    /// o pencere (saf): "olduğu yere sabitle" için.
    nonisolated static func unpinnedFront(
        _ front: CGWindowID?, windows: [Router.WindowSnapshot], rules: [Rule],
        sessionPins: [CGWindowID: Destination], mode: Mode
    ) -> Router.WindowSnapshot? {
        guard let front, let window = windows.first(where: { $0.id == front }),
              window.placement != nil, window.fullscreen == nil,
              pinnedFront(front, windows: windows, rules: rules, sessionPins: sessionPins,
                          mode: mode) == nil
        else { return nil }
        return window
    }

    private func menu() -> NSMenu? {
        let model = AppModel.shared
        let store = model.store, router = model.router
        let front = AX.frontWindowID()

        let menu = NSMenu()
        menu.autoenablesItems = false

        let pinned = store.document.rules.filter { $0[model.screens.mode] != nil }.count
        menu.addItem(disabled(store.document.enabled
            ? L("Deskmap on · %@", pinCount(pinned)) : L("Paused · no window is moved")))
        menu.addItem(.separator())

        if let window = Self.pinnedFront(
            front, windows: router.windows, rules: store.document.rules,
            sessionPins: router.sessionPins, mode: model.screens.mode) {
            windowID = window.id
            menu.addItem(disabled(Self.header(for: window)))

            let remaining = router.freeMoves[window.id].map { $0.timeIntervalSinceNow } ?? 0
            if remaining > 0 {
                menu.addItem(disabled(L("Free to move · %@ left", Router.freeMoveRemaining(remaining))))
            }
            let durations = NSMenu()
            durations.autoenablesItems = false
            for duration in Router.freeMoveDurations {
                let item = NSMenuItem(title: FreeMoveRow.label(duration),
                                      action: #selector(grant(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = duration
                durations.addItem(item)
            }
            let free = NSMenuItem(title: L("Free move"), action: nil, keyEquivalent: "")
            free.submenu = durations
            menu.addItem(free)
            if remaining > 0 {
                menu.addItem(item(L("End now"), #selector(end(_:))))
            }
            menu.addItem(.separator())
        } else if let window = Self.unpinnedFront(
            front, windows: router.windows, rules: store.document.rules,
            sessionPins: router.sessionPins, mode: model.screens.mode) {
            windowID = window.id
            menu.addItem(disabled(Self.header(for: window)))
            menu.addItem(item(L("Pin it where it is"), #selector(pinFront(_:))))
            menu.addItem(.separator())
        }

        if store.document.enabled {
            menu.addItem(item(L("Pause for 15 minutes"), #selector(pause(_:))))
        } else {
            menu.addItem(item(L("Resume"), #selector(resume(_:))))
        }

        if store.profiles.count > 1 {
            let profiles = NSMenu()
            profiles.autoenablesItems = false
            for profile in store.profiles {
                let entry = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = profile.id
                entry.state = profile.id == store.document.activeProfileID ? .on : .off
                profiles.addItem(entry)
            }
            let item = NSMenuItem(title: L("Profile"), action: nil, keyEquivalent: "")
            item.submenu = profiles
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(item(L("Settings…"), #selector(settings(_:))))
        menu.addItem(item(L("Quit Deskmap"), #selector(quit(_:))))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func grant(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else { return }
        AppModel.shared.router.allowFreeMove([windowID], for: duration)
    }

    @objc private func end(_ sender: NSMenuItem) {
        AppModel.shared.router.endFreeMove([windowID])
    }

    @objc private func pinFront(_ sender: NSMenuItem) {
        let model = AppModel.shared
        MultiPinBar.pinWhereTheyAre([windowID], store: model.store, router: model.router,
                                    screens: model.screens)
    }

    @objc private func pause(_ sender: NSMenuItem) {
        let store = AppModel.shared.store
        store.document.enabled = false
        resumeTask?.cancel()
        let armed = store.enabledChanges
        resumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.quickPause * 1_000_000_000))
            guard !Task.isCancelled,
                  Self.autoResumes(armedAt: armed, changes: store.enabledChanges,
                                   enabled: store.document.enabled)
            else { return }
            store.document.enabled = true
        }
    }

    /// Hızlı duraklatmanın süresi dolunca devam edilir mi (saf): yalnız
    /// duraklatmadan beri anahtar başka yoldan değişmediyse. Arada açılıp
    /// yeniden kapatılan Deskmap süresiz duraklatılmıştır.
    nonisolated static func autoResumes(armedAt: Int, changes: Int, enabled: Bool) -> Bool {
        !enabled && changes == armedAt
    }

    @objc private func resume(_ sender: NSMenuItem) {
        resumeTask?.cancel()
        resumeTask = nil
        AppModel.shared.store.document.enabled = true
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppModel.shared.store.switchProfile(to: id)
    }

    @objc private func settings(_ sender: NSMenuItem) {
        SettingsWindow.shared.show(store: AppModel.shared.store)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
