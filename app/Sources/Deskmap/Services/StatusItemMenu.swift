import AppKit

/// Menü çubuğu simgesine sağ tık: öndeki pencere pinliyse kısa bir menü
/// açılır (serbest hareket süresi). SwiftUI `MenuBarExtra` sağ tıkı ayrı
/// vermediği için olay, simgenin durum çubuğu penceresinde yerel izleyiciyle
/// yakalanır. Pinli pencere yoksa olaya dokunulmaz.
@MainActor
final class StatusItemMenu: NSObject {

    static let shared = StatusItemMenu()

    private var monitor: Any?
    private var windowID: CGWindowID = 0

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Yerel izleyici ana iş parçacığında çağrılır.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { StatusItemMenu.shared.handle(event) }
            return handled ? nil : event
        }
    }

    /// Sağ tık simgenin penceresindeyse ve öndeki pencere pinliyse menüyü
    /// açar; olay tüketildiyse true.
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

    private func menu() -> NSMenu? {
        let model = AppModel.shared
        guard let window = Self.pinnedFront(
            AX.frontWindowID(), windows: model.router.windows,
            rules: model.store.document.rules, sessionPins: model.router.sessionPins,
            mode: model.screens.mode)
        else { return nil }
        windowID = window.id

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(disabled(Self.header(for: window)))
        menu.addItem(.separator())

        let remaining = model.router.freeMoves[window.id].map { $0.timeIntervalSinceNow } ?? 0
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
            let end = NSMenuItem(title: L("End now"), action: #selector(end(_:)), keyEquivalent: "")
            end.target = self
            menu.addItem(end)
        }
        return menu
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
}
