import CoreGraphics
import Foundation
@testable import Deskmap

/// Gerçek Router, sahte ekran ve pencere kaynaklarıyla: ekranlar
/// `ScreenService(displays:)`, belge `Store(demo:)`, pencereler her taramada
/// dışarıdan verilir. Tarama `Router.sweepSelection` ile yürür (üretimdeki
/// `sweep` ile aynı girdiler, `Router.select` ve birleştirme); AX/SkyLight
/// çağrılmaz, hiçbir pencere taşınmaz.
@MainActor
final class RouterHarness {

    static let builtin = ScreenService.RawDisplay(
        uuid: "BUILTIN", name: "Built-in", isBuiltin: true,
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1074))
    static let monitor = ScreenService.RawDisplay(
        uuid: "MONITOR", name: "Monitor", isBuiltin: false,
        frame: CGRect(x: 0, y: 1112, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 1112, width: 1920, height: 1050))

    private final class Displays { var list: [ScreenService.RawDisplay] = [] }

    let store: Store
    let screens: ScreenService
    let router: Router
    private let displays = Displays()

    var appName = "Claude"
    var bundleID = "com.anthropic.claudefordesktop"
    /// Açık pencereler: kimlik → başlık.
    var titles: [CGWindowID: String] = [:]
    var now = Date(timeIntervalSince1970: 1_000_000)

    init(rules: [Rule], docked: Bool = true) {
        displays.list = docked ? [Self.builtin, Self.monitor] : [Self.builtin]
        let displays = displays
        screens = ScreenService(displays: { displays.list })
        var document = Document()
        document.rules = rules
        store = Store(demo: document)
        router = Router(store: store, screens: screens, demoWindows: [])
    }

    var rules: [Rule] {
        get { store.document.rules }
        set { store.document.rules = newValue }
    }

    /// Monitör takılı (docked) ya da yalnız dahili ekran (undocked); ekranlar
    /// hemen yatışır.
    var mode: Mode {
        get { screens.mode }
        set {
            displays.list = newValue == .docked ? [Self.builtin, Self.monitor] : [Self.builtin]
            screens.simulateChangeForTesting(settle: true)
        }
    }

    /// Router'ın bağları (arayüze verilen bağlam).
    var bindings: [CGWindowID: Routing.Binding] { router.routingContext.bindings }

    var windows: [Router.WindowSnapshot] {
        titles.keys.sorted().map { id in
            Router.WindowSnapshot(id: id, pid: 1, appName: appName, bundleID: bundleID,
                                  title: titles[id] ?? "", placement: nil, frame: nil,
                                  isMinimized: false)
        }
    }

    /// Bir tarama: açık her pencere → seçilen hedef (yoksa nil).
    func sweep() -> [CGWindowID: Destination?] {
        let matches = router.sweepSelection(windows: windows, now: now)
        var result: [CGWindowID: Destination?] = [:]
        for id in titles.keys { result.updateValue(matches[id]?.destination, forKey: id) }
        return result
    }

    /// Tarama, seçilen kuralın kimliğiyle.
    func sweepRules() -> [CGWindowID: String?] {
        let matches = router.sweepSelection(windows: windows, now: now)
        var result: [CGWindowID: String?] = [:]
        for id in titles.keys { result.updateValue(matches[id]?.ruleID, forKey: id) }
        return result
    }

    func pin(_ id: CGWindowID, _ destination: Destination) {
        router.pinSession(id, destination: destination)
    }

    func unpin(_ id: CGWindowID) { router.unpinSession(id) }

    func wait(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
