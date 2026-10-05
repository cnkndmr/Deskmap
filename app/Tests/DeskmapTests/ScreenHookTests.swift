import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Ekran değişimi kancası: değişimin tespiti ve tanımın eşleşmesi.
struct ScreenHookTests {

    private let builtin = ScreenInfo(id: "builtin", uuid: "B", name: "Built-in Retina Display",
                                     isBuiltin: true, frame: .zero, visibleFrame: .zero)
    private let external = ScreenInfo(id: "external", uuid: "E", name: "External Monitor",
                                      isBuiltin: false, frame: .zero, visibleFrame: .zero)

    private func window(_ id: CGWindowID, on screen: String?, minimized: Bool = false,
                        fullscreen: Bool = false) -> Router.WindowSnapshot {
        var snapshot = Router.WindowSnapshot(
            id: id, pid: 42, appName: "cmux", bundleID: "com.cmuxterm.app", title: "t",
            placement: screen.map { Router.Placement(screen: $0, desktop: 1) },
            frame: nil, isMinimized: minimized)
        if fullscreen {
            snapshot.fullscreen = Router.FullscreenSlot(screen: screen ?? "", space: 9, afterDesktop: 1, order: 0)
        }
        return snapshot
    }

    private func detect(_ old: [Router.WindowSnapshot], _ new: [Router.WindowSnapshot],
                        screens: [ScreenInfo]? = nil) -> [ScreenChange] {
        let both = [builtin, external]
        return ScreenChange.detect(old: old, new: new, oldScreens: screens ?? both, newScreens: both)
    }

    @Test func movedWindowIsDetected() {
        let changes = detect([window(1, on: "external")], [window(1, on: "builtin")])
        #expect(changes.count == 1)
        #expect(changes.first?.from == .init(id: "external", name: "External Monitor"))
        #expect(changes.first?.to == .init(id: "builtin", name: "Built-in Retina Display"))
        #expect(changes.first?.environment["DESKMAP_TO"] == "builtin")
    }

    @Test func sameScreenOrNewWindowIsIgnored() {
        #expect(detect([window(1, on: "external")], [window(1, on: "external")]).isEmpty)
        #expect(detect([window(1, on: "external")], [window(1, on: "external"),
                                                     window(2, on: "builtin")]).isEmpty)
        #expect(detect([], [window(1, on: "builtin")]).isEmpty)
    }

    @Test func minimizedFullscreenOrUnknownIsIgnored() {
        #expect(detect([window(1, on: "external")], [window(1, on: "builtin", minimized: true)]).isEmpty)
        #expect(detect([window(1, on: "external")], [window(1, on: "builtin", fullscreen: true)]).isEmpty)
        #expect(detect([window(1, on: nil)], [window(1, on: "builtin")]).isEmpty)
    }

    @Test func screenListChangeSuppressesHooks() {
        let changes = detect([window(1, on: "external")], [window(1, on: "builtin")],
                             screens: [builtin])
        #expect(changes.isEmpty)
    }

    @Test func hookMatching() throws {
        let change = try #require(detect([window(1, on: "external")], [window(1, on: "builtin")]).first)
        #expect(ScreenHook(app: "cmux", from: "*", to: "builtin", run: "x").matches(change))
        #expect(ScreenHook(app: "com.cmuxterm.app", to: "built-in retina display", run: "x").matches(change))
        #expect(ScreenHook(run: "x").matches(change))
        #expect(!ScreenHook(app: "Safari", run: "x").matches(change))
        #expect(!ScreenHook(to: "external", run: "x").matches(change))
        #expect(!ScreenHook(from: "builtin", run: "x").matches(change))
    }

    @Test func hooksDecodeWithOptionalFields() throws {
        let json = #"[{"run": "echo hi"}, {"app": "cmux", "to": "builtin", "run": "a"}]"#
        let hooks = try JSONDecoder().decode([ScreenHook].self, from: Data(json.utf8))
        #expect(hooks.count == 2)
        #expect(hooks[0].app == nil)
        #expect(hooks[1].to == "builtin")
    }
}
