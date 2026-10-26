import CoreGraphics
import Testing
@testable import Deskmap

/// Toplu aç/kapat: karar mantığı ve yan etkisiz kenar durumları. Pencere
/// kapatma/uygulama açma gerçek sisteme dokunur; yalnız "yapılacak iş yok"
/// ve "bulunamayan pencere" yolları sınanır (uydurma pid, hiçbir uygulama
/// açılmaz).
@MainActor
struct PinBatchLogicTests {

    private func rule(_ id: String, app: String = "Excel") -> Rule {
        Rule(id: id, appName: app, bundleID: "b.\(app)", tokens: [id],
             docked: Destination(screen: "external", desktop: 1), undocked: nil)
    }

    @Test func groupActionPrefersFinishingAHalfOpenGroup() {
        #expect(PinBatch.groupAction(openPinned: 5, closed: 1) == .open)
        #expect(PinBatch.groupAction(openPinned: 0, closed: 7) == .open)
        #expect(PinBatch.groupAction(openPinned: 1, closed: 0) == .close)
    }

    @Test func groupActionIsTotalOverTheSmallGrid() {
        for open in 0...3 {
            for closed in 0...3 {
                let action = PinBatch.groupAction(openPinned: open, closed: closed)
                switch (open, closed) {
                case (_, 1...): #expect(action == .open)
                case (1..., 0): #expect(action == .close)
                default: #expect(action == .none)
                }
            }
        }
    }

    @Test func reopenableKeepsOrderAndOnlyDropsShadowedRules() {
        let rules = ["a", "b", "c", "d"].map { rule($0) }
        #expect(PinBatch.reopenable(rules, shadowed: [:]).map(\.id) == ["a", "b", "c", "d"])
        #expect(PinBatch.reopenable(rules, shadowed: ["b": "x", "d": "y", "zzz": "q"]).map(\.id) == ["a", "c"])
        #expect(PinBatch.reopenable(rules, shadowed: ["a": "", "b": "", "c": "", "d": ""]).isEmpty)
        #expect(PinBatch.reopenable([], shadowed: ["a": "x"]).isEmpty)
    }

    @Test func closingNothingReportsNothing() {
        let store = Store(demo: Document())
        PinBatch.close([], store: store)
        #expect(store.lastError == nil)
    }

    @Test func closingWindowsOfAProcessThatDoesNotExistCountsEachFailure() {
        let store = Store(demo: Document())
        let ghost = pid_t(2_000_000_000)
        let windows = [CGWindowID(900_001), CGWindowID(900_002)].map {
            Router.WindowSnapshot(id: $0, pid: ghost, appName: "Nothing", bundleID: "b.nothing",
                                  title: "t", placement: nil, frame: nil, isMinimized: false)
        }
        PinBatch.close(windows, store: store)
        #expect(store.lastError == L("Could not close %ld windows", 2))
    }

    @Test func openingNothingStartsNothingAndReportsNothing() async {
        let store = Store(demo: Document())
        let screens = ScreenService(displays: { [] })
        let router = Router(store: store, screens: screens, demoWindows: [])
        PinBatch.open([], mode: .docked, router: router, store: store)
        await Task.yield()
        #expect(store.lastError == nil)
    }
}
