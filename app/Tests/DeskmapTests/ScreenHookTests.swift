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

    /// İlk taramayı `old` ile (ekran listesi `screens`), ikinciyi `new` ile yapar.
    private func detect(_ old: [Router.WindowSnapshot], _ new: [Router.WindowSnapshot],
                        screens: [ScreenInfo]? = nil) -> [ScreenChange] {
        let both = [builtin, external]
        var memory = ScreenMemory()
        _ = memory.update(windows: old, screens: screens ?? both)
        return memory.update(windows: new, screens: both)
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

    /// Yanıt vermeyen uygulamanın penceresi bir iki tarama listeden düşer;
    /// geri geldiğinde geçiş kaybolmamalı.
    @Test func windowMissingFromSomeScansStillFires() {
        let both = [builtin, external]
        let start = Date()
        var memory = ScreenMemory()
        _ = memory.update(windows: [window(1, on: "builtin")], screens: both, now: start)
        #expect(memory.update(windows: [], screens: both, now: start + 2).isEmpty)
        let changes = memory.update(windows: [window(1, on: "external")], screens: both, now: start + 4)
        #expect(changes.map(\.to.id) == ["external"])
    }

    @Test func longGoneWindowIsForgotten() {
        let both = [builtin, external]
        let start = Date()
        var memory = ScreenMemory()
        _ = memory.update(windows: [window(1, on: "builtin")], screens: both, now: start)
        _ = memory.update(windows: [], screens: both, now: start + ScreenMemory.forgetAfter + 1)
        #expect(memory.entries.isEmpty)
        #expect(memory.update(windows: [window(1, on: "external")], screens: both,
                              now: start + ScreenMemory.forgetAfter + 2).isEmpty)
    }

    /// Her geçiş bir kez sayılır: gidip gelme iki olay, ara taramalar sessiz.
    @Test func backAndForthCountsEachCrossingOnce() {
        let both = [builtin, external]
        var memory = ScreenMemory()
        var all: [ScreenChange] = []
        for screen in ["builtin", "builtin", "external", "external", "builtin"] {
            all += memory.update(windows: [window(1, on: screen)], screens: both)
        }
        #expect(all.map(\.to.id) == ["external", "builtin"])
    }

    /// Simge durumundan başka ekranda dönen pencere: dönüşte tetikler.
    @Test func restoredOnOtherScreenFires() {
        let both = [builtin, external]
        var memory = ScreenMemory()
        _ = memory.update(windows: [window(1, on: "builtin")], screens: both)
        #expect(memory.update(windows: [window(1, on: "builtin", minimized: true)], screens: both).isEmpty)
        #expect(memory.update(windows: [window(1, on: "external")], screens: both).count == 1)
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

/// Sürükleme sırasında biriken değişimlerin birleşmesi.
struct ScreenHookCoalesceTests {
    private func change(_ id: CGWindowID, _ from: String, _ to: String) -> ScreenChange {
        ScreenChange(windowID: id, pid: 1, appName: "a", bundleID: "b",
                     from: .init(id: from, name: from), to: .init(id: to, name: to))
    }

    @Test func dragThereAndBackCancelsOut() {
        let merged = ScreenHooks.coalesce([change(1, "builtin", "external"),
                                           change(1, "external", "builtin")])
        #expect(merged.count == 1)
        #expect(merged.filter { $0.from != $0.to }.isEmpty)
    }

    @Test func multipleHopsKeepFirstOriginAndLastTarget() {
        let merged = ScreenHooks.coalesce([change(1, "builtin", "external"),
                                           change(2, "external", "builtin"),
                                           change(1, "external", "external-2")])
        #expect(merged.map(\.windowID) == [1, 2])
        #expect(merged[0].from.id == "builtin" && merged[0].to.id == "external-2")
        #expect(merged[1].to.id == "builtin")
    }
}
